defmodule Slab do
  @moduledoc """
  A data table component for Phoenix LiveView.

  Renders a table from a list of records and `<:col>` slot definitions, with
  support for:

    * **Automatic cell rendering** based on Ecto schema field types — booleans
      render as check/x icons, datetimes render with absolute and relative
      formats, UUIDs are truncated with a hover tooltip, maps render as
      code blocks.
    * **Custom cell rendering** via slot bodies.
    * **Sortable column headers** rendered as patch links that set `sort` and
      `sort_direction` query params on the URL.
    * **Row selection** (checkboxes) stored in the URL query string, so
      selections survive navigation and pagination.

  Table state — sorting and row selection — lives in the URL. The component
  patches query params; the parent LiveView reacts to `handle_params/3`.
  Callers pass the current `uri` and `params` (both from `handle_params/3`)
  to enable these features.

  ## Usage

  Render a table with `Slab.table/1`, defining columns as `<:col>` slots.
  Data comes from one of two modes:

  **List mode** — pass pre-fetched records via `data`. An optional `schema`
  (an `Ecto.Schema` module) makes values render according to their field
  type; without one, values render as strings:

      <Slab.table id="users-table" data={@users} schema={MyApp.User}>
        <:col field={:id} />
        <:col field={:name} />
        <:col field={:email} />
        <:col field={:inserted_at} />
      </Slab.table>

  **Query mode** — omit `data` and Slab fetches for you. `schema` becomes
  the source to query (an `Ecto.Schema` module or an `%Ecto.Query{}`), run
  through `repo`:

      <Slab.table id="users-table" schema={MyApp.User} repo={MyApp.Repo} uri={@uri} params={@params}>
        <:col field={:name} sortable />
        <:col field={:email} />
      </Slab.table>

  The repo can also be configured once, globally:

      config :slab, repo: MyApp.Repo

  Passing an `%Ecto.Query{}` lets the caller scope what the table can ever
  see (authorization, multi-tenancy) while Slab layers sorting on top:

      <Slab.table id="users-table" schema={from u in MyApp.User, where: u.org_id == ^@org.id} ...>

  A `<:col>` with no body renders the record's `field` automatically.

  ### Custom cell rendering

  Give a `<:col>` a body to take over rendering. The body receives the record
  via `:let`. A `field` is optional — omit it for virtual columns like
  actions, and give the column a `label` instead:

      <Slab.table id="users-table" data={@users}>
        <:col :let={user} field={:name}>{String.upcase(user.name)}</:col>
        <:col :let={user} label="Actions">
          <.link navigate={~p"/users/\#{user}/edit"}>Edit</.link>
        </:col>
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
        <:col field={:name} sortable />
        <:col field={:email} sortable />
      </Slab.table>

  ### Filtering

  Mark columns as `filterable` and Slab translates `filter` URL params into
  WHERE conditions in query mode. Values are cast with `Ecto.Type.cast/2`
  against the schema's field types — strings match with a case-insensitive
  contains, other types by equality, and an operator form enables
  comparisons. Only declared columns are ever filtered; invalid values and
  unknown operators are ignored:

      <Slab.table id="users-table" schema={MyApp.User} repo={MyApp.Repo} uri={@uri} params={@params}>
        <:col field={:name} filterable />
        <:col field={:inserted_at} filterable />
      </Slab.table>

      ?filter[name]=ada                          # WHERE name ILIKE %ada%
      ?filter[active]=true                       # WHERE active = true
      ?filter[inserted_at][gte]=2026-01-01       # WHERE inserted_at >= ...

  Operators: `eq`, `neq`, `gt`, `gte`, `lt`, `lte`, `contains`.

  For custom logic — full-text search, filtering through associations — pass
  a 2-arity `filter_query` function instead. It receives the queryable and the raw
  param value, and can add joins or any Ecto condition (a `filter_query` function
  implies `filterable`):

      <:col field={:organization} filter_query={fn query, value ->
        from u in query,
          join: o in assoc(u, :organization),
          where: ilike(o.name, ^"%\#{value}%")
      end} />

  Render filter inputs with `filter/1`, which patches the `filter[field]`
  param as the user types or selects:

      <Slab.filter id="filter-name" field={:name} uri={@uri} params={@params}
        label="Name" placeholder="Search names..." />

  Or build custom filter UIs in the parent with `filter_path/3`, which sets
  the param and resets pagination. For anything beyond per-field filters,
  scope the `schema` query itself — the escape hatch always works.

  ### Pagination

  Pass `paginate` with one of two modes. `:page` is classic offset
  pagination driven by `page` and `per_page` URL params — it works in both
  data modes (in list mode the list is sliced in memory):

      <Slab.table id="users-table" schema={MyApp.User} repo={MyApp.Repo}
        paginate={:page} per_page={25} uri={@uri} params={@params}>
        <:col field={:name} />
      </Slab.table>

  `:cursor` is keyset pagination driven by an `after` URL param — built for
  constantly-updated data, where new inserts would shift offset pages
  underneath the viewer. Cursors paginate relative to the last-seen record,
  stay correct as records land, avoid deep-offset scans, and need no count
  query. Query mode only; navigation is First/Next (no random page access):

      <Slab.table id="users-table" schema={MyApp.User} repo={MyApp.Repo}
        paginate={:cursor} per_page={25} uri={@uri} params={@params}>
        <:col field={:inserted_at} sortable />
      </Slab.table>

  Cursors are readable, not opaque: `?after[id]=...&after[value]=...` holds
  the last record's id (always the ordering tiebreaker) plus its sort-field
  value when sorting. Both are cast against the schema's field types with
  `Ecto.Type.cast/2` — a tampered cursor falls back to the first page rather
  than erroring or reaching the query. Changing the sort resets pagination
  in either mode.

  Page mode renders a full footer: a "Showing X to Y of Z entries" summary,
  numbered page links with ellipses, and a page-size dropdown (see
  `per_page_options`). The total comes from a count query cached on the
  current filters — page and sort changes never re-count. Cursor mode never
  runs a count query at all; it detects a next page by fetching one extra
  record.

  ### Tabs and sharing

  A tab bar above the table is derived automatically from the table
  definition — no separate declaration:

    * a **Filters** tab appears when any `<:col>` is `filterable`, with one
      input per filterable column and a badge showing the active filter
      count. Input types derive from the schema — booleans and `Ecto.Enum`
      fields get a select with derived options, everything else a text
      input — and the col's `filter_type`, `filter_options`,
      `filter_placeholder`, and `filter_min_chars` attrs override the
      defaults
    * a **Columns** tab appears when `columns_tab?` is set and `uri` is
      given — see the next section
    * a **Share** tab appears when `share_tab?` is set and `uri` is given,
      holding a copyable link to the exact current view

  No qualifying tabs, no tab bar. `tabs/1`, `share/1`, and `filter/1`
  remain public for composing custom layouts outside the table.

  ### Column visibility and order

  The `columns[]` URL param controls which columns render, *in param
  order* — column layout is shareable user state like everything else:

      ?columns[]=email&columns[]=name    # email and name only, email first

  Names are matched against the declared columns (a column's key is its
  `field`, or a slug of its `label` for virtual columns like "Actions" →
  `actions`); unknown names are ignored, and no matches falls back to the
  default view. With no param, columns render in declaration order minus
  those marked `optional`:

      <Slab.table id="users-table" ... columns_tab?>
        <:col field={:name} />
        <:col field={:email} optional />
      </Slab.table>

  The Columns tab renders a multi-select picker driving the param; its
  selection order becomes the column order. Changing columns never resets
  pagination — the result set is unchanged. Sorting and filtering are
  unaffected by visibility: a hidden column's filter still applies.

  ### Row selection

  Pass `checkable?` and the current `uri`. Checked row IDs are stored in the
  `checked` query param via `push_patch`:

      <Slab.table id="users-table" data={@users} checkable? uri={@uri}>
        <:col field={:name} />
      </Slab.table>

  Read selections back with `get_checked_ids/1`, `get_checked_values/3`, and
  `checked?/1`. For selections spanning paginated results, see
  `get_selected_and_missing_ids/3`.

  ## Styling

  Markup is styled with Tailwind CSS utility classes. Ensure your app's
  Tailwind configuration includes this dependency's files so the classes are
  generated — see the README for details.
  """

  use Phoenix.Component

  import Slab.Components, only: [icon: 1]

  alias Phoenix.LiveView.JS

  @doc """
  Renders a data table.

  Columns are defined with `<:col>` slots — see the module docs for full
  usage. Interactive features (row selection) are handled internally by a
  live component; sorting is handled with patch links. Both require the
  current `uri`, and sorting additionally reads the current `params`.

  Data comes from one of two modes:

    * **List mode** — pass `data` with pre-fetched records. `schema` is an
      optional rendering hint.
    * **Query mode** — omit `data` and pass `schema` (an `Ecto.Schema` module
      or an `%Ecto.Query{}`) plus a `repo`; Slab runs the query itself,
      applying sorting from `params`. The repo may also be set globally with
      `config :slab, repo: MyApp.Repo`.

  ## Examples

      <Slab.table id="users-table" data={@users} uri={@uri} params={@params}>
        <:col field={:name} sortable />
        <:col :let={user} label="Actions">
          <.link navigate={"/users/\#{user.id}/edit"}>Edit</.link>
        </:col>
      </Slab.table>

      <Slab.table id="users-table" schema={MyApp.User} repo={MyApp.Repo} uri={@uri} params={@params}>
        <:col field={:name} sortable />
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
    doc: "the current request URI, from handle_params/3; enables sorting and row selection"
  )

  attr(:params, :map,
    default: %{},
    doc: "the current request params, from handle_params/3; carries sort state"
  )

  attr(:checkable?, :boolean,
    default: false,
    doc: "renders row-selection checkboxes; requires uri"
  )

  attr(:paginate, :atom,
    default: nil,
    values: [nil, :page, :cursor],
    doc:
      "pagination mode; `:page` uses page/per_page params (works in both data modes), " <>
        "`:cursor` uses keyset cursors for constantly-updated data (query mode only); " <>
        "requires uri"
  )

  attr(:per_page, :integer,
    default: 25,
    doc: "default page size; the URL per_page param overrides it up to max_per_page"
  )

  attr(:max_per_page, :integer,
    default: 100,
    doc: "upper clamp for the URL per_page param"
  )

  attr(:per_page_options, :list,
    default: [10, 25, 50, 100],
    doc:
      "page sizes offered in the footer dropdown (page mode); values above " <>
        "max_per_page are dropped, and the current size is always included"
  )

  attr(:share_tab?, :boolean,
    default: false,
    doc: "shows the Share tab above the table when uri is present"
  )

  attr(:columns_tab?, :boolean,
    default: false,
    doc:
      "shows the Columns tab above the table when uri is present, letting users " <>
        "toggle and reorder columns via the columns[] URL param"
  )

  slot :col, required: true, doc: "one slot per column" do
    attr(:field, :any,
      doc: "the record field to render; optional for virtual columns with a body"
    )

    attr(:label, :string, doc: "the column header; defaults to the humanized field name")

    attr(:sortable, :boolean,
      doc:
        "renders the header as a sort patch link (requires uri); in query mode, " <>
          "also whitelists the field for ORDER BY"
    )

    attr(:filterable, :boolean,
      doc:
        "whitelists the field for filter URL params in query mode and adds an " <>
          "input to the Filters tab; strings match with case-insensitive contains, " <>
          "other types by equality, and filter[field][op]= enables " <>
          "eq/neq/gt/gte/lt/lte/contains"
    )

    attr(:filter_query, :any,
      doc:
        "custom 2-arity filter function (queryable, value) -> queryable; implies " <>
          "filterable, skips type casting, and may join associations"
    )

    attr(:filter_type, :string,
      values: ["text", "select", "multiselect"],
      doc:
        "overrides the Filters tab input type; defaults by schema type — " <>
          "booleans and Ecto.Enum fields get a select, everything else text"
    )

    attr(:filter_options, :list,
      doc:
        "options for select/multiselect filter inputs, as `[{label, value}]` " <>
          "tuples or plain values; derived automatically for booleans and " <>
          "Ecto.Enum fields"
    )

    attr(:filter_placeholder, :string, doc: "placeholder for the Filters tab input")

    attr(:filter_min_chars, :integer,
      doc: "minimum characters before a text filter change applies (default 0)"
    )

    attr(:optional, :boolean,
      doc:
        "starts the column hidden until enabled through the Columns tab or the " <>
          "columns[] URL param"
    )
  end

  def table(assigns) do
    validate_pagination!(assigns)
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
      checkable?={@checkable?}
      paginate={@paginate}
      per_page={@per_page}
      max_per_page={@max_per_page}
      per_page_options={@per_page_options}
      share_tab?={@share_tab?}
      columns_tab?={@columns_tab?}
      col={@col}
    />
    """
  end

  defp validate_pagination!(%{paginate: nil}), do: :ok

  defp validate_pagination!(%{paginate: paginate, data: data, uri: uri}) do
    cond do
      is_nil(uri) ->
        raise ArgumentError,
              "Slab.table pagination requires uri — without it the table would be " <>
                "truncated with no way to navigate. Pass uri={@uri} from handle_params/3."

      paginate == :cursor && is_list(data) ->
        raise ArgumentError,
              "Slab.table cursor pagination requires query mode — pass schema and repo " <>
                "instead of data, or use paginate={:page} to paginate a list in memory."

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

    * `"text"` (default) — debounced text input; with a string-typed column
      this becomes a case-insensitive contains match
    * `"select"` — a searchable single select ([PhoenixSelect](https://github.com/chrislaskey/phoenix_select));
      clearing the selection clears the filter
    * `"multiselect"` — a searchable multi select; the selected values filter
      with `field IN (...)`

  The select types render via PhoenixSelect's colocated hook — register it
  once in `assets/js/app.js` (see the README's installation section).

  ## Examples

      <Slab.filter id="filter-name" field={:name} uri={@uri} params={@params}
        label="Name" placeholder="Search names..." />

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
    doc: "the filter key — matches a `<:col filterable>` field on the table"
  )

  attr(:uri, :string,
    required: true,
    doc: "the current request URI, from handle_params/3"
  )

  attr(:params, :map,
    default: %{},
    doc: "the current request params, from handle_params/3; carries the current value"
  )

  attr(:type, :string,
    default: "text",
    values: ["text", "select", "multiselect"],
    doc: "the input type"
  )

  attr(:label, :string, default: nil, doc: "optional label rendered above the input")

  attr(:placeholder, :string, default: nil, doc: "placeholder for the input")

  attr(:options, :list,
    default: [],
    doc: "select options, as `[{label, value}]` tuples or plain values"
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

  def filter(%{type: "text"} = assigns) do
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

  def filter(assigns) do
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
        <form class="border border-gray-200 rounded w-full">
          <input
            type="text"
            readonly
            value={@uri}
            data-slab-share-url
            class="m-0 py-1 px-4 w-full text-sm border-0 rounded bg-white text-zinc-700 outline-0 focus:outline-none"
          />
        </form>
        <button
          id={"#{@id}-copy"}
          phx-hook=".CopyToClipboard"
          type="button"
          class="px-2 flex gap-x-1 items-center justify-center bg-white whitespace-nowrap text-sm border border-gray-200 rounded hover:text-cyan-600"
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
