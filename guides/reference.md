# Reference


Full documentation for every attribute, with types and defaults, is generated
from the component declarations — run `mix docs` or see the `Slab` module on
HexDocs. The tables below are the quick version.

## `Slab.table/1` attributes

| Attribute | Default | Example | Description |
| --- | --- | --- | --- |
| `id` | required | `id="users-table"` | Unique component id |
| `data` | `nil` | `data={@users}` | Pre-fetched records (list mode); omit for query mode |
| `schema` | `nil` | `schema={MyApp.User}` | `Ecto.Schema` module for field reflection (typed rendering, filter inputs, casting); the default query-mode source |
| `query` | `nil` | `query={@scoped_query}` | `Ecto.Query` used as the base of every fetch instead of the schema — scoping, joins, computed fields |
| `preload` | `nil` | `preload={[:products]}` | Associations to preload on fetched records, in any `Ecto.Query.preload/3` shape |
| `repo` | `nil` | `repo={MyApp.Repo}` | Repo for query mode; falls back to `config :slab, repo: MyApp.Repo` |
| `uri` | `nil` | `uri={@uri}` | Current request URI from `handle_params/3`; required by URL-driven slots |
| `params` | `%{}` | `params={@params}` | Current request params from `handle_params/3`; carries sort/page/filter/column/selection state |
| `on_save` | `nil` | `on_save={&save_user/2}` | 2-arity `(record, changed_params) -> {:ok, record} \| {:error, error}` called on row save; required when any column is `editable` |

## `<:column>` slot attributes

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

## `<:column_checkbox>` slot

Row-selection checkboxes, always the first column and always visible. At
most one; requires `uri`. No attributes.

## `<:filter>` slot attributes

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

## `<:tab>` slot attributes

| Attribute | Default | Example | Description |
| --- | --- | --- | --- |
| `name` | required | `name="filters"` | `"filters"`, `"columns"`, `"share"`, `"export"`, or a custom tab's identity |
| `label` | derived | `label="Help"` | Tab label; derived for built-in names, required for custom tabs |
| `icon` | derived | `icon="bookmark-outline"` | Icon before the label; see `Slab.Components.icon/1` |
| `count` | derived | `count={3}` | Badge count for custom tabs; built-in tabs compute their own |
| `limit` | `1000` | `limit={5000}` | Export only: maximum rows in a full-data export |

## `<:pagination>` slot attributes

| Attribute | Default | Example | Description |
| --- | --- | --- | --- |
| `mode` | required | `mode={:page}` | `:page` (offset, both modes) or `:cursor` (keyset, query mode only); requires `uri` |
| `per_page` | `25` | `per_page={50}` | Default page size |
| `max_per_page` | `100` | `max_per_page={200}` | Upper clamp for the URL `per_page` param, so a crafted URL can't request unbounded rows |
| `options` | `[10, 25, 50, 100]` | `options={[25, 100]}` | Page sizes offered in the footer dropdown (page mode) |

## `Slab.filter/1` attributes

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

## `Slab.tabs/1` attributes

| Attribute | Default | Example | Description |
| --- | --- | --- | --- |
| `id` | required | `id="table-tabs"` | Unique DOM id |
| `active` | first tab | `active="Filters"` | Label of the initially active tab |

Each `<:tab>` slot takes `label` (required), `icon` (optional, see
`Slab.Components.icon/1`), and `count` (optional badge, hidden when zero).

## `Slab.share/1` attributes

| Attribute | Default | Example | Description |
| --- | --- | --- | --- |
| `uri` | required | `uri={@uri}` | Current request URI shown in the copyable input |

## URL params

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

## Helper functions

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
