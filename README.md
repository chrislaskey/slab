<p align="center">
  <img title="v1.0.0 Screenshot" src="https://raw.githubusercontent.com/chrislaskey/slab/refs/heads/main/examples/screenshot-v1.0.0.png" width="600">
</p>

# Slab

> A data table component for Phoenix LiveView.

Pass records and column slots, get a rendered table with:

- **Automatic cell rendering** based on Ecto schema field types — booleans render
  as check/x icons, datetimes render with absolute and relative formats, UUIDs
  are truncated with a full-value hover tooltip, maps render as code blocks,
  string arrays render one item per line.
- **Custom cell rendering** via `<:col>` slot bodies.
- **Sortable column headers** rendered as patch links that set `sort` and
  `sort_direction` query params on the URL.
- **Row selection** (checkboxes) stored in the URL query string, so selections
  survive navigation, pagination, and refreshes — and are shareable as links.

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
    {:slab, github: "chrislaskey/slab"}
  ]
end
```

### JavaScript hooks

Slab ships a small amount of JavaScript (the share tab's copy-to-clipboard
button) as a colocated hook, and select/multiselect filters are rendered by
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

Render a table with `Slab.table/1`, defining columns as `<:col>` slots. Data
comes from one of two modes.

**List mode** — pass pre-fetched records via `data`:

```heex
<Slab.table id="users-table" data={@users} schema={MyApp.User}>
  <:col field={:id} />
  <:col field={:name} />
  <:col field={:email} />
  <:col field={:inserted_at} />
</Slab.table>
```

**Query mode** — omit `data` and Slab fetches for you. `schema` becomes the
source to query (an `Ecto.Schema` module or an `%Ecto.Query{}`), run through
`repo`:

```heex
<Slab.table id="users-table" schema={MyApp.User} repo={MyApp.Repo} uri={@uri} params={@params}>
  <:col field={:name} sortable />
  <:col field={:email} />
</Slab.table>
```

The repo can also be configured once, globally:

```elixir
config :slab, repo: MyApp.Repo
```

Passing an `%Ecto.Query{}` lets you scope what the table can ever see
(authorization, multi-tenancy) while Slab layers sorting on top:

```heex
<Slab.table id="users-table" schema={from u in User, where: u.org_id == ^@org.id} ...>
```

Query mode requires Ecto, which is an optional dependency — your app's Ecto
version is used as-is. List mode works without Ecto entirely.

A `<:col>` with no body renders the record's `field` automatically.

### Automatic type-based rendering

Pass a `schema` (an `Ecto.Schema` module) and cells render according to each
field's type. Without a schema, values render as plain strings. In query
mode the schema is already known, so typed rendering is automatic.

### Custom cell rendering

Give a `<:col>` a body to take over rendering — the body receives the record
via `:let`. A `field` is optional: omit it for virtual columns like actions,
and give the column a `label` instead:

```heex
<Slab.table id="users-table" data={@users}>
  <:col :let={user} field={:status}>{String.upcase(user.status)}</:col>
  <:col :let={user} label="Actions">
    <.link navigate={~p"/users/#{user}/edit"}>Edit</.link>
  </:col>
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
  <:col field={:name} sortable />
  <:col field={:email} sortable />
</Slab.table>
```

### Filtering

Mark columns as `filterable` and Slab translates `filter` URL params into
WHERE conditions in query mode:

```heex
<Slab.table id="users-table" schema={MyApp.User} repo={MyApp.Repo} uri={@uri} params={@params}>
  <:col field={:name} filterable />
  <:col field={:inserted_at} filterable />
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
`contains`. Only declared columns are ever filtered; invalid values, unknown
operators, and LIKE wildcards in user input are all neutralized.

For custom logic — full-text search, filtering through associations — pass a
2-arity `filter_query` function instead. It receives the queryable and the
raw param value, and can add joins or any Ecto condition (a `filter_query`
function implies `filterable`):

```heex
<:col field={:organization} filter_query={fn query, value ->
  from u in query,
    join: o in assoc(u, :organization),
    where: ilike(o.name, ^"%#{value}%")
end} />
```

### Filter inputs

`Slab.filter/1` renders a ready-made filter input that drives the
`filter[field]` param — point it at a filterable column and the table
requeries as the user types or selects:

```heex
<div class="flex gap-x-4">
  <Slab.filter id="filter-name" field={:name} uri={@uri} params={@params}
    label="Name" placeholder="Search names..." min_chars={3} />

  <Slab.filter id="filter-active" field={:active} uri={@uri} params={@params}
    type="select" label="Status"
    options={[{"Active", "true"}, {"Inactive", "false"}]} />

  <Slab.filter id="filter-role" field={:role} uri={@uri} params={@params}
    type="multiselect" label="Roles"
    options={[{"Admin", "admin"}, {"Member", "member"}, {"Guest", "guest"}]} />
</div>

<Slab.table id="users-table" schema={MyApp.User} repo={MyApp.Repo} uri={@uri} params={@params}>
  <:col field={:name} filterable sortable />
  <:col field={:active} filterable />
  <:col field={:role} filterable />
</Slab.table>
```

Text inputs debounce (default 300ms) and can wait for `min_chars` before
applying. Select and multiselect are searchable, keyboard-navigable
comboboxes from [phoenix_select](https://github.com/chrislaskey/phoenix_select);
clearing the selection clears the filter, and multiselect values filter with
`field IN (...)`. Remember the one-time hook registration from the
installation section.

Prefer your own markup? Build filter UIs in the parent with
`Slab.filter_path/3`, which sets the param and resets pagination. For
anything beyond per-field filters, scope the `schema` query itself — the
escape hatch always works.

### Pagination

Pass `paginate` with one of two modes.

`:page` is classic offset pagination driven by `page` and `per_page` URL
params. It works in both data modes — in list mode the list is sliced in
memory. The `per_page` attribute sets the default page size; a `per_page`
URL param can override it but is clamped to `max_per_page` (default 100), so
a crafted URL can't request unbounded rows:

```heex
<Slab.table id="users-table" schema={MyApp.User} repo={MyApp.Repo}
  paginate={:page} per_page={25} uri={@uri} params={@params}>
  <:col field={:name} />
</Slab.table>
```

`:cursor` is keyset pagination driven by an `after` URL param — built for
constantly-updated data, where new inserts shift offset pages underneath the
viewer. Cursors paginate relative to the last-seen record, stay correct as
records land, avoid deep-offset scans, and need no count query. Query mode
only; navigation is First/Next (no random page access):

```heex
<Slab.table id="users-table" schema={MyApp.User} repo={MyApp.Repo}
  paginate={:cursor} per_page={25} uri={@uri} params={@params}>
  <:col field={:inserted_at} sortable />
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
prev/next chevrons, and a page-size dropdown (`per_page_options`, default
`[10, 25, 50, 100]`). The total comes from a count query cached on the
current filters — page and sort changes never re-count, only filter changes
do. Cursor mode never runs a count query at all; both modes detect a next
page by fetching one extra record.

### Tabs and sharing

A tab bar above the table is derived automatically from the table
definition — nothing to declare:

- a **Filters** tab appears when any `<:col>` is `filterable`, containing
  one input per filterable column and a badge with the active filter count.
  Input types derive from the schema — booleans and `Ecto.Enum` fields get
  a select with derived options, everything else a text input — and the
  col's `filter_type`, `filter_options`, `filter_placeholder`, and
  `filter_min_chars` attrs override the defaults:

  ```heex
  <:col field={:role} filterable filter_type="multiselect" />
  <:col field={:name} filterable filter_placeholder="Search names..." filter_min_chars={2} />
  ```

- a **Columns** tab appears when `columns_tab?` is set and `uri` is given
  (see the next section)

- a **Share** tab appears when `share_tab?` is set and `uri` is given,
  holding a read-only copy of the current URL with a copy-to-clipboard
  button — meaningful because *all* table state lives in the URL

No qualifying tabs, no tab bar. The building blocks stay public for custom
layouts outside the table: `Slab.tabs/1` (client-side tabs with icons and
count badges), `Slab.share/1`, and `Slab.filter/1`, plus the badge helpers
`Slab.get_filter_count/1` and `Slab.Helpers.URI.get_query_param_count/1`.

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
<Slab.table id="users-table" ... columns_tab?>
  <:col field={:name} />
  <:col field={:email} optional />
</Slab.table>
```

The Columns tab renders a multi-select picker driving the param; its
selection order becomes the column order. Changing columns never resets
pagination, and sorting/filtering are unaffected by visibility — a hidden
column's filter still applies.

### Row selection

Track the current URI in `handle_params/3` (as above) and pass it along with
`checkable?`:

```heex
<Slab.table id="users-table" data={@users} checkable? uri={@uri}>
  <:col field={:name} />
  <:col field={:email} />
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
| `uri` | `nil` | `uri={@uri}` | Current request URI from `handle_params/3`; enables sorting, selection, pagination |
| `params` | `%{}` | `params={@params}` | Current request params from `handle_params/3`; carries sort/page/filter state |
| `checkable?` | `false` | `checkable?` | Row-selection checkboxes; requires `uri` |
| `paginate` | `nil` | `paginate={:page}` | `:page` (offset, both modes) or `:cursor` (keyset, query mode only); requires `uri` |
| `per_page` | `25` | `per_page={50}` | Default page size |
| `max_per_page` | `100` | `max_per_page={200}` | Upper clamp for the URL `per_page` param, so a crafted URL can't request unbounded rows |
| `per_page_options` | `[10, 25, 50, 100]` | `per_page_options={[25, 100]}` | Page sizes offered in the footer dropdown (page mode) |
| `share_tab?` | `false` | `share_tab?` | Shows the Share tab above the table when `uri` is present |
| `columns_tab?` | `false` | `columns_tab?` | Shows the Columns tab, letting users toggle and reorder columns via `columns[]` |

### `<:col>` slot attributes

| Attribute | Default | Example | Description |
| --- | --- | --- | --- |
| `field` | `nil` | `field={:name}` | Record field to render; optional for virtual columns with a body |
| `label` | humanized field | `label="Full Name"` | Column header text |
| `sortable` | `false` | `sortable` | Header becomes a sort patch link; whitelists the field for `ORDER BY` in query mode |
| `filterable` | `false` | `filterable` | Whitelists the field for `filter[...]` URL params in query mode and adds an input to the Filters tab |
| `filter_query` | `nil` | `filter_query={&by_org/2}` | Custom 2-arity `(queryable, value) -> queryable` filter; implies `filterable`, may join associations |
| `filter_type` | derived | `filter_type="multiselect"` | Filters tab input type (`"text"`, `"select"`, `"multiselect"`); defaults by schema type — booleans and `Ecto.Enum` get a select |
| `filter_options` | derived | `filter_options={[{"Admin", "admin"}]}` | Options for select/multiselect inputs; derived automatically for booleans and `Ecto.Enum` fields |
| `filter_placeholder` | `nil` | `filter_placeholder="Search..."` | Placeholder for the Filters tab input |
| `filter_min_chars` | `0` | `filter_min_chars={3}` | Minimum characters before a text filter change applies |
| `optional` | `false` | `optional` | Starts the column hidden until enabled via the Columns tab or `columns[]` param |

Columns with a body receive the record via `:let`:

```heex
<:col :let={user} field={:name}>{String.upcase(user.name)}</:col>
```

### `Slab.filter/1` attributes

| Attribute | Default | Example | Description |
| --- | --- | --- | --- |
| `id` | required | `id="filter-name"` | Unique component id |
| `field` | required | `field={:name}` | Filter key; matches a `<:col filterable>` field |
| `uri` | required | `uri={@uri}` | Current request URI from `handle_params/3` |
| `params` | `%{}` | `params={@params}` | Current request params; carries the input's current value |
| `type` | `"text"` | `type="multiselect"` | `"text"`, `"select"`, or `"multiselect"` |
| `label` | `nil` | `label="Status"` | Label rendered above the input |
| `placeholder` | `nil` | `placeholder="Search..."` | Placeholder for the input |
| `options` | `[]` | `options={[{"Active", "true"}]}` | Select options, as `[{label, value}]` tuples or plain values |
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

## Testing

```
mix test
```

## License

MIT — see [LICENSE.md](LICENSE.md).
