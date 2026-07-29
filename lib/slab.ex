defmodule Slab do
  @moduledoc """
  A data table component for Phoenix LiveView.

  A table is composed from slots — every optional region is declared by the
  presence of a slot, and nothing renders that wasn't declared:

    * `<:column>` — one per column, with automatic cell rendering by Ecto
      field type, custom bodies, and URL-driven sorting
    * `<:column_checkbox>` — row-selection checkboxes stored in the URL
    * `<:filter>` — whitelists a field for URL-driven filtering and defines
      its input
    * `<:tab>` — the tab bar above the table (Filters, Columns, Share,
      Export, or fully custom tabs), in declaration order
    * `<:pagination>` — offset or keyset pagination

  All table state — sorting, filters, pagination, column layout, row
  selection — lives in the URL. The component patches query params; the
  parent LiveView reacts to `handle_params/3`. Callers pass the current
  `uri` and `params` (both from `handle_params/3`) to enable these features.

  ## Usage

  Render a table with `Slab.table/1`. Data comes from one of two modes:

  **List mode** — pass pre-fetched records via `data`. An optional `schema`
  (an `Ecto.Schema` module) makes values render according to their field
  type; without one, values render as strings:

      <Slab.table id="users-table" data={@users} schema={MyApp.User}>
        <:column field={:id} />
        <:column field={:name} />
        <:column field={:email} />
        <:column field={:inserted_at} />
      </Slab.table>

  **Query mode** — omit `data` and Slab fetches for you. `schema` becomes
  the source to query (an `Ecto.Schema` module or an `%Ecto.Query{}`), run
  through `repo`:

      <Slab.table id="users-table" schema={MyApp.User} repo={MyApp.Repo} uri={@uri} params={@params}>
        <:column field={:name} sortable />
        <:column field={:email} />
      </Slab.table>

  The repo can also be configured once, globally:

      config :slab, repo: MyApp.Repo

  Passing an `%Ecto.Query{}` lets the caller scope what the table can ever
  see (authorization, multi-tenancy) while Slab layers sorting and
  filtering on top:

      <Slab.table id="users-table" schema={from u in MyApp.User, where: u.org_id == ^@org.id} ...>

  A `<:column>` with no body renders the record's `field` automatically.

  ### Custom cell rendering

  Give a `<:column>` a body to take over rendering. The body receives the
  record via `:let`. A `field` is optional — omit it for virtual columns
  like actions, and give the column a `label` instead:

      <Slab.table id="users-table" data={@users}>
        <:column :let={user} field={:name}>{String.upcase(user.name)}</:column>
        <:column :let={user} label="Actions">
          <.link navigate={~p"/users/\#{user}/edit"}>Edit</.link>
        </:column>
      </Slab.table>

  ### Sorting

  Mark columns as `sortable` and pass the current `uri` and `params`. Sortable
  headers render as patch links that set the `sort` and `sort_direction`
  query params. In query mode Slab requeries with the new sort automatically —
  only fields declared `sortable` are ever compiled into `ORDER BY`, so URL
  tampering cannot sort by arbitrary columns. In list mode, the parent
  LiveView reacts in `handle_params/3` by requerying:

      def handle_params(params, uri, socket) do
        socket =
          socket
          |> assign(:uri, uri)
          |> assign(:params, params)
          |> assign(:users, list_users(params))

        {:noreply, socket}
      end

      <Slab.table id="users-table" data={@users} uri={@uri} params={@params}>
        <:column field={:name} sortable />
        <:column field={:email} sortable />
      </Slab.table>

  ### Filtering

  Declare a `<:filter>` per filterable field and Slab translates `filter`
  URL params into WHERE conditions in query mode. Values are cast with
  `Ecto.Type.cast/2` against the schema's field types — strings match with
  a case-insensitive contains, other types by equality, and an operator
  form enables comparisons. Only declared fields are ever filtered; invalid
  values and unknown operators are ignored:

      <Slab.table id="users-table" schema={MyApp.User} repo={MyApp.Repo} uri={@uri} params={@params}>
        <:tab name="filters" />
        <:filter field={:name} />
        <:filter field={:inserted_at} />
        <:column field={:name} />
        <:column field={:inserted_at} />
      </Slab.table>

      ?filter[name]=ada                          # WHERE name ILIKE %ada%
      ?filter[active]=true                       # WHERE active = true
      ?filter[inserted_at][gte]=2026-01-01       # WHERE inserted_at >= ...

  Operators: `eq`, `neq`, `gt`, `gte`, `lt`, `lte`, `contains`.

  Filters are field-level, not column-level — a `<:filter>` needs no
  matching `<:column>`, so you can filter on fields the table never shows.

  For custom logic — full-text search, filtering through associations —
  pass a 2-arity `query` function. It receives the queryable and the raw
  param value, and can add joins or any Ecto condition:

      <:filter field={:organization} query={fn query, value ->
        from u in query,
          join: o in assoc(u, :organization),
          where: ilike(o.name, ^"%\#{value}%")
      end} />

  Each `<:filter>` also defines its input in the Filters tab (see
  [Tabs](#module-tabs)). The input type derives from the schema — booleans
  and `Ecto.Enum` fields get a select with derived options, everything else
  a text input — and the `type`, `label`, `options`, `placeholder`,
  `min_chars`, and `debounce` attrs override the defaults. `type="hidden"`
  whitelists the field without rendering an input — for filters driven from
  elsewhere on the page.

  ### External filter UI

  The contract between filter UI and the table is the URL, so any component
  that patches `filter[field]` params drives the table — the table only
  requires the field to be whitelisted by a `<:filter>`. `Slab.filter/1`
  works standalone anywhere on the page:

      <Slab.filter id="filter-name" schema={MyApp.User} field={:name}
        uri={@uri} params={@params} label="Name" placeholder="Search names..." />

      <Slab.table id="users-table" schema={MyApp.User} repo={MyApp.Repo} uri={@uri} params={@params}>
        <:filter field={:name} type="hidden" />
        <:column field={:name} sortable />
      </Slab.table>

  Components not owned by Slab integrate the same way: patch the URL with
  `filter[field]=value` (or `filter[field][]=value` for multi-selects, and
  `filter[field][op]=value` for operators) — `filter_path/3` builds those
  paths. State stays in the URL, so sharing, back-button, and exports keep
  working with any filter UI.

  ### Pagination

  Declare a `<:pagination>` slot with one of two modes. `:page` is classic
  offset pagination driven by `page` and `per_page` URL params — it works
  in both data modes (in list mode the list is sliced in memory):

      <Slab.table id="users-table" schema={MyApp.User} repo={MyApp.Repo} uri={@uri} params={@params}>
        <:column field={:name} />
        <:pagination mode={:page} per_page={25} />
      </Slab.table>

  `:cursor` is keyset pagination driven by an `after` URL param — built for
  constantly-updated data, where new inserts would shift offset pages
  underneath the viewer. Cursors paginate relative to the last-seen record,
  stay correct as records land, avoid deep-offset scans, and need no count
  query. Query mode only; navigation is First/Next (no random page access):

      <Slab.table id="users-table" schema={MyApp.User} repo={MyApp.Repo} uri={@uri} params={@params}>
        <:column field={:inserted_at} sortable />
        <:pagination mode={:cursor} per_page={25} />
      </Slab.table>

  Cursors are readable, not opaque: `?after[id]=...&after[value]=...` holds
  the last record's id (always the ordering tiebreaker) plus its sort-field
  value when sorting. Both are cast against the schema's field types with
  `Ecto.Type.cast/2` — a tampered cursor falls back to the first page rather
  than erroring or reaching the query. Changing the sort resets pagination
  in either mode.

  Page mode renders a full footer: a "Showing X to Y of Z entries" summary,
  numbered page links with ellipses, and a page-size dropdown (see the
  `options` attr). The total comes from a count query cached on the current
  filters — page and sort changes never re-count. Cursor mode never runs a
  count query at all; it detects a next page by fetching one extra record.

  ### Tabs

  Declare `<:tab>` slots to render a tab bar above the table. Tabs render
  in declaration order. Four names have built-in content:

    * `<:tab name="filters" />` — one input per non-hidden `<:filter>`, with
      a badge showing the active filter count; requires `uri`
    * `<:tab name="columns" />` — a picker driving the `columns[]` URL param
      (see [Column visibility and order](#module-column-visibility-and-order));
      requires `uri`
    * `<:tab name="share" />` — a copyable link to the exact current view;
      requires `uri`
    * `<:tab name="export" />` — CSV downloads (see
      [Exporting](#module-exporting)); takes a `limit` attr

  A body on a built-in tab replaces its default content (the badge count
  stays params-derived), and any other `name` defines a custom tab — give
  it a `label`, an optional `icon` and `count`, and a body:

      <:tab name="filters" />
      <:tab name="help" label="Help" icon="bookmark-outline">
        <p>Contact #data-team for access questions.</p>
      </:tab>

  No `<:tab>` slots, no tab bar. `tabs/1`, `share/1`, and `filter/1` remain
  public for composing custom layouts outside the table.

  ### Exporting

  The Export tab downloads the table as CSV, generated server-side and
  delivered through the browser — no extra routes or setup. Two buttons:

    * **Download current page** — the rows exactly as displayed
    * **Download all data** — the first `limit` rows (default 1000) of the
      current filtered, sorted result; when the total exceeds the limit the
      button reads "Download first N rows" instead

  Exports honor the current filters, sort, and column selection. Columns
  render their raw field values (see `Slab.Export.csv/2` for the value
  formats), or the result of their `export_value` function when given — a
  1-arity function receiving the record. That is how computed columns (a
  body but no `field`) join an export; without a `field` or an
  `export_value`, a virtual column — like action links — is skipped. The
  file travels over the LiveView socket, so keep `limit` in the thousands,
  not the millions:

      <Slab.table id="users-table" schema={MyApp.User} repo={MyApp.Repo} uri={@uri} params={@params}>
        <:tab name="export" limit={5000} />
        <:column field={:name} />
        <:column :let={user} label="Products" export_value={fn user -> Enum.map_join(user.products, ", ", & &1.name) end}>
          <.product_badges products={user.products} />
        </:column>
        <:pagination mode={:page} />
      </Slab.table>

  The download button uses a colocated hook — register Slab's hooks once in
  `assets/js/app.js` (see the README's installation section).

  ### Column visibility and order

  The `columns[]` URL param controls which columns render, *in param
  order* — column layout is shareable user state like everything else:

      ?columns[]=email&columns[]=name    # email and name only, email first

  Names are matched against the declared columns (a column's key is its
  `field`, or a slug of its `label` for virtual columns like "Actions" →
  `actions`); unknown names are ignored, and no matches falls back to the
  default view. With no param, columns render in declaration order minus
  those marked `optional`:

      <Slab.table id="users-table" ...>
        <:tab name="columns" />
        <:column field={:name} />
        <:column field={:email} optional />
      </Slab.table>

  The Columns tab renders a multi-select picker driving the param; its
  selection order becomes the column order. Changing columns never resets
  pagination — the result set is unchanged. Sorting and filtering are
  unaffected by visibility: a hidden column's filter still applies.

  ### Row selection

  Declare `<:column_checkbox />` and pass the current `uri`. It renders as
  the first column, always visible (it is not addressable through the
  Columns tab or the `columns[]` param), with checked row IDs stored in the
  `checked` query param via `push_patch`:

      <Slab.table id="users-table" data={@users} uri={@uri}>
        <:column_checkbox />
        <:column field={:name} />
      </Slab.table>

  Read selections back with `get_checked_ids/1`, `get_checked_values/3`, and
  `checked?/1`. For selections spanning paginated results, see
  `get_selected_and_missing_ids/3`.

  ### Inline editing

  Mark columns as `editable` and pass an `on_save` function. Editable
  columns render their input directly in the cell — there is no edit mode —
  and a save column (no heading) appears at the end of the table. Editing a
  value highlights the row's save button; clicking it (or pressing Enter)
  calls `on_save` once with the row's record and the changed fields:

      <Slab.table id="users-table" schema={MyApp.User} repo={MyApp.Repo}
        uri={@uri} params={@params} on_save={&save_user/2}>
        <:column field={:name} editable />
        <:column field={:role} editable />
        <:column field={:inserted_at} />
      </Slab.table>

      def save_user(user, params) do
        user
        |> MyApp.User.changeset(params)
        |> MyApp.Repo.update()
      end

  Slab never writes to the database itself: `on_save` receives the record
  and a map of only the changed fields, with raw string values
  (`%{"name" => "Ada"}`) — cast them with your own changeset. Return
  `{:ok, updated_record}` to clear the row's pending state and render the
  updated record in place, or `{:error, changeset_or_message}` to keep the
  edits and show the error under the row.

  Input types derive from the schema — booleans and `Ecto.Enum` fields get
  a select, everything else a text input. Text inputs read as plain text
  until focused, keeping the table scannable. Multiple columns can change
  before one save, and each row saves independently. Pending edits are
  component state, not URL state: they survive re-renders, sorting, and
  filtering, but not a page reload.

  ## Styling

  Markup is styled with Tailwind CSS utility classes. Ensure your app's
  Tailwind configuration includes this dependency's files so the classes are
  generated — see the README for details.
  """

  use Phoenix.Component

  import Slab.Components, only: [icon: 1]

  alias Phoenix.LiveView.JS

  @doc """
  Renders a data table composed from slots.

  Every optional region is declared by the presence of a slot — columns,
  row-selection checkboxes, filters, tabs, pagination. See the module docs
  for full usage of each. Interactive features are handled internally by a
  live component; sorting is handled with patch links. URL-driven features
  require the current `uri` and `params`.

  Data comes from one of two modes:

    * **List mode** — pass `data` with pre-fetched records. `schema` is an
      optional rendering hint.
    * **Query mode** — omit `data` and pass `schema` (an `Ecto.Schema` module
      or an `%Ecto.Query{}`) plus a `repo`; Slab runs the query itself,
      applying sorting, filtering, and pagination from `params`. The repo
      may also be set globally with `config :slab, repo: MyApp.Repo`.

  ## Examples

      <Slab.table id="users-table" data={@users} uri={@uri} params={@params}>
        <:column field={:name} sortable />
        <:column :let={user} label="Actions">
          <.link navigate={"/users/\#{user.id}/edit"}>Edit</.link>
        </:column>
      </Slab.table>

      <Slab.table id="users-table" schema={MyApp.User} repo={MyApp.Repo} uri={@uri} params={@params}>
        <:tab name="filters" />
        <:tab name="share" />
        <:filter field={:name} placeholder="Search names..." />
        <:column_checkbox />
        <:column field={:name} sortable />
        <:pagination mode={:page} per_page={25} />
      </Slab.table>
  """
  attr(:id, :string, required: true)

  attr(:data, :list,
    default: nil,
    doc: "pre-fetched records to render; omit to have Slab query via schema and repo"
  )

  attr(:schema, :any,
    default: nil,
    doc:
      "an Ecto.Schema module or Ecto.Query; renders cell values by field type, " <>
        "and in query mode is the source Slab fetches from"
  )

  attr(:repo, :atom,
    default: nil,
    doc:
      "the Ecto.Repo used to run queries in query mode; " <>
        "falls back to `config :slab, repo: MyApp.Repo`"
  )

  attr(:uri, :string,
    default: nil,
    doc: "the current request URI, from handle_params/3; required by URL-driven slots"
  )

  attr(:params, :map,
    default: %{},
    doc:
      "the current request params, from handle_params/3; carries sort, filter, " <>
        "pagination, column, and selection state"
  )

  attr(:on_save, :any,
    default: nil,
    doc:
      "2-arity function (record, changed_params) -> {:ok, record} | {:error, error} " <>
        "called when a row's save button is clicked; required when any column is " <>
        "editable — Slab never writes to the database itself"
  )

  slot :tab,
    doc:
      "tabs rendered above the table, in declaration order; the names filters, " <>
        "columns, share, and export have built-in content (a body replaces it), " <>
        "any other name is a custom tab requiring a label and a body" do
    attr(:name, :string, required: true, doc: "the tab type, or a custom tab's identity")

    attr(:label, :string,
      doc: "the tab label; derived for built-in names, required for custom tabs"
    )

    attr(:icon, :string,
      doc:
        "icon rendered before the label; derived for built-in names — see " <>
          "`Slab.Components.icon/1` for the available names"
    )

    attr(:count, :integer, doc: "badge count for custom tabs; built-in tabs compute their own")

    attr(:limit, :integer,
      doc:
        "export only: maximum rows in a full-data export (default 1000); the " <>
          "download travels over the LiveView socket, so keep it modest"
    )
  end

  slot :filter,
    doc:
      "one slot per filterable field; whitelists the field for filter URL params " <>
        "in query mode and defines its input in the Filters tab" do
    attr(:field, :atom, required: true, doc: "the field to filter on")

    attr(:label, :string,
      doc: "label for the Filters tab input; defaults to the humanized field name"
    )

    attr(:type, :string,
      values: ["text", "select", "multiselect", "hidden"],
      doc:
        "the Filters tab input type; defaults by schema type — booleans and " <>
          "Ecto.Enum fields get a select, everything else text. \"hidden\" " <>
          "whitelists the field without rendering an input, for filters driven " <>
          "from elsewhere on the page"
    )

    attr(:options, :list,
      doc:
        "options for select/multiselect inputs, as `[{label, value}]` tuples or " <>
          "plain values; derived automatically for booleans and Ecto.Enum fields"
    )

    attr(:placeholder, :string, doc: "placeholder for the Filters tab input")

    attr(:min_chars, :integer,
      doc: "minimum characters before a text filter change applies (default 0)"
    )

    attr(:debounce, :integer, doc: "milliseconds to debounce text input changes (default 300)")

    attr(:query, :any,
      doc:
        "custom 2-arity filter function (queryable, value) -> queryable; skips " <>
          "type casting and may join associations"
    )
  end

  slot :column, required: true, doc: "one slot per column" do
    attr(:field, :any,
      doc: "the record field to render; optional for virtual columns with a body"
    )

    attr(:label, :string, doc: "the column header; defaults to the humanized field name")

    attr(:sortable, :boolean,
      doc:
        "renders the header as a sort patch link (requires uri); in query mode, " <>
          "also whitelists the field for ORDER BY"
    )

    attr(:optional, :boolean,
      doc:
        "starts the column hidden until enabled through the Columns tab or the " <>
          "columns[] URL param"
    )

    attr(:export_value, :any,
      doc:
        "1-arity function (record) -> value used when exporting this column; " <>
          "makes virtual columns exportable and overrides the raw field value " <>
          "on field columns"
    )

    attr(:editable, :boolean,
      doc:
        "renders the cell as an input feeding the row's save action; requires a " <>
          "field and the table's on_save function, and cannot combine with a body"
    )
  end

  slot(:column_checkbox,
    doc:
      "renders row-selection checkboxes as the first column, always visible; " <>
        "checked row IDs live in the checked URL param; requires uri"
  )

  slot :pagination, doc: "paginates the table; at most one" do
    attr(:mode, :atom,
      values: [:page, :cursor],
      doc:
        "`:page` uses page/per_page params (works in both data modes), `:cursor` " <>
          "uses keyset cursors for constantly-updated data (query mode only); " <>
          "requires uri"
    )

    attr(:per_page, :integer,
      doc: "default page size (25); the URL per_page param overrides it up to max_per_page"
    )

    attr(:max_per_page, :integer, doc: "upper clamp for the URL per_page param (100)")

    attr(:options, :list,
      doc:
        "page sizes offered in the footer dropdown (page mode, default " <>
          "[10, 25, 50, 100]); values above max_per_page are dropped, and the " <>
          "current size is always included"
    )
  end

  def table(assigns) do
    validate_pagination!(assigns)
    validate_column_checkbox!(assigns)
    validate_tabs!(assigns)
    validate_filters!(assigns)
    validate_columns!(assigns)
    assigns = assign(assigns, :repo, resolve_repo!(assigns))

    ~H"""
    <.live_component
      module={Slab.Live}
      id={@id}
      data={@data}
      schema={@schema}
      repo={@repo}
      uri={@uri}
      params={@params}
      on_save={@on_save}
      tab={@tab}
      filter={@filter}
      column={@column}
      column_checkbox={@column_checkbox}
      pagination={@pagination}
    />
    """
  end

  defp validate_pagination!(%{pagination: []}), do: :ok

  defp validate_pagination!(%{pagination: [entry], data: data, uri: uri}) do
    cond do
      entry[:mode] == nil ->
        raise ArgumentError,
              "Slab.table <:pagination> requires a mode — :page for offset pagination " <>
                "or :cursor for keyset pagination."

      is_nil(uri) ->
        raise ArgumentError,
              "Slab.table <:pagination> requires uri — without it the table would be " <>
                "truncated with no way to navigate. Pass uri={@uri} from handle_params/3."

      entry.mode == :cursor && is_list(data) ->
        raise ArgumentError,
              "Slab.table cursor pagination requires query mode — pass schema and repo " <>
                "instead of data, or use mode={:page} to paginate a list in memory."

      true ->
        :ok
    end
  end

  defp validate_pagination!(_assigns) do
    raise ArgumentError, "Slab.table accepts at most one <:pagination> slot."
  end

  defp validate_column_checkbox!(%{column_checkbox: []}), do: :ok

  defp validate_column_checkbox!(%{column_checkbox: [_entry], uri: uri}) do
    if is_nil(uri) do
      raise ArgumentError,
            "Slab.table <:column_checkbox> requires uri — selections are stored in " <>
              "the URL. Pass uri={@uri} from handle_params/3."
    end

    :ok
  end

  defp validate_column_checkbox!(_assigns) do
    raise ArgumentError, "Slab.table accepts at most one <:column_checkbox> slot."
  end

  @built_in_tabs ~w(filters columns share export)
  @uri_tabs ~w(filters columns share)

  defp validate_tabs!(%{tab: tabs, uri: uri}) do
    names = Enum.map(tabs, & &1.name)

    if names != Enum.uniq(names) do
      raise ArgumentError, "Slab.table received duplicate <:tab> names."
    end

    Enum.each(tabs, fn tab -> validate_tab!(tab, uri) end)
  end

  defp validate_tab!(%{name: name}, nil) when name in @uri_tabs do
    raise ArgumentError,
          "Slab.table <:tab name=\"#{name}\"> requires uri — its content is " <>
            "driven by the URL. Pass uri={@uri} from handle_params/3."
  end

  defp validate_tab!(%{name: name} = tab, _uri) do
    cond do
      tab[:limit] && name != "export" ->
        raise ArgumentError,
              "Slab.table <:tab> limit is only supported on the export tab."

      name not in @built_in_tabs && (tab[:label] in [nil, ""] || tab[:inner_block] == nil) ->
        raise ArgumentError,
              "Slab.table <:tab name=\"#{name}\"> is a custom tab and requires " <>
                "a label and a body."

      true ->
        :ok
    end
  end

  defp validate_filters!(%{filter: filters}) do
    fields = Enum.map(filters, & &1.field)

    if fields != Enum.uniq(fields) do
      raise ArgumentError, "Slab.table received duplicate <:filter> fields."
    end

    Enum.each(filters, fn filter ->
      if filter[:query] && !is_function(filter[:query], 2) do
        raise ArgumentError,
              "Slab.table <:filter query> must be a 2-arity function " <>
                "(queryable, value) -> queryable."
      end
    end)
  end

  defp validate_columns!(%{column: columns, on_save: on_save}) do
    Enum.each(columns, &validate_column!/1)

    cond do
      Enum.any?(columns, &Map.get(&1, :editable, false)) && is_nil(on_save) ->
        raise ArgumentError,
              "Slab.table editable columns require on_save — a 2-arity function " <>
                "(record, changed_params) called when a row is saved. Slab never " <>
                "writes to the database itself."

      on_save && !is_function(on_save, 2) ->
        raise ArgumentError,
              "Slab.table on_save must be a 2-arity function (record, changed_params)."

      true ->
        :ok
    end
  end

  defp validate_column!(column) do
    cond do
      column[:export_value] && !is_function(column[:export_value], 1) ->
        raise ArgumentError,
              "Slab.table <:column export_value> must be a 1-arity function " <>
                "(record) -> value."

      Map.get(column, :editable, false) && !(is_atom(column[:field]) && column[:field]) ->
        raise ArgumentError,
              "Slab.table <:column editable> requires a field — the input reads " <>
                "and writes it."

      Map.get(column, :editable, false) && column[:inner_block] ->
        raise ArgumentError,
              "Slab.table <:column editable> cannot have a body — editable " <>
                "columns render an input."

      true ->
        :ok
    end
  end

  @doc """
  Renders a filter input that drives a `filter[field]` URL param.

  Pairs with `table/1`: point `field` at a `<:col filterable>` column and the
  table requeries as the user types or selects. On change the component
  patches the URL via `push_patch` — the parent LiveView only needs to track
  `uri` and `params` in `handle_params/3`, as with everything else in Slab.

  Three input types:

    * `"text"` — debounced text input; with a string-typed field this
      becomes a case-insensitive contains match
    * `"select"` — a searchable single select ([PhoenixSelect](https://github.com/chrislaskey/phoenix_select));
      clearing the selection clears the filter
    * `"multiselect"` — a searchable multi select; the selected values filter
      with `field IN (...)`

  When `type` is omitted it derives from `schema` — booleans and `Ecto.Enum`
  fields get a select with derived options, everything else a text input.

  The select types render via PhoenixSelect's colocated hook — register it
  once in `assets/js/app.js` (see the README's installation section).

  ## Examples

      <Slab.filter id="filter-name" field={:name} uri={@uri} params={@params}
        label="Name" placeholder="Search names..." />

      <Slab.filter id="filter-role" schema={MyApp.User} field={:role}
        uri={@uri} params={@params} label="Role" />

      <Slab.filter id="filter-active" field={:active} uri={@uri} params={@params}
        type="select" label="Status"
        options={[{"Active", "true"}, {"Inactive", "false"}]} />

      <Slab.filter id="filter-role" field={:role} uri={@uri} params={@params}
        type="multiselect" label="Roles"
        options={[{"Admin", "admin"}, {"Member", "member"}, {"Guest", "guest"}]} />
  """
  attr(:id, :string, required: true)

  attr(:field, :any,
    required: true,
    doc: "the filter key — matches a `<:filter>` field on the table"
  )

  attr(:uri, :string,
    required: true,
    doc: "the current request URI, from handle_params/3"
  )

  attr(:params, :map,
    default: %{},
    doc: "the current request params, from handle_params/3; carries the current value"
  )

  attr(:schema, :atom,
    default: nil,
    doc:
      "optional Ecto.Schema module used to derive the input type and options " <>
        "when they are not given"
  )

  attr(:type, :string,
    default: nil,
    doc:
      ~s(the input type: "text", "select", or "multiselect"; derived from schema ) <>
        "when omitted, defaulting to text"
  )

  attr(:label, :string, default: nil, doc: "optional label rendered beside the input")

  attr(:placeholder, :string, default: nil, doc: "placeholder for the input")

  attr(:options, :list,
    default: [],
    doc:
      "select options, as `[{label, value}]` tuples or plain values; derived " <>
        "from schema for booleans and Ecto.Enum fields when not given"
  )

  attr(:debounce, :integer,
    default: 300,
    doc: "milliseconds to debounce text input changes"
  )

  attr(:min_chars, :integer,
    default: 0,
    doc:
      "minimum characters before a text change applies (empty always applies, " <>
        "clearing the filter); submitting the form applies regardless"
  )

  def filter(assigns) do
    {derived_type, derived_options} =
      Slab.Query.filter_input_defaults(assigns.schema, assigns.field)

    assigns =
      assigns
      |> assign(:type, assigns.type || derived_type)
      |> assign(:options, if(assigns.options == [], do: derived_options, else: assigns.options))

    render_filter(assigns)
  end

  defp render_filter(%{type: "text"} = assigns) do
    ~H"""
    <div class="flex-1 min-w-0 flex items-center gap-x-3">
      <label :if={@label} for={"#{@id}-input"} class="whitespace-nowrap text-sm text-zinc-700">
        {@label}
      </label>
      <div class="w-full min-w-0">
        <.live_component
          module={Slab.FilterLive}
          id={@id}
          field={@field}
          uri={@uri}
          params={@params}
          placeholder={@placeholder}
          debounce={@debounce}
          min_chars={@min_chars}
        />
      </div>
    </div>
    """
  end

  defp render_filter(assigns) do
    ~H"""
    <div class="flex-1 min-w-0 flex items-center gap-x-3">
      <label :if={@label} for={"#{@id}-input"} class="whitespace-nowrap text-sm text-zinc-700">
        {@label}
      </label>
      <div class="w-full min-w-0">
        <PhoenixSelect.select
          id={@id}
          param={"filter[#{@field}]"}
          uri={@uri}
          params={@params}
          options={@options}
          multiple={@type == "multiselect"}
          placeholder={@placeholder}
          reset_params={["page", "after"]}
        />
      </div>
    </div>
    """
  end

  @doc """
  Renders a tabbed container, typically placed above a table to organize
  filters, sharing, and other table tooling.

  Tabs switch client-side (no server round trip). Each `<:tab>` takes a
  `label`, an optional `icon` (see `Slab.Components.icon/1` for the
  available names), and an optional `count` badge — pass
  `get_filter_count/1` for a filters tab or
  `Slab.Helpers.URI.get_query_param_count/1` for a share tab so users can
  see at a glance that the current view is filtered.

  ## Examples

      <Slab.tabs id="table-tabs" active="Filters">
        <:tab label="Filters" icon="funnel-outline" count={Slab.get_filter_count(@params)}>
          <div class="flex gap-x-4">
            <Slab.filter id="filter-name" field={:name} uri={@uri} params={@params} />
          </div>
        </:tab>
        <:tab label="Share" icon="bookmark-outline" count={Slab.Helpers.URI.get_query_param_count(@uri)}>
          <Slab.share uri={@uri} />
        </:tab>
      </Slab.tabs>
  """
  attr(:id, :string, required: true)

  attr(:active, :string,
    default: nil,
    doc: "label of the initially active tab; defaults to the first tab"
  )

  attr(:flush_bottom?, :boolean,
    default: false,
    doc:
      "opens the panel's bottom edge (no bottom border or rounding, extra bottom " <>
        "padding) so following content — like the table card — can overlap into it"
  )

  slot :tab, required: true, doc: "one slot per tab" do
    attr(:label, :string, required: true, doc: "the tab label")
    attr(:icon, :string, doc: "optional icon name rendered before the label")

    attr(:count, :integer, doc: "optional badge count rendered after the label; hidden when zero")
  end

  def tabs(assigns) do
    ~H"""
    <div>
      <div id={"#{@id}-labels"} class="flex">
        <a
          :for={{tab, index} <- Enum.with_index(@tab)}
          id={"#{@id}-label-#{index}"}
          class={tab_label_class(active_tab?(tab, index, @active))}
          phx-click={select_tab(@id, index)}
        >
          <.icon :if={tab[:icon]} type={tab.icon} class="h-5 w-5 text-cyan-600" />
          {tab.label}
          <div
            :if={(tab[:count] || 0) > 0}
            class="ml-1 h-5 px-2 flex items-center justify-center text-xs bg-cyan-600/70 text-white rounded-full"
          >
            {tab.count}
          </div>
        </a>
      </div>

      <div id={"#{@id}-contents"}>
        <div
          :for={{tab, index} <- Enum.with_index(@tab)}
          id={"#{@id}-content-#{index}"}
          class={tab_content_class(active_tab?(tab, index, @active), @flush_bottom?)}
        >
          {render_slot(tab)}
        </div>
      </div>
    </div>
    """
  end

  defp active_tab?(_tab, index, nil), do: index == 0
  defp active_tab?(tab, _index, active), do: tab.label == active

  @tab_label_base "px-4 py-2 flex items-center gap-x-1 cursor-pointer text-zinc-700 hover:text-cyan-600"
  @tab_label_active "-mb-px bg-gray-50 rounded-tl rounded-tr border border-b-0 border-gray-200"
  @tab_content_base "p-4 bg-gray-50 border border-gray-200"

  defp tab_label_class(true), do: "#{@tab_label_base} #{@tab_label_active}"
  defp tab_label_class(false), do: @tab_label_base

  defp tab_content_class(active?, flush_bottom?) do
    variant =
      if flush_bottom? do
        "pb-10 border-b-0 rounded-tr"
      else
        "pb-6 rounded-tr rounded-br rounded-bl"
      end

    hidden = if active?, do: "", else: " hidden"

    "#{@tab_content_base} #{variant}#{hidden}"
  end

  defp select_tab(id, index) do
    labels = "##{id}-labels a"
    label = "##{id}-label-#{index}"
    contents = "##{id}-contents>div"
    content = "##{id}-content-#{index}"

    %JS{}
    |> JS.remove_class(@tab_label_active, to: labels)
    |> JS.add_class(@tab_label_active, to: label)
    |> JS.add_class("hidden", to: contents)
    |> JS.remove_class("hidden", to: content)
  end

  @doc """
  Renders a share row: the current URL in a read-only input with a
  copy-to-clipboard button.

  Because all table state — sorting, filters, pagination, selection — lives
  in the URL, the copied link reproduces the exact current view. Typically
  rendered inside a `tabs/1` Share tab.

  The copy button uses a colocated hook — register Slab's hooks once in
  `assets/js/app.js` (see the README's installation section).

  ## Examples

      <Slab.share uri={@uri} />
  """
  attr(:id, :string, default: "slab-share", doc: "unique DOM id, when rendering more than one")
  attr(:uri, :string, required: true, doc: "the current request URI, from handle_params/3")

  def share(assigns) do
    ~H"""
    <div id={@id} data-slab-share class="flex items-center gap-x-3">
      <div class="whitespace-nowrap text-sm text-zinc-700">Share URL</div>
      <div class="w-full flex gap-x-2">
        <form class="w-full flex items-center min-h-10 rounded-lg border border-zinc-300 bg-white focus-within:border-cyan-600">
          <input
            type="text"
            readonly
            value={@uri}
            data-slab-share-url
            class="m-0 py-1 px-4 w-full text-sm border-0 rounded-lg bg-transparent text-zinc-700 outline-0 focus:ring-0 focus:outline-none"
          />
        </form>
        <button
          id={"#{@id}-copy"}
          phx-hook=".CopyToClipboard"
          type="button"
          class="min-h-10 px-4 flex gap-x-1 items-center justify-center bg-white whitespace-nowrap text-sm text-zinc-700 border border-zinc-300 rounded-lg hover:text-cyan-600"
        >
          <.icon type="clipboard-outline" class="h-4 w-4 text-cyan-600" />
          <span data-slab-copy-label>Copy to clipboard</span>
        </button>
      </div>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".CopyToClipboard">
        export default {
          mounted() {
            this.el.addEventListener("click", () => {
              const root = this.el.closest("[data-slab-share]")
              const input = root && root.querySelector("[data-slab-share-url]")
              if (!input) return
              navigator.clipboard.writeText(input.value).then(() => {
                const label = this.el.querySelector("[data-slab-copy-label]")
                if (!label) return
                const original = label.textContent
                label.textContent = "Copied!"
                setTimeout(() => (label.textContent = original), 1500)
              })
            })
          }
        }
      </script>
    </div>
    """
  end

  defp resolve_repo!(%{data: data, schema: schema, repo: repo}) do
    cond do
      is_list(data) && repo ->
        raise ArgumentError,
              "Slab.table received both data and repo — repo is only used in query mode. " <>
                "Pass data with pre-fetched records, or pass schema and repo to have Slab query."

      is_list(data) ->
        nil

      is_nil(schema) ->
        raise ArgumentError,
              "Slab.table requires either data (a list of records to render) or " <>
                "schema (an Ecto schema or query for Slab to fetch from) — neither was given."

      true ->
        repo ||
          Application.get_env(:slab, :repo) ||
          raise(
            ArgumentError,
            "Slab.table query mode requires a repo — pass repo={MyApp.Repo} or " <>
              "set config :slab, repo: MyApp.Repo"
          )
    end
  end

  # Helpers - Sorting

  @doc """
  Returns the path to patch to when sorting by `field`.

  Sets the `sort` and `sort_direction` query params on the given URI. Clicking
  the currently ascending sort field flips the direction to descending;
  anything else sorts ascending. Changing the sort resets pagination — the
  `page` and `after` params are removed, since neither an offset nor a cursor
  is meaningful under a different ordering.

  ## Examples

      iex> Slab.sort_path("https://example.com/users", %{}, "name")
      "/users?sort=name&sort_direction=asc"

      iex> Slab.sort_path(
      ...>   "https://example.com/users?sort=name&sort_direction=asc",
      ...>   %{"sort" => "name", "sort_direction" => "asc"},
      ...>   "name"
      ...> )
      "/users?sort=name&sort_direction=desc"

      iex> Slab.sort_path("https://example.com/users?page=3", %{}, "name")
      "/users?sort=name&sort_direction=asc"
  """
  def sort_path(uri, params, field) do
    direction =
      if Map.get(params, "sort") == field && Map.get(params, "sort_direction") == "asc" do
        "desc"
      else
        "asc"
      end

    uri
    |> Slab.Helpers.URI.delete_query_param("page")
    |> Slab.Helpers.URI.delete_query_param("after")
    |> Slab.Helpers.URI.create_or_update_query_param("sort", field)
    |> Slab.Helpers.URI.create_or_update_query_param("sort_direction", direction)
    |> Slab.Helpers.URI.extract_full_path()
  end

  # Helpers - Pagination

  @doc """
  Returns the path to patch to for the given page number.

  Page 1 removes the `page` param entirely, keeping first-page URLs clean.
  The `after` cursor param is always removed — the two pagination modes are
  mutually exclusive.

  ## Examples

      iex> Slab.page_path("https://example.com/users?page=2", 3)
      "/users?page=3"

      iex> Slab.page_path("https://example.com/users?page=2", 1)
      "/users"
  """
  def page_path(uri, page) when is_integer(page) and page <= 1 do
    uri
    |> Slab.Helpers.URI.delete_query_param("after")
    |> Slab.Helpers.URI.delete_query_param("page")
    |> Slab.Helpers.URI.extract_full_path()
  end

  def page_path(uri, page) when is_integer(page) do
    uri
    |> Slab.Helpers.URI.delete_query_param("after")
    |> Slab.Helpers.URI.create_or_update_query_param("page", to_string(page))
    |> Slab.Helpers.URI.extract_full_path()
  end

  # Helpers - Filtering

  @doc """
  Returns the number of active filters from a URI string or a params map.

  Useful as the `count` badge on a filters tab. Counts filter entries
  recursively, so an operator filter (`filter[age][gte]=21`) counts once per
  operator and a multi-select counts as one.

  ## Examples

      iex> Slab.get_filter_count(%{"filter" => %{"name" => "ada", "role" => ["admin", "member"]}})
      2

      iex> Slab.get_filter_count("/users?filter[name]=ada&sort=name")
      1

      iex> Slab.get_filter_count(%{})
      0
  """
  def get_filter_count(uri) when is_bitstring(uri) do
    uri
    |> Slab.Helpers.URI.get_query_param("filter")
    |> count_filters()
  end

  def get_filter_count(params) when is_map(params) do
    params
    |> Map.get("filter")
    |> count_filters()
  end

  defp count_filters(%{} = filters) do
    Enum.reduce(filters, 0, fn
      {_key, %{} = operators}, acc -> acc + map_size(operators)
      {_key, _value}, acc -> acc + 1
    end)
  end

  defp count_filters(_filters), do: 0

  @doc """
  Returns the path to patch to when filtering `field` by `value`.

  Sets the `filter[field]` query param — pass a string for the default
  operator (contains for strings, equality otherwise), a map for explicit
  operators, or `nil`/`""` to clear the filter. Changing a filter resets
  pagination, since the result set is different.

  Use this to build filter UIs in the parent LiveView; Slab applies the
  resulting params to the query in query mode.

  ## Examples

      iex> Slab.filter_path("https://example.com/users", :name, "ada")
      "/users?filter[name]=ada"

      iex> Slab.filter_path("https://example.com/users?page=3", :age, %{"gte" => "21"})
      "/users?filter[age][gte]=21"

      iex> Slab.filter_path("https://example.com/users?filter[name]=ada", :name, nil)
      "/users"
  """
  def filter_path(uri, field, value) do
    uri
    |> Slab.Helpers.URI.delete_query_param("page")
    |> Slab.Helpers.URI.delete_query_param("after")
    |> Slab.Helpers.URI.create_or_update_or_delete_query_param("filter[#{field}]", value)
    |> Slab.Helpers.URI.extract_full_path()
  end

  # Helpers - Row selection

  @doc """
  Returns the list of checked row IDs (as strings) from a URI string or a
  params map.
  """
  def get_checked_ids(uri) when is_bitstring(uri) do
    uri
    |> Slab.Helpers.URI.get_query_param("checked")
    |> Kernel.||([])
    |> Enum.map(&to_string/1)
  end

  def get_checked_ids(params) when is_map(params) do
    params
    |> Map.get("checked", [])
    |> Enum.map(&to_string/1)
  end

  @doc """
  Returns the number of checked rows from a URI string or a params map.
  """
  def get_checked_count(uri_or_params) do
    uri_or_params
    |> get_checked_ids()
    |> length()
  end

  @doc """
  Returns the records whose ID is checked in the given URI.

  ## Options

    * `:key` - the record field to match against checked IDs (default: `:id`)
  """
  def get_checked_values(uri, records, options \\ []) do
    key = Keyword.get(options, :key, :id)
    ids = get_checked_ids(uri)

    Enum.filter(records, fn record -> to_string(Map.get(record, key)) in ids end)
  end

  @doc """
  Returns whether any rows are checked in the given URI string or params map.
  """
  def checked?(uri_or_params), do: get_checked_count(uri_or_params) > 0

  @doc """
  Returns selected records from current page and IDs that need to be fetched.

  This is useful for pagination scenarios where you need to maintain full record data
  for selections across multiple pages.

  ## Parameters
    - `current_page_records` - List of records currently displayed on the page
    - `checked_ids` - List of selected IDs (typically from URI query params)
    - `options` - Keyword list of options
      - `:key` - The field to use as the ID (default: `:id`)
      - `:parse_ids` - Function to parse/convert IDs (default: `&to_string/1`)

  ## Returns
    A tuple of `{selected_from_current_page, missing_ids}` where:
    - `selected_from_current_page` - Records from current page that are selected
    - `missing_ids` - IDs that need to be fetched (not on current page)

  ## Examples

      # In a LiveView:
      checked_ids = Slab.get_checked_ids(uri)
      {current_selected, missing_ids} = Slab.get_selected_and_missing_ids(
        users.entries,
        checked_ids
      )

      # Fetch missing records
      missing_users = Repo.all(from u in User, where: u.id in ^missing_ids)

      # Combine
      all_selected = current_selected ++ missing_users
  """
  def get_selected_and_missing_ids(current_page_records, checked_ids, options \\ []) do
    key = Keyword.get(options, :key, :id)
    parse_fn = Keyword.get(options, :parse_ids, &to_string/1)

    normalized_checked_ids = Enum.map(checked_ids, parse_fn)

    current_page_selected =
      Enum.filter(current_page_records, fn record ->
        parse_fn.(Map.get(record, key)) in normalized_checked_ids
      end)

    current_page_ids =
      Enum.map(current_page_selected, fn record ->
        parse_fn.(Map.get(record, key))
      end)

    missing_ids = Enum.reject(normalized_checked_ids, fn id -> id in current_page_ids end)

    {current_page_selected, missing_ids}
  end
end
