defmodule Slab.Query do
  @moduledoc """
  Builds and runs Ecto queries for `Slab.table/1` query mode.

  Query support is compiled in only when Ecto is available (it is an optional
  dependency). Without Ecto, `fetch/4` raises at runtime with instructions.

  Everything URL-driven is whitelisted and cast before it touches a query:
  sort fields come from `<:col sortable>` declarations, and cursor values are
  cast with `Ecto.Type.cast/2` against the schema's field types — invalid
  input is ignored, never interpolated.
  """

  alias Slab.Helpers.Params

  if Code.ensure_loaded?(Ecto.Query) do
    import Ecto.Query

    @doc """
    Runs the queryable through the repo, applying whitelisted sorting and
    pagination from `params`.

    Returns `{records, has_next?}`. Pagination fetches one extra record to
    detect whether a next page exists, avoiding a count query.

    ## Options

      * `:sortable_fields` - atoms whitelisted for ORDER BY
      * `:filterable_cols` - columns whitelisted for WHERE, as maps of
        `%{field: atom, filter: fun | nil}`
      * `:paginate` - `nil`, `:page`, or `:cursor`
      * `:per_page` - default page size
      * `:max_per_page` - upper clamp for the URL `per_page` param
    """
    def fetch(queryable, repo, params, opts) do
      sortable_fields = Map.get(opts, :sortable_fields, [])

      queryable =
        apply_filters(
          queryable,
          params,
          Map.get(opts, :filterable_cols, []),
          schema_module(queryable)
        )

      case Map.get(opts, :paginate) do
        nil ->
          {queryable |> apply_sort(params, sortable_fields) |> repo.all(), false}

        :page ->
          per_page = per_page(params, opts)
          page = Params.page(params)

          queryable
          |> apply_sort(params, sortable_fields)
          |> offset(^((page - 1) * per_page))
          |> fetch_with_extra(repo, per_page)

        :cursor ->
          per_page = per_page(params, opts)
          sort_field = sort_field(params, sortable_fields)
          direction = direction(params, sort_field)
          schema = schema_module(queryable)

          queryable
          |> apply_cursor(params, sort_field, direction, schema)
          |> order_by(^cursor_order(sort_field, direction))
          |> fetch_with_extra(repo, per_page)
      end
    end

    @doc """
    Counts the records matching the current filters, ignoring sorting and
    pagination. Backs the "Showing X to Y of Z entries" summary and the
    numbered page links in page mode.
    """
    def count(queryable, repo, params, filterable_cols) do
      queryable
      |> apply_filters(params, filterable_cols, schema_module(queryable))
      |> repo.aggregate(:count)
    end

    @doc """
    Applies `order_by` from the `sort` and `sort_direction` params.

    Only fields in `sortable_fields` (a list of atoms, derived from
    `<:col sortable>` declarations) are ever compiled into the query —
    anything else in the URL is ignored.
    """
    def apply_sort(queryable, params, sortable_fields) do
      case sort_field(params, sortable_fields) do
        nil ->
          queryable

        sort_field ->
          direction = direction(params, sort_field)
          order_by(queryable, [q], [{^direction, field(q, ^sort_field)}])
      end
    end

    @doc """
    Applies WHERE conditions from the `filter` URL params.

    Only whitelisted columns are ever filtered. Each filter is one of:

      * a custom 2-arity function from `<:col filter={...}>` — called with
        `(queryable, raw_value)` and free to add joins or any Ecto condition
      * a bare value (`filter[name]=ada`) — strings match with a
        case-insensitive contains, other types cast to an equality check
      * a list of values (`filter[role][]=a&filter[role][]=b`, from
        multi-select inputs) — becomes a `field IN (...)` condition
      * an operator map (`filter[age][gte]=21`) — supported operators are
        `eq`, `neq`, `gt`, `gte`, `lt`, `lte`, and `contains`

    Declarative values are cast with `Ecto.Type.cast/2` against the schema's
    field type; anything that fails to cast is ignored, never interpolated.
    """
    def apply_filters(queryable, params, filterable_cols, schema) do
      case Map.get(params, "filter") do
        %{} = filters ->
          Enum.reduce(filterable_cols, queryable, fn col, acc ->
            apply_filter(acc, col, Map.get(filters, to_string(col.field)), schema)
          end)

        _no_filters ->
          queryable
      end
    end

    @doc """
    Returns the `Ecto.Schema` module behind a queryable — the module itself,
    or the source schema of an `%Ecto.Query{}`. Returns `nil` when there is
    no schema to reflect on.
    """
    def schema_module(%Ecto.Query{from: %{source: {_source, schema}}}), do: schema
    def schema_module(schema) when is_atom(schema), do: schema
    def schema_module(_queryable), do: nil

    @doc """
    Returns the values of an `Ecto.Enum` field, or `nil` when the field is
    not an enum. Backs automatic select options in the Filters tab.
    """
    def enum_values(schema, field) when is_atom(schema) and not is_nil(schema) do
      case schema.__schema__(:type, field) do
        {:parameterized, {Ecto.Enum, _config}} -> Ecto.Enum.values(schema, field)
        {:parameterized, Ecto.Enum, _config} -> Ecto.Enum.values(schema, field)
        _type -> nil
      end
    end

    def enum_values(_schema, _field), do: nil

    defp apply_filter(queryable, _col, empty, _schema) when empty in [nil, ""], do: queryable

    defp apply_filter(queryable, %{filter: custom}, value, _schema)
         when is_function(custom, 2) do
      custom.(queryable, value)
    end

    defp apply_filter(queryable, %{field: field}, value, schema) when is_binary(value) do
      case field_type(schema, field) do
        :string -> where(queryable, ^contains_condition(field, value))
        nil -> queryable
        _type -> apply_operator(queryable, field, "eq", value, schema)
      end
    end

    # Multi-select filters arrive as lists (filter[role][]=a&filter[role][]=b)
    # and become an IN condition. Values that fail casting are dropped; if
    # none survive, the filter is skipped.
    defp apply_filter(queryable, %{field: field}, values, schema) when is_list(values) do
      cast_values =
        values
        |> Enum.reject(&(&1 == ""))
        |> Enum.flat_map(fn value ->
          case is_binary(value) && cast_field(schema, field, value) do
            {:ok, cast_value} -> [cast_value]
            _invalid -> []
          end
        end)

      if cast_values == [] do
        queryable
      else
        where(queryable, [q], field(q, ^field) in ^cast_values)
      end
    end

    defp apply_filter(queryable, %{field: field}, %{} = operators, schema) do
      Enum.reduce(operators, queryable, fn {operator, value}, acc ->
        apply_operator(acc, field, operator, value, schema)
      end)
    end

    defp apply_filter(queryable, _col, _value, _schema), do: queryable

    @comparison_operators ~w(eq neq gt gte lt lte)

    defp apply_operator(queryable, field, operator, value, schema)
         when operator in @comparison_operators and is_binary(value) do
      with type when not is_nil(type) <- field_type(schema, field),
           {:ok, cast_value} <- Ecto.Type.cast(type, value) do
        where(queryable, ^comparison_condition(operator, field, cast_value))
      else
        _invalid -> queryable
      end
    end

    defp apply_operator(queryable, field, "contains", value, schema) when is_binary(value) do
      if field_type(schema, field) == :string do
        where(queryable, ^contains_condition(field, value))
      else
        queryable
      end
    end

    defp apply_operator(queryable, _field, _operator, _value, _schema), do: queryable

    defp comparison_condition("eq", f, v), do: dynamic([q], field(q, ^f) == ^v)
    defp comparison_condition("neq", f, v), do: dynamic([q], field(q, ^f) != ^v)
    defp comparison_condition("gt", f, v), do: dynamic([q], field(q, ^f) > ^v)
    defp comparison_condition("gte", f, v), do: dynamic([q], field(q, ^f) >= ^v)
    defp comparison_condition("lt", f, v), do: dynamic([q], field(q, ^f) < ^v)
    defp comparison_condition("lte", f, v), do: dynamic([q], field(q, ^f) <= ^v)

    # Case-insensitive contains, portable across Postgres, MySQL, and SQLite
    # (ilike is Postgres-only). The ESCAPE clause is explicit because SQLite
    # has no default escape character for LIKE.
    defp contains_condition(field, value) do
      pattern = "%" <> escape_like(String.downcase(value)) <> "%"

      dynamic([q], fragment("LOWER(?) LIKE ? ESCAPE '\\'", field(q, ^field), ^pattern))
    end

    # LIKE wildcards in user input are literals, not patterns
    defp escape_like(value) do
      String.replace(value, ~r/[\\%_]/, fn match -> "\\" <> match end)
    end

    defp field_type(nil, _field), do: nil
    defp field_type(schema, field), do: schema.__schema__(:type, field)

    # Fetches one extra record beyond per_page to detect a next page
    defp fetch_with_extra(queryable, repo, per_page) do
      records =
        queryable
        |> limit(^(per_page + 1))
        |> repo.all()

      {Enum.take(records, per_page), length(records) > per_page}
    end

    defp per_page(params, opts) do
      Params.per_page(params, Map.get(opts, :per_page, 25), Map.get(opts, :max_per_page, 100))
    end

    defp sort_field(params, sortable_fields) do
      sort = Map.get(params, "sort")
      Enum.find(sortable_fields, fn field -> to_string(field) == sort end)
    end

    defp direction(_params, nil), do: :asc

    defp direction(params, _sort_field) do
      if Map.get(params, "sort_direction") == "desc", do: :desc, else: :asc
    end

    # Cursor (keyset) pagination. The order always ends with the primary key
    # as a tiebreaker so the traversal is a total order.
    defp cursor_order(nil, direction), do: [{direction, :id}]
    defp cursor_order(sort_field, direction), do: [{direction, sort_field}, {direction, :id}]

    defp apply_cursor(queryable, params, sort_field, direction, schema) do
      case decode_cursor(Map.get(params, "after"), sort_field, schema) do
        {:ok, %{id: id, value: value}} when not is_nil(value) ->
          where(queryable, ^value_condition(sort_field, direction, value, id))

        {:ok, %{id: id}} ->
          where(queryable, ^id_condition(direction, id))

        :error ->
          queryable
      end
    end

    # A cursor is `after[id]` plus, when sorting, `after[value]` — the sort
    # field value of the last-seen record. Values are cast against the
    # schema's field types; anything that fails to cast drops the cursor
    # (falling back to the first page) rather than erroring.
    defp decode_cursor(%{"id" => raw_id} = after_params, sort_field, schema) do
      with {:ok, id} <- cast_field(schema, :id, raw_id),
           {:ok, value} <- decode_cursor_value(after_params, sort_field, schema) do
        {:ok, %{id: id, value: value}}
      else
        _invalid -> :error
      end
    end

    defp decode_cursor(_after_params, _sort_field, _schema), do: :error

    defp decode_cursor_value(%{"value" => raw}, sort_field, schema)
         when is_binary(raw) and not is_nil(sort_field) do
      cast_field(schema, sort_field, raw)
    end

    defp decode_cursor_value(_after_params, _sort_field, _schema), do: {:ok, nil}

    defp cast_field(nil, _field, _value), do: :error

    defp cast_field(schema, field, value) do
      case schema.__schema__(:type, field) do
        nil -> :error
        type -> Ecto.Type.cast(type, value)
      end
    end

    defp id_condition(:asc, id), do: dynamic([q], q.id > ^id)
    defp id_condition(:desc, id), do: dynamic([q], q.id < ^id)

    defp value_condition(sort_field, :asc, value, id) do
      dynamic(
        [q],
        field(q, ^sort_field) > ^value or (field(q, ^sort_field) == ^value and q.id > ^id)
      )
    end

    defp value_condition(sort_field, :desc, value, id) do
      dynamic(
        [q],
        field(q, ^sort_field) < ^value or (field(q, ^sort_field) == ^value and q.id < ^id)
      )
    end
  else
    def fetch(_queryable, _repo, _params, _opts) do
      raise """
      Slab query mode requires Ecto, which is not available.

      Add it to your dependencies:

          {:ecto, "~> 3.0"}

      Or pass pre-fetched records instead: <Slab.table data={@records} ...>
      """
    end

    def count(_queryable, _repo, _params, _filterable_cols) do
      raise "Slab query mode requires Ecto, which is not available. Add {:ecto, \"~> 3.0\"} to your dependencies."
    end

    def apply_sort(queryable, _params, _sortable_fields), do: queryable

    def apply_filters(queryable, _params, _filterable_cols, _schema), do: queryable

    def schema_module(schema) when is_atom(schema), do: schema
    def schema_module(_queryable), do: nil

    def enum_values(_schema, _field), do: nil
  end
end
