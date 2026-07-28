defmodule Slab.Live do
  @moduledoc """
  The stateful core of `Slab.table/1`.

  This live component is an internal implementation detail — render tables
  with `Slab.table/1`, which validates attributes and slots at compile time
  and forwards them here. It exists as a live component so interactive state
  (row selection, query-mode data fetching) has a home with a lifecycle and
  event handlers.
  """

  use Phoenix.LiveComponent

  import Slab.Components

  alias Slab.Helpers.Params

  @impl true
  def update(assigns, socket) do
    uri = Map.get(assigns, :uri)
    params = Map.get(assigns, :params, %{})

    {data, has_next?, query_inputs} = resolve_data(assigns, params, socket)
    {total, count_inputs} = resolve_total(assigns, params, socket)

    checkable? = Map.get(assigns, :checkable?, false) && uri != nil
    checked_ids_lookup = get_checked_ids_lookup(checkable?, uri)

    checked_all? =
      if checkable? && Enum.any?(data) do
        Enum.all?(data, fn record ->
          Map.has_key?(checked_ids_lookup, to_string(Map.get(record, :id)))
        end)
      else
        false
      end

    field_types =
      assigns
      |> Map.get(:schema)
      |> Slab.Query.schema_module()
      |> get_field_types()

    socket =
      socket
      |> assign(assigns)
      |> assign(:checkable?, checkable?)
      |> assign(:checked_all?, checked_all?)
      |> assign(:checked_ids_lookup, checked_ids_lookup)
      |> assign(:count_inputs, count_inputs)
      |> assign(:data, data)
      |> assign(:field_types, field_types)
      |> assign(:params, params)
      |> assign(:query_inputs, query_inputs)
      |> assign(:sort, Map.get(params, "sort"))
      |> assign(:sort_direction, Map.get(params, "sort_direction"))
      |> assign(:total, total)
      |> assign(:uri, uri)
      |> assign(:visible_cols, visible_cols(Map.get(assigns, :col, []), params))
      |> assign_pagination(assigns, params, data, has_next?, total)
      |> assign_tabs(assigns, params, uri, field_types)

    {:ok, socket}
  end

  # Helpers - Column visibility

  # The columns[] URL param controls which columns render, in param order —
  # visibility and ordering are user state like everything else in the URL.
  # Names are matched against the declared columns (unknown names are
  # ignored), and with no param — or nothing matching — the default is the
  # declaration order minus `optional` columns.
  defp visible_cols(cols, params) do
    keyed = keyed_cols(cols)

    case requested_cols(keyed, Map.get(params, "columns")) do
      [] -> for {_key, col} <- keyed, !Map.get(col, :optional, false), do: col
      resolved -> resolved
    end
  end

  defp requested_cols(keyed, requested) when is_list(requested) do
    lookup = Map.new(keyed)

    requested
    |> Enum.uniq()
    |> Enum.flat_map(fn key -> List.wrap(Map.get(lookup, key)) end)
  end

  defp requested_cols(_keyed, _absent), do: []

  # Every column gets a stable string key for the columns[] param: its field
  # name, a slug of its label for virtual columns, or its position as a last
  # resort.
  defp keyed_cols(cols) do
    for {col, index} <- Enum.with_index(cols) do
      {col_key(col, index), col}
    end
  end

  defp col_key(col, index) do
    cond do
      col[:field] -> to_string(col.field)
      is_binary(col[:label]) && col.label != "" -> label_slug(col.label)
      true -> "column-#{index}"
    end
  end

  defp label_slug(label) do
    label
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  # Tabs are derived from the table definition: a Filters tab appears when
  # any column is filterable, Columns and Share tabs when their attrs are
  # set and a uri is given. No qualifying tabs, no tab bar.
  defp assign_tabs(socket, assigns, params, uri, field_types) do
    schema = Slab.Query.schema_module(Map.get(assigns, :schema))
    cols = Map.get(assigns, :col, [])
    filter_inputs = filter_inputs(cols, field_types, schema)
    filter_tab? = filter_inputs != [] && uri != nil
    columns_tab? = Map.get(assigns, :columns_tab?, false) && uri != nil
    share_tab? = Map.get(assigns, :share_tab?, false) && uri != nil

    columns_param = Map.get(params, "columns")

    socket
    |> assign(:filter_inputs, filter_inputs)
    |> assign(:filter_tab?, filter_tab?)
    |> assign(:columns_tab?, columns_tab?)
    |> assign(:share_tab?, share_tab?)
    |> assign(:column_options, column_options(cols))
    |> assign(:columns_count, if(is_list(columns_param), do: length(columns_param), else: 0))
    |> assign(:filter_count, Slab.get_filter_count(params))
    |> assign(:share_count, if(uri, do: Slab.Helpers.URI.get_query_param_count(uri), else: 0))
  end

  # Picker options for the Columns tab, in declaration order
  defp column_options(cols) do
    for {key, col} <- keyed_cols(cols) do
      case column_label(col) do
        "" -> {key, key}
        label -> {label, key}
      end
    end
  end

  # One input per filterable column. The col's filter_* attrs win; otherwise
  # the type is derived from the schema — booleans and Ecto.Enum fields get
  # a select with derived options, everything else a text input.
  defp filter_inputs(cols, field_types, schema) do
    for col <- cols,
        Map.get(col, :filterable, false) || is_function(col[:filter_query], 2),
        is_atom(col[:field]) && col[:field] do
      {default_type, default_options} =
        filter_input_defaults(Map.get(field_types, col.field), schema, col.field)

      %{
        field: col.field,
        label: column_label(col),
        type: col[:filter_type] || default_type,
        options: col[:filter_options] || default_options,
        placeholder: col[:filter_placeholder],
        min_chars: col[:filter_min_chars] || 0
      }
    end
  end

  defp filter_input_defaults(:boolean, _schema, _field) do
    {"select", [{"True", "true"}, {"False", "false"}]}
  end

  defp filter_input_defaults(_type, schema, field) do
    case Slab.Query.enum_values(schema, field) do
      nil ->
        {"text", []}

      values ->
        {"select", Enum.map(values, fn value -> {humanize_field(value), to_string(value)} end)}
    end
  end

  # In list mode the caller owns the data; page mode slices it in memory.
  # In query mode, fetch through the repo — but only when the query inputs
  # changed since the last update, so unrelated parent re-renders don't
  # re-run the query.
  defp resolve_data(%{data: data} = assigns, params, _socket) when is_list(data) do
    case Map.get(assigns, :paginate) do
      :page ->
        page = Params.page(params)
        per_page = per_page(assigns, params)

        {Enum.slice(data, (page - 1) * per_page, per_page), length(data) > page * per_page, nil}

      nil ->
        {data, false, nil}
    end
  end

  defp resolve_data(assigns, params, socket) do
    opts = %{
      sortable_fields: sortable_fields(Map.get(assigns, :col, [])),
      filterable_cols: filterable_cols(Map.get(assigns, :col, [])),
      paginate: Map.get(assigns, :paginate),
      per_page: Map.get(assigns, :per_page, 25),
      max_per_page: Map.get(assigns, :max_per_page, 100)
    }

    query_inputs = {
      Map.get(assigns, :schema),
      Map.get(assigns, :repo),
      Map.take(params, ["sort", "sort_direction", "page", "per_page", "after", "filter"]),
      opts
    }

    if socket.assigns[:query_inputs] == query_inputs do
      {socket.assigns.data, socket.assigns.has_next?, query_inputs}
    else
      {schema, repo, _params, _opts} = query_inputs
      {data, has_next?} = Slab.Query.fetch(schema, repo, params, opts)

      {data, has_next?, query_inputs}
    end
  end

  # The total backs the "Showing X to Y of Z entries" summary and the
  # numbered page links, so it only applies in page mode. In query mode it is
  # a count query cached on {schema, repo, filter} — page and sort changes
  # never re-count, only filter changes do.
  defp resolve_total(%{data: data} = assigns, _params, _socket) when is_list(data) do
    if Map.get(assigns, :paginate) == :page, do: {length(data), nil}, else: {nil, nil}
  end

  defp resolve_total(assigns, params, socket) do
    if Map.get(assigns, :paginate) == :page do
      count_inputs = {
        Map.get(assigns, :schema),
        Map.get(assigns, :repo),
        Map.get(params, "filter")
      }

      if socket.assigns[:count_inputs] == count_inputs do
        {socket.assigns.total, count_inputs}
      else
        {schema, repo, _filter} = count_inputs
        filterable = filterable_cols(Map.get(assigns, :col, []))

        {Slab.Query.count(schema, repo, params, filterable), count_inputs}
      end
    else
      {nil, nil}
    end
  end

  # Fields whitelisted for ORDER BY: declared sortable, with an atom field
  defp sortable_fields(cols) do
    for col <- cols, Map.get(col, :sortable, false), is_atom(col[:field]) && col[:field] do
      col.field
    end
  end

  # Columns whitelisted for WHERE: declared filterable, or carrying a custom
  # filter_query function (which implies filterable)
  defp filterable_cols(cols) do
    for col <- cols,
        Map.get(col, :filterable, false) || is_function(col[:filter_query], 2),
        is_atom(col[:field]) && col[:field] do
      %{field: col.field, filter: col[:filter_query]}
    end
  end

  defp per_page(assigns, params) do
    Params.per_page(
      params,
      Map.get(assigns, :per_page, 25),
      Map.get(assigns, :max_per_page, 100)
    )
  end

  # Helpers - Pagination

  defp assign_pagination(socket, assigns, params, data, has_next?, total) do
    uri = Map.get(assigns, :uri)
    paginate = Map.get(assigns, :paginate)
    page = Params.page(params)
    per_page = per_page(assigns, params)
    total_pages = total_pages(total, per_page)

    {prev_path, first_path, next_path} =
      case paginate do
        nil ->
          {nil, nil, nil}

        :page ->
          prev = if page > 1, do: Slab.page_path(uri, page - 1)
          next = if has_next?, do: Slab.page_path(uri, page + 1)

          {prev, nil, next}

        :cursor ->
          first = if Map.get(params, "after"), do: first_page_path(uri)
          next = if has_next?, do: next_cursor_path(uri, params, assigns, data)

          {nil, first, next}
      end

    socket
    |> assign(:has_next?, has_next?)
    |> assign(:page, page)
    |> assign(:page_numbers, page_numbers(paginate, page, total_pages))
    |> assign(:paginate, paginate)
    |> assign(:per_page_current, per_page)
    |> assign(:per_page_options, per_page_options(assigns, per_page))
    |> assign(:first_path, first_path)
    |> assign(:next_path, next_path)
    |> assign(:prev_path, prev_path)
    |> assign(:showing_from, showing_from(total, page, per_page))
    |> assign(:showing_to, showing_to(total, page, per_page))
  end

  defp total_pages(total, per_page) when is_integer(total) and total > 0 do
    div(total + per_page - 1, per_page)
  end

  defp total_pages(_total, _per_page), do: 1

  defp showing_from(total, _page, _per_page) when total in [nil, 0], do: 0
  defp showing_from(total, page, per_page), do: min((page - 1) * per_page + 1, total)

  defp showing_to(total, _page, _per_page) when total in [nil, 0], do: 0
  defp showing_to(total, page, per_page), do: min(page * per_page, total)

  # Numbered page links: first and last page, the current page ±2, with
  # ellipses covering the gaps — e.g. [1, "…", 4, 5, 6, "…", 20].
  defp page_numbers(:page, page, total_pages) do
    first = MapSet.new([1])
    last = MapSet.new([total_pages])
    middle_first = max(1, page - 2)
    middle_last = min(page + 2, total_pages)
    middle = MapSet.new(Range.new(middle_first, middle_last))

    first
    |> MapSet.union(middle)
    |> MapSet.union(last)
    |> MapSet.to_list()
    |> Enum.sort()
    |> maybe_add_prefix_ellipsis()
    |> maybe_add_suffix_ellipsis()
  end

  defp page_numbers(_paginate, _page, _total_pages), do: []

  defp maybe_add_prefix_ellipsis(numbers) do
    only_one? = length(numbers) == 1
    consecutive? = Enum.at(numbers, 1) == 2

    if only_one? || consecutive? do
      numbers
    else
      List.insert_at(numbers, 1, "…")
    end
  end

  defp maybe_add_suffix_ellipsis(numbers) do
    index = length(numbers) - 2

    if index <= 0 || Enum.at(numbers, index) == List.last(numbers) - 1 do
      numbers
    else
      List.insert_at(numbers, length(numbers) - 1, "…")
    end
  end

  # Page sizes for the footer dropdown: the configured options clamped to
  # max_per_page, always including the current size.
  defp per_page_options(assigns, per_page) do
    max_per_page = Map.get(assigns, :max_per_page, 100)

    assigns
    |> Map.get(:per_page_options, [10, 25, 50, 100])
    |> Enum.filter(fn size -> is_integer(size) && size >= 1 && size <= max_per_page end)
    |> Kernel.++([per_page])
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp first_page_path(uri) do
    uri
    |> Slab.Helpers.URI.delete_query_param("after")
    |> Slab.Helpers.URI.extract_full_path()
  end

  # The next cursor is the last visible record: its id, plus its sort-field
  # value when a whitelisted sort is active (nil sort values fall back to an
  # id-only cursor).
  defp next_cursor_path(uri, params, assigns, data) do
    record = List.last(data)
    sort = Map.get(params, "sort")

    sort_field =
      assigns
      |> Map.get(:col, [])
      |> sortable_fields()
      |> Enum.find(fn field -> to_string(field) == sort end)

    after_params =
      case sort_field && Map.get(record, sort_field) do
        nil -> %{"id" => to_string(Map.get(record, :id))}
        value -> %{"id" => to_string(Map.get(record, :id)), "value" => encode_cursor_value(value)}
      end

    uri
    |> Slab.Helpers.URI.delete_query_param("page")
    |> Slab.Helpers.URI.create_or_update_query_param("after", after_params)
    |> Slab.Helpers.URI.extract_full_path()
  end

  # Round-trippable string encodings: Ecto.Type.cast/2 accepts ISO 8601 for
  # date and time types, and to_string for everything else Slab supports.
  defp encode_cursor_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp encode_cursor_value(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp encode_cursor_value(%Date{} = value), do: Date.to_iso8601(value)
  defp encode_cursor_value(%Time{} = value), do: Time.to_iso8601(value)
  defp encode_cursor_value(value), do: to_string(value)

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div :if={@filter_tab? || @columns_tab? || @share_tab?} class="-mb-4">
        <Slab.tabs id={"#{@id}-tabs"} flush_bottom?>
          <:tab :if={@filter_tab?} label="Filters" icon="funnel-outline" count={@filter_count}>
            <div class="grid grid-cols-[repeat(auto-fit,minmax(200px,1fr))] gap-4">
              <Slab.filter
                :for={input <- @filter_inputs}
                id={"#{@id}-filter-#{input.field}"}
                field={input.field}
                uri={@uri}
                params={@params}
                type={input.type}
                label={input.label}
                options={input.options}
                placeholder={input.placeholder}
                min_chars={input.min_chars}
              />
            </div>
          </:tab>
          <:tab :if={@columns_tab?} label="Columns" icon="view-columns-outline" count={@columns_count}>
            <div class="flex items-center gap-x-3">
              <div class="whitespace-nowrap text-sm text-zinc-700">Table columns</div>
              <div class="w-full">
                <PhoenixSelect.select
                  id={"#{@id}-columns"}
                  param="columns"
                  uri={@uri}
                  params={@params}
                  options={@column_options}
                  multiple
                  placeholder="Default columns"
                />
              </div>
            </div>
          </:tab>
          <:tab :if={@share_tab?} label="Share" icon="bookmark-outline" count={@share_count}>
            <Slab.share id={"#{@id}-share"} uri={@uri} />
          </:tab>
        </Slab.tabs>
      </div>

      <section class="px-4 py-3 border border-gray-200 bg-white shadow-sm rounded-lg">
        <form>
          <.table>
          <:thead>
            <.tr>
              <.th :if={@checkable?}>
                <div class="pl-1 h-full" phx-target={@myself} phx-click="toggle-checkbox-for-all">
                  <.checkbox name="checked_all" checked={@checked_all?} />
                </div>
              </.th>
              <.th :for={col <- @visible_cols}>
                <div class="flex items-center gap-x-1">
                  <.link
                    :if={sortable?(col, @uri)}
                    patch={Slab.sort_path(@uri, @params, to_string(col.field))}
                    class="inline-flex items-center gap-x-1 text-left"
                  >
                    <span>{column_label(col)}</span>

                    <span :if={@sort == to_string(col.field)}>
                      <.icon
                        type={
                          if(@sort_direction == "asc",
                            do: "chevron-up-outline",
                            else: "chevron-down-outline"
                          )
                        }
                        class="h-3 w-3"
                      />
                    </span>
                  </.link>

                  <span :if={!sortable?(col, @uri)}>{column_label(col)}</span>
                </div>
              </.th>
            </.tr>
          </:thead>
          <.tr :for={record <- @data}>
            <.td :if={@checkable?}>
              <div
                class="px-1 h-full"
                phx-target={@myself}
                phx-click="toggle-checkbox-for-row"
                phx-value-id={Map.get(record, :id)}
              >
                <.checkbox
                  name="checked_row"
                  checked={Map.get(@checked_ids_lookup, to_string(Map.get(record, :id))) || false}
                />
              </div>
            </.td>
            <.td :for={col <- @visible_cols}>
              <div class="px-1">
                <%= if col[:inner_block] do %>
                  {render_slot(col, record)}
                <% else %>
                  {render_field_value(record, col[:field], @field_types)}
                <% end %>
              </div>
            </.td>
          </.tr>
          </.table>
        </form>
      </section>

      <div :if={@paginate == :page} class="my-2 py-2 flex items-center justify-between gap-x-4">
        <div class="hidden sm:flex">
          <p class="text-sm text-gray-700">
            Showing <span class="font-medium">{@showing_from}</span>
            to <span class="font-medium">{@showing_to}</span>
            of <span class="font-medium">{@total}</span> entries
          </p>
        </div>

        <div class="flex items-center gap-x-3">
          <nav class="relative z-0 inline-flex rounded-md shadow-sm -space-x-px" aria-label="Pagination">
            <.link :if={@prev_path} patch={@prev_path} class={pager_edge_class(:prev, :link)}>
              <span class="sr-only">Previous</span>
              <.icon type="chevron-left-outline" class="h-5 w-5" />
            </.link>
            <span :if={!@prev_path} class={pager_edge_class(:prev, :disabled)}>
              <span class="sr-only">Previous</span>
              <.icon type="chevron-left-outline" class="h-5 w-5 text-gray-400" />
            </span>

            <%= for number <- @page_numbers do %>
              <span :if={number == "…"} class={pager_number_class(:ellipsis)}>…</span>
              <span
                :if={number == @page}
                aria-current="page"
                class={pager_number_class(:current)}
              >
                {number}
              </span>
              <.link
                :if={is_integer(number) && number != @page}
                patch={Slab.page_path(@uri, number)}
                class={pager_number_class(:link)}
              >
                {number}
              </.link>
            <% end %>

            <.link :if={@next_path} patch={@next_path} class={pager_edge_class(:next, :link)}>
              <span class="sr-only">Next</span>
              <.icon type="chevron-right-outline" class="h-5 w-5" />
            </.link>
            <span :if={!@next_path} class={pager_edge_class(:next, :disabled)}>
              <span class="sr-only">Next</span>
              <.icon type="chevron-right-outline" class="h-5 w-5 text-gray-400" />
            </span>
          </nav>

          <form phx-target={@myself} phx-change="per-page" class="flex items-center gap-x-2">
            <label for={"#{@id}-per-page"} class="text-sm text-gray-700">Page size</label>
            <select
              id={"#{@id}-per-page"}
              name="per_page"
              class="py-2 pl-3 pr-8 text-sm border border-gray-300 rounded-md bg-white text-gray-700 focus:outline-none focus:ring-1 focus:ring-cyan-600"
            >
              <option :for={size <- @per_page_options} value={size} selected={size == @per_page_current}>
                {size}
              </option>
            </select>
          </form>
        </div>
      </div>

      <div :if={@paginate == :cursor} class="my-2 py-2 flex items-center gap-x-4 text-sm">
        <.link :if={@first_path} patch={@first_path} class="text-cyan-600 hover:underline">
          &laquo; First
        </.link>
        <.link :if={@next_path} patch={@next_path} class="text-cyan-600 hover:underline">
          Next &rarr;
        </.link>
      </div>
    </div>
    """
  end

  defp pager_edge_class(side, kind) do
    rounding = if side == :prev, do: "rounded-l-md", else: "rounded-r-md"

    base =
      "relative inline-flex items-center px-2 py-2 #{rounding} border border-gray-300 text-sm font-medium text-gray-500"

    case kind do
      :link -> "#{base} bg-white hover:bg-gray-50"
      :disabled -> "#{base} bg-gray-100"
    end
  end

  defp pager_number_class(:ellipsis) do
    "relative inline-flex items-center px-3 py-2 border bg-white border-gray-300 text-sm font-medium text-gray-700"
  end

  defp pager_number_class(:current) do
    "z-10 bg-white border-cyan-500 text-cyan-600 relative inline-flex items-center px-4 py-2 border text-sm font-medium"
  end

  defp pager_number_class(:link) do
    "border-gray-300 bg-white text-gray-500 hover:bg-gray-50 relative inline-flex items-center px-4 py-2 border text-sm font-medium"
  end

  @impl true
  def handle_event("per-page", %{"per_page" => per_page}, socket) do
    to =
      socket.assigns.uri
      |> Slab.Helpers.URI.delete_query_param("page")
      |> Slab.Helpers.URI.delete_query_param("after")
      |> Slab.Helpers.URI.create_or_update_query_param("per_page", per_page)
      |> Slab.Helpers.URI.extract_full_path()

    {:noreply, push_patch(socket, to: to)}
  end

  def handle_event("toggle-checkbox-for-all", _params, socket) do
    current_ids =
      Enum.map(socket.assigns.data, fn record -> to_string(Map.get(record, :id)) end)

    existing_checked_ids = Slab.get_checked_ids(socket.assigns.uri)

    updated_ids =
      if socket.assigns.checked_all? do
        Enum.reject(existing_checked_ids, fn id -> id in current_ids end)
      else
        Enum.uniq(existing_checked_ids ++ current_ids)
      end

    {:noreply, push_patch(socket, to: checked_path(socket.assigns.uri, updated_ids))}
  end

  def handle_event("toggle-checkbox-for-row", params, socket) do
    id = to_string(params["id"])
    current = Slab.get_checked_ids(socket.assigns.uri)

    updated =
      if Enum.find(current, fn value -> value == id end) do
        List.delete(current, id)
      else
        [id | current]
      end

    {:noreply, push_patch(socket, to: checked_path(socket.assigns.uri, updated))}
  end

  # Helpers - Checkable functions

  defp checked_path(uri, []) do
    uri
    |> Slab.Helpers.URI.delete_query_param("checked")
    |> Slab.Helpers.URI.extract_full_path()
  end

  defp checked_path(uri, checked_ids) do
    uri
    |> Slab.Helpers.URI.create_or_update_query_param("checked", checked_ids)
    |> Slab.Helpers.URI.extract_full_path()
  end

  defp get_checked_ids_lookup(checkable?, uri) do
    if checkable? do
      uri
      |> Slab.Helpers.URI.get_query_param("checked")
      |> Kernel.||([])
      |> Map.new(fn value -> {to_string(value), true} end)
    else
      %{}
    end
  end

  # Helpers - Column functions

  defp get_field_types(nil), do: %{}

  defp get_field_types(schema) do
    Map.new(schema.__schema__(:fields), fn field ->
      {field, schema.__schema__(:type, field)}
    end)
  end

  # Sorting patches the URL, so columns are only sortable when a uri is given
  defp sortable?(col, uri) do
    Map.get(col, :sortable, false) && col[:field] != nil && uri != nil
  end

  defp column_label(%{label: label}) when is_binary(label), do: label
  defp column_label(%{field: field}) when not is_nil(field), do: humanize_field(field)
  defp column_label(_col), do: ""

  defp humanize_field(field) when is_atom(field) do
    field
    |> Atom.to_string()
    |> humanize_field()
  end

  defp humanize_field(field) when is_bitstring(field) do
    field
    |> String.split("_")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  # Helpers - Render functions

  defp render_field_value(_record, nil, _field_types), do: nil

  defp render_field_value(record, field, field_types) when is_bitstring(field) do
    if Enum.member?(keys_as_strings(record), to_string(field)) do
      render_field_value(record, String.to_existing_atom(field), field_types)
    end
  end

  defp render_field_value(record, field, field_types) do
    value = Map.get(record, field)
    assigns = %{value: value}
    type = Map.get(field_types, field, :string)

    render_field_type(type, assigns)
  end

  defp render_field_type(:boolean, assigns) do
    ~H"""
    <div class="flex gap-x-1 items-center">
      <%= if @value do %>
        <.icon type="check-circle-outline" class="h-5 w-5 text-green-500" />
        <span>True</span>
      <% else %>
        <.icon type="x-circle-outline" class="h-5 w-5 text-red-500" />
        <span>False</span>
      <% end %>
    </div>
    """
  end

  defp render_field_type(Ecto.UUID, assigns) do
    ~H"""
    <div class="relative inline-flex mr-1 group">
      <div>
        {String.slice(@value, 0, 8)}
      </div>
      <div class="absolute top-0 left-0 items-center hidden px-3 py-2 text-sm whitespace-nowrap bg-black rounded gap-x-1 text-slate-100 group-hover:flex">
        {@value}
      </div>
    </div>
    """
  end

  defp render_field_type(type, assigns)
       when type in [:naive_datetime, :naive_datetime_usec, :utc_datetime, :utc_datetime_usec] do
    ~H"""
    <%= if @value do %>
      <div class="flex flex-col">
        <div class="whitespace-nowrap">
          {format_datetime(@value)}
        </div>
        <div class="-mt-0.5 text-gray-500 text-sm whitespace-nowrap">
          {Slab.Helpers.RelativeTime.format(@value)}
        </div>
      </div>
    <% end %>
    """
  rescue
    _error -> nil
  end

  defp render_field_type(:map, assigns) do
    ~H"""
    <%= if @value do %>
      <.codeblock value={@value} />
    <% end %>
    """
  end

  defp render_field_type({:array, :string}, assigns) do
    ~H"""
    <div :for={item <- @value || []} class="text-sm">{item}</div>
    """
  end

  defp render_field_type(_, assigns) do
    ~H"""
    {@value}
    """
  end

  # Formats as RFC 1123, e.g. "Tue, 06 Mar 2026 01:25:19 +0000"
  defp format_datetime(%DateTime{} = value) do
    Calendar.strftime(value, "%a, %d %b %Y %H:%M:%S %z")
  end

  defp format_datetime(%NaiveDateTime{} = value) do
    Calendar.strftime(value, "%a, %d %b %Y %H:%M:%S")
  end

  # Helpers - Data functions

  defp keys_as_strings(value) when is_map(value) do
    value
    |> Map.keys()
    |> Enum.map(&to_string/1)
  end
end
