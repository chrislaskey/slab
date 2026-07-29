<p align="center">
  <img title="v1.0.0 Screenshot" src="https://raw.githubusercontent.com/chrislaskey/slab/refs/heads/main/examples/screenshot-v1.0.0.png" width="600">
</p>

# Slab

> A data table component for Phoenix LiveView.

A table is composed from slots — every optional region is declared by the
presence of a slot, and nothing renders that wasn't declared:

- **`<:column>`** — automatic cell rendering based on Ecto schema field types
  (booleans render as check/x icons, datetimes with absolute and relative
  formats, UUIDs truncated with a full-value hover tooltip, maps as code
  blocks), custom bodies, and URL-driven sorting.
- **`<:column_checkbox>`** — row selection stored in the URL query string, so
  selections survive navigation, pagination, and refreshes — and are
  shareable as links.
- **`<:filter>`** — declarative, whitelisted filtering driven by `filter[...]`
  URL params, with ready-made inputs.
- **`<:tab>`** — a tab bar above the table: Filters, Columns, Share, Export,
  or fully custom tabs, in declaration order.
- **`<:pagination>`** — offset or keyset pagination.

Table state lives in the URL: the component patches query params, and the
parent LiveView reacts to `handle_params/3` by requerying. Callers pass in the
current `uri` and `params` to enable these features.

## Demo app

The `/examples` directory contains many examples, including a full
Phoenix demo app that demonstrates the different options:

```
git clone https://github.com/chrislaskey/slab.git
cd slab/examples/demo
mix setup && iex -S mix phx.server
```

Note: the script `examples/regenerate.sh` can be used to regenerate the demo from a pinned
`phx.new` release.

## Installation

Add `slab` to your dependencies in `mix.exs` (requires LiveView `~> 1.1`):

```elixir
def deps do
  [
    {:slab, "~> 2.0"}
  ]
end
```

### JavaScript hooks

Slab ships a small amount of JavaScript (the Share tab's copy-to-clipboard
button and the Export tab's download trigger) as colocated hooks, and
select/multiselect filters are rendered by
[phoenix_select](https://github.com/chrislaskey/phoenix_select) (pulled in
automatically), which does the same — nothing to `npm install`, but both
hook sets must be registered once in `assets/js/app.js`:

```javascript
import {hooks as slabHooks} from "phoenix-colocated/slab"
import {hooks as phoenixSelectHooks} from "phoenix-colocated/phoenix_select"

const liveSocket = new LiveSocket("/live", Socket, {
  hooks: {...colocatedHooks, ...slabHooks, ...phoenixSelectHooks},
  // ...
})
```

### Tailwind CSS

The components are styled with Tailwind utility classes. Add both libraries
to your Tailwind sources so the classes are generated.

Tailwind v4 (`assets/css/app.css`):

```css
@source "../../deps/slab/lib";
@source "../../deps/phoenix_select/lib";
```

Tailwind v3 (`assets/tailwind.config.js`):

```js
content: [
  // ...existing paths
  "../deps/slab/lib/**/*.ex",
  "../deps/phoenix_select/lib/**/*.ex",
],
```

## Usage

Render a table with `Slab.table/1`, defining columns as `<:column>` slots.
Data comes from one of two modes.

**List mode** — pass pre-fetched records via `data`:

```heex
<Slab.table id="users-table" data={@users} schema={MyApp.User}>
  <:column field={:id} />
  <:column field={:name} />
  <:column field={:email} />
  <:column field={:inserted_at} />
</Slab.table>
```

**Query mode** — omit `data` and Slab fetches for you. `schema` becomes the
source to query (an `Ecto.Schema` module or an `%Ecto.Query{}`), run through
`repo`:

```heex
<Slab.table id="users-table" schema={MyApp.User} repo={MyApp.Repo} uri={@uri} params={@params}>
  <:column field={:name} sortable />
  <:column field={:email} />
</Slab.table>
```

The repo can also be configured once, globally:

```elixir
config :slab, repo: MyApp.Repo
```

Passing an `%Ecto.Query{}` lets you scope what the table can ever see
(authorization, multi-tenancy) while Slab layers sorting and filtering on
top:

```heex
<Slab.table id="users-table" schema={from u in User, where: u.org_id == ^@org.id} ...>
```

Query mode requires Ecto, which is an optional dependency — your app's Ecto
version is used as-is. List mode works without Ecto entirely.

A `<:column>` with no body renders the record's `field` automatically.

### Automatic type-based rendering

Pass a `schema` (an `Ecto.Schema` module) and cells render according to each
field's type. Without a schema, values render as plain strings. In query
mode the schema is already known, so typed rendering is automatic.

### Custom cell rendering

Give a `<:column>` a body to take over rendering — the body receives the
record via `:let`. A `field` is optional: omit it for virtual columns like
actions, and give the column a `label` instead:

```heex
<Slab.table id="users-table" data={@users}>
  <:column :let={user} field={:status}>{String.upcase(user.status)}</:column>
  <:column :let={user} label="Actions">
    <.link navigate={~p"/users/#{user}/edit"}>Edit</.link>
  </:column>
</Slab.table>
```

### Sorting

Mark columns as `sortable` and pass the current `uri` and `params`. Sortable
headers render as patch links that set the `sort` and `sort_direction` query
params — nothing else. In query mode Slab requeries with the new sort
automatically, and only fields declared `sortable` are ever compiled into
`ORDER BY`, so URL tampering cannot sort by arbitrary columns. In list mode,
the parent LiveView reacts in `handle_params/3` by requerying:

```elixir
# In the parent LiveView
def handle_params(params, uri, socket) do
  socket =
    socket
    |> assign(:uri, uri)
    |> assign(:params, params)
    |> assign(:users, list_users(params))

  {:noreply, socket}
end
```

```heex
<Slab.table id="users-table" data={@users} uri={@uri} params={@params}>
  <:column field={:name} sortable />
  <:column field={:email} sortable />
</Slab.table>
```

### Filtering

Declare a `<:filter>` per filterable field and Slab translates `filter` URL
params into WHERE conditions in query mode:

```heex
<Slab.table id="users-table" schema={MyApp.User} repo={MyApp.Repo} uri={@uri} params={@params}>
  <:tab name="filters" />
  <:filter field={:name} />
  <:filter field={:inserted_at} />
  <:column field={:name} />
  <:column field={:inserted_at} />
</Slab.table>
```

```
?filter[name]=ada                          # WHERE lower(name) LIKE %ada%
?filter[active]=true                       # WHERE active = true
?filter[inserted_at][gte]=2026-01-01       # WHERE inserted_at >= ...
```

Values are cast with `Ecto.Type.cast/2` against the schema's field types —
strings match with a case-insensitive contains, other types by equality, and
`filter[field][op]=` enables `eq`, `neq`, `gt`, `gte`, `lt`, `lte`, and
`contains`. Only declared fields are ever filtered; invalid values, unknown
operators, and LIKE wildcards in user input are all neutralized.

Filters are field-level, not column-level — a `<:filter>` needs no matching
`<:column>`, so you can filter on fields the table never shows.

For custom logic — full-text search, filtering through associations — pass a
2-arity `query` function. It receives the queryable and the raw param value,
and can add joins or any Ecto condition:

```heex
<:filter field={:organization} query={fn query, value ->
  from u in query,
    join: o in assoc(u, :organization),
    where: ilike(o.name, ^"%#{value}%")
end} />
```

### Filter inputs

Each `<:filter>` defines its input in the Filters tab (declare
`<:tab name="filters" />` to render it). Input types derive from the
schema — booleans and `Ecto.Enum` fields get a select with derived options,
everything else a text input — and the `type`, `label`, `options`,
`placeholder`, `min_chars`, and `debounce` attrs override the defaults:

```heex
<:tab name="filters" />
<:filter field={:name} placeholder="Search names..." min_chars={2} />
<:filter field={:role} type="multiselect" />
<:filter field={:active} type="select" options={[{"Active", "true"}, {"Inactive", "false"}]} />
```

Text inputs debounce (default 300ms) and can wait for `min_chars` before
applying. Select and multiselect are searchable, keyboard-navigable
comboboxes from [phoenix_select](https://github.com/chrislaskey/phoenix_select);
clearing the selection clears the filter, and multiselect values filter with
`field IN (...)`. Remember the one-time hook registration from the
installation section.

### External filter UI

The contract between filter UI and the table is the URL — any component that
patches `filter[field]` params drives the table, which only requires the
field to be whitelisted by a `<:filter>`. Declare a filter as
`type="hidden"` to whitelist it without rendering an input, and place
`Slab.filter/1` (or your own component) anywhere on the page:

```heex
<div class="flex gap-x-4">
  <Slab.filter id="filter-name" schema={MyApp.User} field={:name}
    uri={@uri} params={@params} label="Name" placeholder="Search names..." />
  <Slab.filter id="filter-role" schema={MyApp.User} field={:role}
    uri={@uri} params={@params} label="Role" />
</div>

<Slab.table id="users-table" schema={MyApp.User} repo={MyApp.Repo} uri={@uri} params={@params}>
  <:filter field={:name} type="hidden" />
  <:filter field={:role} type="hidden" />
  <:column field={:name} sortable />
  <:column field={:role} />
</Slab.table>
```

`Slab.filter/1` derives its input type and options from the optional
`schema` attr, exactly like the Filters tab does.

Components not owned by Slab integrate the same way: patch the URL with
`filter[field]=value` (or `filter[field][]=value` for multi-selects, and
`filter[field][op]=value` for operators) — `Slab.filter_path/3` builds those
paths and resets pagination. Because state stays in the URL, sharing,
back-button, and exports keep working with any filter UI. For anything
beyond per-field filters, scope the `schema` query itself — the escape hatch
always works.

### Pagination

Declare a `<:pagination>` slot with one of two modes.

`:page` is classic offset pagination driven by `page` and `per_page` URL
params. It works in both data modes — in list mode the list is sliced in
memory. The `per_page` attr sets the default page size; a `per_page` URL
param can override it but is clamped to `max_per_page` (default 100), so a
crafted URL can't request unbounded rows:

```heex
<Slab.table id="users-table" schema={MyApp.User} repo={MyApp.Repo} uri={@uri} params={@params}>
  <:column field={:name} />
  <:pagination mode={:page} per_page={25} />
</Slab.table>
```

`:cursor` is keyset pagination driven by an `after` URL param — built for
constantly-updated data, where new inserts shift offset pages underneath the
viewer. Cursors paginate relative to the last-seen record, stay correct as
records land, avoid deep-offset scans, and need no count query. Query mode
only; navigation is First/Next (no random page access):

```heex
<Slab.table id="users-table" schema={MyApp.User} repo={MyApp.Repo} uri={@uri} params={@params}>
  <:column field={:inserted_at} sortable />
  <:pagination mode={:cursor} per_page={25} />
</Slab.table>
```

Cursors are readable, not opaque blobs: `?after[id]=...&after[value]=...`
holds the last record's id (always the ordering tiebreaker) plus its
sort-field value when sorting. Both are cast against the schema's field types
with `Ecto.Type.cast/2` — a tampered cursor falls back to the first page
rather than erroring or reaching the query. Changing the sort resets
pagination in either mode.

Page mode renders a full footer: a "Showing 1 to 25 of 223 entries" summary
on the left, numbered page links with ellipses (`1 … 4 5 6 … 21`) and
prev/next chevrons, and a page-size dropdown (the `options` attr, default
`[10, 25, 50, 100]`). The total comes from a count query cached on the
current filters — page and sort changes never re-count, only filter changes
do. Cursor mode never runs a count query at all; both modes detect a next
page by fetching one extra record.

### Tabs

Declare `<:tab>` slots to render a tab bar above the table. Tabs render in
declaration order. Four names have built-in content:

- **`<:tab name="filters" />`** — one input per non-hidden `<:filter>`, with
  a badge showing the active filter count; requires `uri`
- **`<:tab name="columns" />`** — a picker driving the `columns[]` URL param
  (see the next section); requires `uri`
- **`<:tab name="share" />`** — a read-only copy of the current URL with a
  copy-to-clipboard button — meaningful because *all* table state lives in
  the URL; requires `uri`
- **`<:tab name="export" />`** — CSV downloads (see
  [Exporting](#exporting)); takes a `limit` attr

A body on a built-in tab replaces its default content (badge counts stay
params-derived either way), and any other `name` defines a custom tab —
give it a `label`, an optional `icon` and `count`, and a body:

```heex
<:tab name="filters" />
<:tab name="help" label="Help" icon="bookmark-outline">
  <p>Contact #data-team for access questions.</p>
</:tab>
```

No `<:tab>` slots, no tab bar. The building blocks stay public for custom
layouts outside the table: `Slab.tabs/1` (client-side tabs with icons and
count badges), `Slab.share/1`, and `Slab.filter/1`, plus the badge helpers
`Slab.get_filter_count/1` and `Slab.Helpers.URI.get_query_param_count/1`.

### Exporting

The Export tab downloads the table as CSV, generated server-side and
delivered through the browser — no routes or setup beyond registering
Slab's hooks (see [JavaScript hooks](#javascript-hooks)). It offers two
buttons:

- **Download current page** — the rows exactly as displayed
- **Download all data** — the first `limit` rows (default 1000) of the
  current filtered, sorted result; when the total exceeds the limit the
  button reads "Download first N rows" instead

```heex
<Slab.table id="users-table" schema={MyApp.User} repo={MyApp.Repo} uri={@uri} params={@params}>
  <:tab name="export" limit={5000} />
  <:column field={:name} />
  <:pagination mode={:page} />
</Slab.table>
```

Exports honor the current filters, sort, and column selection. Columns
export their raw field values — nil as empty, dates and times as ISO 8601,
lists joined with `", "` — or the result of their `export_value` function
when given, a 1-arity function receiving the record:

```heex
<:column :let={user} label="Products"
  export_value={fn user -> Enum.map_join(user.products, ", ", & &1.name) end}>
  <.product_badges products={user.products} />
</:column>
```

That is how computed columns (a body but no `field`) join an export;
without a `field` or an `export_value`, a virtual column (like action
links) is skipped. `Slab.Export.csv/2` is public for reuse in custom
export code.

The file travels over the LiveView socket as part of a `push_event`, which
is what makes the zero-setup delivery possible — and why `limit` should
stay in the thousands. For genuinely large exports, stream from a
controller instead: reuse `Slab.Query.apply_filters/4` and
`Slab.Query.apply_sort/3` to reconstruct the query from the same URL
params, and `Slab.Export.csv/2` to serialize each batch.

### Column visibility and order

The `columns[]` URL param controls which columns render, *in param order* —
column layout is shareable user state like everything else:

```
?columns[]=email&columns[]=name    # email and name only, email first
```

Names match the declared columns (a column's key is its `field`, or a slug
of its `label` for virtual columns — "Actions" → `actions`); unknown names
are ignored, and no matches falls back to the default view. With no param,
columns render in declaration order minus those marked `optional`:

```heex
<Slab.table id="users-table" ...>
  <:tab name="columns" />
  <:column field={:name} />
  <:column field={:email} optional />
</Slab.table>
```

The Columns tab renders a multi-select picker driving the param; its
selection order becomes the column order. Changing columns never resets
pagination, and sorting/filtering are unaffected by visibility — a hidden
column's filter still applies.

### Row selection

Declare `<:column_checkbox />` and pass the current `uri`. It renders as the
first column, always visible — it is not addressable through the Columns tab
or the `columns[]` param:

```heex
<Slab.table id="users-table" data={@users} uri={@uri}>
  <:column_checkbox />
  <:column field={:name} />
  <:column field={:email} />
</Slab.table>
```

Checked row IDs live in the `checked` query param. Read them back anywhere:

```elixir
Slab.get_checked_ids(uri)          #=> ["1", "42"]
Slab.get_checked_values(uri, records)
Slab.checked?(uri)
```

For selections that span paginated results, use
`Slab.get_selected_and_missing_ids/3` to split checked IDs into records
already on the current page and IDs that need fetching.

### Inline editing

Mark columns as `editable` and pass an `on_save` function. Editable columns
render their input directly in the cell — there is no edit mode — and a
save column (no heading) appears at the end of the table. Editing a value
highlights the row's save button; clicking it (or pressing Enter) calls
`on_save` once with the row's record and the changed fields:

```heex
<Slab.table id="users-table" schema={MyApp.User} repo={MyApp.Repo}
  uri={@uri} params={@params} on_save={&save_user/2}>
  <:column field={:name} editable />
  <:column field={:role} editable />
  <:column field={:inserted_at} />
</Slab.table>
```

```elixir
def save_user(user, params) do
  user
  |> MyApp.User.changeset(params)
  |> MyApp.Repo.update()
end
```

Slab never writes to the database itself: `on_save` receives the record and
a map of only the changed fields, with raw string values
(`%{"name" => "Ada"}`) — cast them with your own changeset. Return
`{:ok, updated_record}` to clear the row's pending state and render the
updated record in place, or `{:error, changeset_or_message}` to keep the
edits and show the error under the row.

Input types derive from the schema — booleans and `Ecto.Enum` fields get a
select, everything else a text input. Text inputs read as plain text until
focused, keeping the table scannable. Multiple columns can change before
one save, and each row saves independently (each row is its own form, so
Enter submits just that row). Pending edits are component state, not URL
state: they survive re-renders, sorting, and filtering, but not a page
reload.

## Reference

Full documentation for every attribute, with types and defaults, is generated
from the component declarations — run `mix docs` or see the `Slab` module on
HexDocs. The tables below are the quick version.

### `Slab.table/1` attributes

| Attribute | Default | Example | Description |
| --- | --- | --- | --- |
| `id` | required | `id="users-table"` | Unique component id |
| `data` | `nil` | `data={@users}` | Pre-fetched records (list mode); omit for query mode |
| `schema` | `nil` | `schema={MyApp.User}` | Rendering hint in list mode; the queryable (schema module or `%Ecto.Query{}`) in query mode |
| `repo` | `nil` | `repo={MyApp.Repo}` | Repo for query mode; falls back to `config :slab, repo: MyApp.Repo` |
| `uri` | `nil` | `uri={@uri}` | Current request URI from `handle_params/3`; required by URL-driven slots |
| `params` | `%{}` | `params={@params}` | Current request params from `handle_params/3`; carries sort/page/filter/column/selection state |
| `on_save` | `nil` | `on_save={&save_user/2}` | 2-arity `(record, changed_params) -> {:ok, record} \| {:error, error}` called on row save; required when any column is `editable` |

### `<:column>` slot attributes

| Attribute | Default | Example | Description |
| --- | --- | --- | --- |
| `field` | `nil` | `field={:name}` | Record field to render; optional for virtual columns with a body |
| `label` | humanized field | `label="Full Name"` | Column header text |
| `sortable` | `false` | `sortable` | Header becomes a sort patch link; whitelists the field for `ORDER BY` in query mode |
| `optional` | `false` | `optional` | Starts the column hidden until enabled via the Columns tab or `columns[]` param |
| `export_value` | `nil` | `export_value={&products_csv/1}` | 1-arity `(record) -> value` used when exporting; makes virtual columns exportable and overrides the raw field value |
| `editable` | `false` | `editable` | Renders the cell as an input feeding the row's save action; requires a `field` and the table's `on_save`, and cannot combine with a body |

Columns with a body receive the record via `:let`:

```heex
<:column :let={user} field={:name}>{String.upcase(user.name)}</:column>
```

### `<:column_checkbox>` slot

Row-selection checkboxes, always the first column and always visible. At
most one; requires `uri`. No attributes.

### `<:filter>` slot attributes

| Attribute | Default | Example | Description |
| --- | --- | --- | --- |
| `field` | required | `field={:name}` | Field to filter on; whitelists it for `filter[...]` URL params |
| `label` | humanized field | `label="Full Name"` | Label for the Filters tab input |
| `type` | derived | `type="multiselect"` | Input type (`"text"`, `"select"`, `"multiselect"`); `"hidden"` whitelists without rendering an input |
| `options` | derived | `options={[{"Admin", "admin"}]}` | Options for select/multiselect inputs; derived automatically for booleans and `Ecto.Enum` fields |
| `placeholder` | `nil` | `placeholder="Search..."` | Placeholder for the input |
| `min_chars` | `0` | `min_chars={3}` | Minimum characters before a text filter change applies |
| `debounce` | `300` | `debounce={500}` | Milliseconds to debounce text input changes |
| `query` | `nil` | `query={&by_org/2}` | Custom 2-arity `(queryable, value) -> queryable` filter; may join associations |

### `<:tab>` slot attributes

| Attribute | Default | Example | Description |
| --- | --- | --- | --- |
| `name` | required | `name="filters"` | `"filters"`, `"columns"`, `"share"`, `"export"`, or a custom tab's identity |
| `label` | derived | `label="Help"` | Tab label; derived for built-in names, required for custom tabs |
| `icon` | derived | `icon="bookmark-outline"` | Icon before the label; see `Slab.Components.icon/1` |
| `count` | derived | `count={3}` | Badge count for custom tabs; built-in tabs compute their own |
| `limit` | `1000` | `limit={5000}` | Export only: maximum rows in a full-data export |

### `<:pagination>` slot attributes

| Attribute | Default | Example | Description |
| --- | --- | --- | --- |
| `mode` | required | `mode={:page}` | `:page` (offset, both modes) or `:cursor` (keyset, query mode only); requires `uri` |
| `per_page` | `25` | `per_page={50}` | Default page size |
| `max_per_page` | `100` | `max_per_page={200}` | Upper clamp for the URL `per_page` param, so a crafted URL can't request unbounded rows |
| `options` | `[10, 25, 50, 100]` | `options={[25, 100]}` | Page sizes offered in the footer dropdown (page mode) |

### `Slab.filter/1` attributes

| Attribute | Default | Example | Description |
| --- | --- | --- | --- |
| `id` | required | `id="filter-name"` | Unique component id |
| `field` | required | `field={:name}` | Filter key; matches a `<:filter>` field on the table |
| `uri` | required | `uri={@uri}` | Current request URI from `handle_params/3` |
| `params` | `%{}` | `params={@params}` | Current request params; carries the input's current value |
| `schema` | `nil` | `schema={MyApp.User}` | Derives the input type and options when not given |
| `type` | derived | `type="multiselect"` | `"text"`, `"select"`, or `"multiselect"`; derived from `schema` when omitted |
| `label` | `nil` | `label="Status"` | Label rendered beside the input |
| `placeholder` | `nil` | `placeholder="Search..."` | Placeholder for the input |
| `options` | derived | `options={[{"Active", "true"}]}` | Select options, as `[{label, value}]` tuples or plain values |
| `debounce` | `300` | `debounce={500}` | Milliseconds to debounce text input changes |
| `min_chars` | `0` | `min_chars={3}` | Minimum characters before a text change applies; empty always applies (clearing the filter) |

### `Slab.tabs/1` attributes

| Attribute | Default | Example | Description |
| --- | --- | --- | --- |
| `id` | required | `id="table-tabs"` | Unique DOM id |
| `active` | first tab | `active="Filters"` | Label of the initially active tab |

Each `<:tab>` slot takes `label` (required), `icon` (optional, see
`Slab.Components.icon/1`), and `count` (optional badge, hidden when zero).

### `Slab.share/1` attributes

| Attribute | Default | Example | Description |
| --- | --- | --- | --- |
| `uri` | required | `uri={@uri}` | Current request URI shown in the copyable input |

### URL params

The URL is Slab's state contract — every param is readable, shareable, and
validated against whitelists and field types before touching a query:

| Param | Written by | Example |
| --- | --- | --- |
| `sort`, `sort_direction` | Sortable headers | `?sort=name&sort_direction=desc` |
| `page`, `per_page` | Page-mode pagination | `?page=3&per_page=50` |
| `after[id]`, `after[value]` | Cursor-mode pagination | `?after[id]=42&after[value]=2026-01-01T00%3A00%3A00Z` |
| `filter[field]` | Filter inputs | `?filter[name]=ada` |
| `filter[field][op]` | Custom filter UIs | `?filter[age][gte]=21` |
| `columns` | Columns tab picker | `?columns[]=email&columns[]=name` |
| `checked` | Row-selection checkboxes | `?checked[]=1&checked[]=42` |

### Helper functions

| Function | Description |
| --- | --- |
| `Slab.sort_path(uri, params, field)` | Path that sorts by `field`, flipping direction and resetting pagination |
| `Slab.page_path(uri, page)` | Path for a page number; page 1 drops the param |
| `Slab.filter_path(uri, field, value)` | Path that sets/clears `filter[field]` and resets pagination |
| `Slab.get_filter_count(uri_or_params)` | Number of active filters (for a filters tab badge) |
| `Slab.Helpers.URI.get_query_param_count(uri)` | Recursive count of query params (for a share tab badge) |
| `Slab.get_checked_ids(uri_or_params)` | Checked row IDs as strings |
| `Slab.get_checked_count(uri_or_params)` | Number of checked rows |
| `Slab.get_checked_values(uri, records, opts)` | Records whose ID is checked |
| `Slab.checked?(uri_or_params)` | Whether any rows are checked |
| `Slab.get_selected_and_missing_ids(records, ids, opts)` | Splits selections into current-page records and IDs to fetch (cross-page selection) |

## Architecture

`Slab.table/1` is a function component — it declares and validates attributes
and slots at compile time, and is the stable public interface. Internally it
renders `Slab.Live`, a live component that owns interactive state: row
selection, and in query mode the data fetching itself — queries only re-run
when their inputs (source, repo, sort) actually change, not on every parent
re-render. Sorting needs no events at all: headers are plain patch links
built with `Slab.sort_path/3`.

Cross-slot reads are the core of the design: because every slot is a sibling
under one component, the Filters tab reads the `<:filter>` declarations, the
Columns tab and exports read the `<:column>` declarations, and the query
whitelists derive from both — one declaration, consistently enforced.

## Testing

```
mix test
```

## License

MIT — see [LICENSE.md](LICENSE.md).
