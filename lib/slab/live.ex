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
    assigns = normalize_assigns(assigns)
    uri = Map.get(assigns, :uri)
    params = Map.get(assigns, :params, %{})

    {data, has_next?, query_inputs} = resolve_data(assigns, params, socket)
    {total, count_inputs} = resolve_total(assigns, params, socket)

    checkable? = assigns.checkable?
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
      |> assign(:checked_all?, checked_all?)
      |> assign(:checked_ids_lookup, checked_ids_lookup)
      |> assign(:count_inputs, count_inputs)
      |> assign(:data, data)
      |> assign(:field_types, field_types)
      |> assign(:list_data, if(is_list(Map.get(assigns, :data)), do: Map.get(assigns, :data)))
      |> assign(:params, params)
      |> assign(:query_inputs, query_inputs)
      |> assign(:sort, Map.get(params, "sort"))
      |> assign(:sort_direction, Map.get(params, "sort_direction"))
      |> assign(:total, total)
      |> assign(:uri, uri)
      |> assign(:visible_cols, visible_cols(Map.get(assigns, :column, []), params))
      |> assign_pagination(assigns, params, data, has_next?, total)
      |> assign_tabs(assigns, params, uri)
      |> assign_editing(assigns)

    {:ok, socket}
  end

  # Helpers - Inline editing

  # Editing is active when any visible column is editable and an on_save
  # callback is present. Pending edits and save errors are keyed by row id
  # and live in the component — they are transient state, not URL state.
  defp assign_editing(socket, assigns) do
    on_save = Map.get(assigns, :on_save)
    schema = Slab.Query.schema_module(Map.get(assigns, :schema))

    editable_cols =
      for col <- socket.assigns.visible_cols,
          Map.get(col, :editable, false) && is_atom(col[:field]) && col[:field],
          do: col

    edit_inputs =
      Map.new(editable_cols, fn col ->
        {to_string(col.field), {col.field, Slab.Query.filter_input_defaults(schema, col.field)}}
      end)

    socket
    |> assign_new(:edits, fn -> %{} end)
    |> assign_new(:edit_errors, fn -> %{} end)
    |> assign(:editing?, editable_cols != [] && is_function(on_save, 2))
    |> assign(:on_save, on_save)
    |> assign(:edit_inputs, edit_inputs)
  end

  # Slots arrive as lists of maps. Flatten the singleton slots and the
  # config they carry into the assigns the rest of the component reads.
  defp normalize_assigns(assigns) do
    pagination = assigns |> Map.get(:pagination, []) |> List.first()
    export = assigns |> Map.get(:tab, []) |> Enum.find(&(&1.name == "export"))
    checkbox? = Map.get(assigns, :column_checkbox, []) != []

    assigns
    |> Map.put_new(:tab, [])
    |> Map.put_new(:filter, [])
    |> Map.put_new(:column, [])
    |> Map.put(:checkable?, checkbox? && Map.get(assigns, :uri) != nil)
    |> Map.put(:paginate, pagination && pagination[:mode])
    |> Map.put(:per_page, slot_config(pagination, :per_page, 25))
    |> Map.put(:max_per_page, slot_config(pagination, :max_per_page, 100))
    |> Map.put(:per_page_options, slot_config(pagination, :options, [10, 25, 50, 100]))
    |> Map.put(:export_limit, slot_config(export, :limit, 1000))
  end

  defp slot_config(nil, _key, default), do: default
  defp slot_config(entry, key, default), do: Map.get(entry, key) || default

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

  # The tab bar renders <:tab> entries in declaration order. Built-in names
  # get derived labels, icons, and badge counts; custom tabs bring their
  # own. Badge counts derive from the URL params, so they stay correct even
  # when a tab's content is replaced by a custom body.
  defp assign_tabs(socket, assigns, params, uri) do
    schema = Slab.Query.schema_module(Map.get(assigns, :schema))
    columns_param = Map.get(params, "columns")

    counts = %{
      "filters" => Slab.get_filter_count(params),
      "columns" => if(is_list(columns_param), do: length(columns_param), else: 0),
      "share" => if(uri, do: Slab.Helpers.URI.get_query_param_count(uri), else: 0)
    }

    tab_entries =
      for tab <- Map.get(assigns, :tab, []) do
        %{
          name: tab.name,
          label: tab[:label] || tab_label(tab.name),
          icon: tab[:icon] || tab_icon(tab.name),
          count: tab[:count] || Map.get(counts, tab.name, 0),
          slot: tab
        }
      end

    socket
    |> assign(:filter_inputs, filter_inputs(Map.get(assigns, :filter, []), schema))
    |> assign(:tab_entries, tab_entries)
    |> assign(:column_options, column_options(Map.get(assigns, :column, [])))
  end

  defp tab_label("filters"), do: "Filters"
  defp tab_label("columns"), do: "Columns"
  defp tab_label("share"), do: "Share"
  defp tab_label("export"), do: "Export"
  defp tab_label(name), do: name

  defp tab_icon("filters"), do: "funnel-outline"
  defp tab_icon("columns"), do: "view-columns-outline"
  defp tab_icon("share"), do: "bookmark-outline"
  defp tab_icon("export"), do: "arrow-down-tray-outline"
  defp tab_icon(_name), do: nil

  # Picker options for the Columns tab, in declaration order
  defp column_options(cols) do
    for {key, col} <- keyed_cols(cols) do
      case column_label(col) do
        "" -> {key, key}
        label -> {label, key}
      end
    end
  end

  # One input per non-hidden <:filter>. Explicit attrs win; otherwise the
  # type and options derive from the schema — booleans and Ecto.Enum fields
  # get a select with derived options, everything else a text input.
  defp filter_inputs(filters, schema) do
    for filter <- filters, filter[:type] != "hidden" do
      {default_type, default_options} = Slab.Query.filter_input_defaults(schema, filter.field)

      %{
        field: filter.field,
        label: filter[:label] || humanize_field(filter.field),
        type: filter[:type] || default_type,
        options: filter[:options] || default_options,
        placeholder: filter[:placeholder],
        min_chars: filter[:min_chars] || 0,
        debounce: filter[:debounce] || 300
      }
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
      sortable_fields: sortable_fields(Map.get(assigns, :column, [])),
      filterable_cols: filterable_cols(Map.get(assigns, :filter, [])),
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
        filterable = filterable_cols(Map.get(assigns, :filter, []))

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

  # Fields whitelisted for WHERE, from <:filter> declarations — hidden
  # filters whitelist like any other, only their input is absent
  defp filterable_cols(filters) do
    for filter <- filters, is_atom(filter[:field]) && filter[:field] do
      %{field: filter.field, filter: filter[:query]}
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
      |> Map.get(:column, [])
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
      <div :if={@tab_entries != []} class="-mb-4">
        <Slab.tabs id={"#{@id}-tabs"} flush_bottom?>
          <:tab :for={entry <- @tab_entries} label={entry.label} icon={entry.icon} count={entry.count}>
            <.tab_content
              entry={entry}
              id={@id}
              uri={@uri}
              params={@params}
              filter_inputs={@filter_inputs}
              column_options={@column_options}
              paginate={@paginate}
              total={@total}
              export_limit={@export_limit}
              myself={@myself}
            />
          </:tab>
        </Slab.tabs>
      </div>

      <form
        :for={record <- @data}
        :if={@editing?}
        id={row_form_id(@id, record)}
        phx-target={@myself}
        phx-change="edit-row"
        phx-submit="save-row"
      >
        <input type="hidden" name="row_id" value={Map.get(record, :id)} />
      </form>

      <section class="px-4 py-3 border border-gray-200 bg-white shadow-sm rounded-lg">
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
              <.th :if={@editing?}><span class="sr-only">Save</span></.th>
            </.tr>
          </:thead>
          <%= for record <- @data do %>
            <.tr>
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
                  <%= cond do %>
                    <% @editing? && is_map_key(@edit_inputs, to_string(col[:field])) -> %>
                      <.edit_input
                        name={to_string(col.field)}
                        form={row_form_id(@id, record)}
                        value={edit_input_value(@edits, record, col.field)}
                        input={edit_input_config(@edit_inputs, col.field)}
                      />
                    <% col[:inner_block] -> %>
                      {render_slot(col, record)}
                    <% true -> %>
                      {render_field_value(record, col[:field], @field_types)}
                  <% end %>
                </div>
              </.td>
              <.td :if={@editing?}>
                <div class="px-1 flex justify-center">
                  <button
                    type="submit"
                    form={row_form_id(@id, record)}
                    disabled={!row_dirty?(@edits, record)}
                    title={Map.get(@edit_errors, row_key(record)) || "Save row"}
                    class={save_button_class(row_dirty?(@edits, record), Map.has_key?(@edit_errors, row_key(record)))}
                  >
                    <span class="sr-only">Save row</span>
                    <.icon type="check-outline" class="h-5 w-5" />
                  </button>
                </div>
              </.td>
            </.tr>
            <.tr :if={@editing? && Map.has_key?(@edit_errors, row_key(record))}>
              <.td colspan={row_colspan(assigns)}>
                <div class="px-1 -mt-1 pb-1 text-sm text-red-500">
                  {Map.get(@edit_errors, row_key(record))}
                </div>
              </.td>
            </.tr>
          <% end %>
        </.table>
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

  # Built-in tabs render their default content when the slot has no body; a
  # body — on any tab name — takes over the panel.
  defp tab_content(%{entry: %{slot: %{inner_block: nil}, name: "filters"}} = assigns) do
    ~H"""
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
        debounce={input.debounce}
      />
    </div>
    """
  end

  defp tab_content(%{entry: %{slot: %{inner_block: nil}, name: "columns"}} = assigns) do
    ~H"""
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
    """
  end

  defp tab_content(%{entry: %{slot: %{inner_block: nil}, name: "share"}} = assigns) do
    ~H"""
    <Slab.share id={"#{@id}-share"} uri={@uri} />
    """
  end

  defp tab_content(%{entry: %{slot: %{inner_block: nil}, name: "export"}} = assigns) do
    ~H"""
    <div
      id={"#{@id}-export"}
      phx-hook=".Download"
      data-slab-id={@id}
      class="flex items-center gap-x-3"
    >
      <div class="whitespace-nowrap text-sm text-zinc-700">Export CSV</div>
      <div class="flex flex-wrap gap-2">
        <button
          type="button"
          phx-target={@myself}
          phx-click="export-current"
          class={export_button_class()}
        >
          <.icon type="arrow-down-tray-outline" class="h-4 w-4 text-cyan-600" />
          Download current page
        </button>
        <button
          :if={@paginate}
          type="button"
          phx-target={@myself}
          phx-click="export-limit"
          phx-disable-with="Preparing download..."
          class={export_button_class()}
        >
          <.icon type="arrow-down-tray-outline" class="h-4 w-4 text-cyan-600" />
          {export_all_label(@total, @export_limit)}
        </button>
      </div>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".Download">
        export default {
          mounted() {
            this.handleEvent(`slab-download-${this.el.dataset.slabId}`, ({filename, content, mime}) => {
              const blob = new Blob([content], {type: mime || "text/csv;charset=utf-8"})
              const url = URL.createObjectURL(blob)
              const anchor = document.createElement("a")
              anchor.href = url
              anchor.download = filename
              document.body.appendChild(anchor)
              anchor.click()
              anchor.remove()
              URL.revokeObjectURL(url)
            })
          }
        }
      </script>
    </div>
    """
  end

  defp tab_content(assigns) do
    ~H"""
    {render_slot(@entry.slot)}
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

  def handle_event("edit-row", %{"row_id" => row_id} = params, socket) do
    edits =
      case find_record(socket.assigns.data, row_id) do
        nil ->
          socket.assigns.edits

        record ->
          case changed_params(record, params, socket.assigns.edit_inputs) do
            changes when changes == %{} -> Map.delete(socket.assigns.edits, row_id)
            changes -> Map.put(socket.assigns.edits, row_id, changes)
          end
      end

    {:noreply, assign(socket, :edits, edits)}
  end

  def handle_event("save-row", %{"row_id" => row_id} = params, socket) do
    with record when not is_nil(record) <- find_record(socket.assigns.data, row_id),
         changes when changes != %{} <- changed_params(record, params, socket.assigns.edit_inputs) do
      {:noreply, apply_save(socket, record, row_id, changes)}
    else
      _missing_or_unchanged -> {:noreply, socket}
    end
  end

  def handle_event("export-current", _params, socket) do
    {:noreply, push_download(socket, socket.assigns.data)}
  end

  def handle_event("export-limit", _params, socket) do
    {:noreply, push_download(socket, export_records(socket.assigns))}
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

  # Helpers - Inline editing functions

  defp edit_input(%{input: {"select", _options}} = assigns) do
    ~H"""
    <select name={@name} form={@form} class={edit_select_class()}>
      <option :for={{label, value} <- elem(@input, 1)} value={value} selected={to_string(value) == @value}>
        {label}
      </option>
    </select>
    """
  end

  defp edit_input(assigns) do
    ~H"""
    <input type="text" name={@name} form={@form} value={@value} class={edit_text_class()} />
    """
  end

  # Text inputs read as plain text until focused: the border is transparent
  # (not absent, so focusing never shifts layout) and the negative margin
  # cancels the cell padding, aligning the value with non-editable cells.
  defp edit_text_class do
    "w-[calc(100%+0.5rem)] -mx-1 rounded-lg border border-transparent bg-transparent py-1 px-1 " <>
      "text-sm text-zinc-700 focus:border-cyan-600 focus:bg-white focus:outline-none focus:ring-0"
  end

  defp edit_select_class do
    "w-full rounded-lg border border-zinc-300 bg-white py-1 px-2 text-sm text-zinc-700 " <>
      "focus:border-cyan-600 focus:outline-none focus:ring-0"
  end

  defp save_button_class(dirty?, error?) do
    base = "flex items-center justify-center disabled:cursor-default"

    cond do
      error? -> "#{base} text-red-500 hover:text-red-600"
      dirty? -> "#{base} text-cyan-600 hover:text-cyan-700"
      true -> "#{base} text-gray-300"
    end
  end

  defp row_form_id(id, record), do: "#{id}-row-#{Map.get(record, :id)}"

  defp row_key(record), do: to_string(Map.get(record, :id))

  defp row_dirty?(edits, record), do: Map.has_key?(edits, row_key(record))

  defp row_colspan(assigns) do
    length(assigns.visible_cols) + if(assigns.checkable?, do: 2, else: 1)
  end

  defp edit_input_config(edit_inputs, field) do
    {_field, input} = Map.fetch!(edit_inputs, to_string(field))
    input
  end

  # Inputs reflect the pending edit when one exists, so unrelated
  # re-renders never clobber typed-but-unsaved values.
  defp edit_input_value(edits, record, field) do
    case edits |> Map.get(row_key(record), %{}) |> Map.fetch(to_string(field)) do
      {:ok, value} -> value
      :error -> edit_value(record, field)
    end
  end

  # The string an editable field renders into its input — also the baseline
  # a submitted value is compared against to detect a change.
  defp edit_value(record, field) do
    case Map.get(record, field) do
      nil -> ""
      %DateTime{} = value -> DateTime.to_iso8601(value)
      %NaiveDateTime{} = value -> NaiveDateTime.to_iso8601(value)
      %Date{} = value -> Date.to_iso8601(value)
      %Time{} = value -> Time.to_iso8601(value)
      value -> to_string(value)
    end
  end

  # Only declared editable fields are considered, and only values that
  # differ from the record's current value count as changes — raw strings,
  # for the caller's changeset to cast.
  defp changed_params(record, params, edit_inputs) do
    for {key, {field, _input}} <- edit_inputs,
        Map.has_key?(params, key),
        Map.get(params, key) != edit_value(record, field),
        into: %{} do
      {key, Map.get(params, key)}
    end
  end

  defp apply_save(socket, record, row_id, changes) do
    case socket.assigns.on_save.(record, changes) do
      {:ok, updated} ->
        socket
        |> assign(:data, replace_record(socket.assigns.data, row_id, updated))
        |> assign(:edits, Map.delete(socket.assigns.edits, row_id))
        |> assign(:edit_errors, Map.delete(socket.assigns.edit_errors, row_id))

      {:error, error} ->
        socket
        |> assign(:edits, Map.put(socket.assigns.edits, row_id, changes))
        |> assign(
          :edit_errors,
          Map.put(socket.assigns.edit_errors, row_id, format_save_error(error))
        )
    end
  end

  defp find_record(data, row_id) do
    Enum.find(data, fn record -> row_key(record) == row_id end)
  end

  defp replace_record(data, row_id, updated) do
    Enum.map(data, fn record ->
      if row_key(record) == row_id, do: updated, else: record
    end)
  end

  defp format_save_error(%{__struct__: Ecto.Changeset, errors: errors}) do
    Enum.map_join(errors, ", ", fn {field, {message, _opts}} ->
      "#{humanize_field(field)} #{message}"
    end)
  end

  defp format_save_error(message) when is_binary(message), do: message
  defp format_save_error(other), do: inspect(other)

  # Helpers - Export functions

  # In list mode the full list is already in memory; in query mode, re-run
  # the current filtered, sorted query from the top, capped at export_limit —
  # pagination params are dropped so the export always starts at record one.
  defp export_records(%{list_data: list} = assigns) when is_list(list) do
    Enum.take(list, assigns.export_limit)
  end

  defp export_records(assigns) do
    params = Map.drop(assigns.params, ["page", "per_page", "after"])

    opts = %{
      sortable_fields: sortable_fields(assigns.column),
      filterable_cols: filterable_cols(assigns.filter),
      paginate: :page,
      per_page: assigns.export_limit,
      max_per_page: assigns.export_limit
    }

    {records, _has_next?} = Slab.Query.fetch(assigns.schema, assigns.repo, params, opts)
    records
  end

  defp push_download(socket, records) do
    csv = Slab.Export.csv(records, export_columns(socket.assigns.visible_cols))

    # The BOM makes Excel read the CSV as UTF-8
    push_event(socket, "slab-download-#{socket.assigns.id}", %{
      filename: "#{socket.assigns.id}-#{Date.utc_today()}.csv",
      content: "\uFEFF" <> csv,
      mime: "text/csv;charset=utf-8"
    })
  end

  # Exports carry the visible columns in their current order. A column
  # contributes its export_value function when given, otherwise its raw
  # field value; virtual columns with neither (like action links) have no
  # exportable value.
  defp export_columns(cols) do
    for col <- cols, accessor = export_accessor(col) do
      {column_label(col), accessor}
    end
  end

  defp export_accessor(col) do
    cond do
      is_function(col[:export_value], 1) -> col[:export_value]
      is_atom(col[:field]) && col[:field] -> col.field
      true -> nil
    end
  end

  defp export_all_label(total, limit) when is_integer(total) and total <= limit do
    "Download all data"
  end

  defp export_all_label(_total, limit), do: "Download first #{limit} rows"

  defp export_button_class do
    "min-h-10 px-4 flex gap-x-1 items-center justify-center bg-white whitespace-nowrap " <>
      "text-sm text-zinc-700 border border-zinc-300 rounded-lg hover:text-cyan-600"
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
