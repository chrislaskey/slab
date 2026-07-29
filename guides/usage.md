# Usage

## Architecture

A table is composed from Phoenix Component slots — every region is declared by the
presence of a slot, and nothing renders that wasn't declared. Common slots include:

- **`<:column>`** — automatic table rendering based on Ecto schema field types
  with support for custom rendering.
- **`<:column_checkbox>`** — checkbox row selection.
- **`<:pagination>`** — supports either offset or keyset pagination.
- **`<:tab>`** — a tab bar above the table: Filters, Columns, Share, Export,
  or fully custom tabs, in declaration order.
- **`<:filter>`** — declarative, whitelisted filtering driven by `filter[...]`
  URL params, with ready-made inputs.

Supports automatic database querying (including sorting and filtering) or simply
render data passed in as a list.

Table state lives in query params in the URL, persisting views across reloads
and making it easy to share.

Supports custom rendering of fields, inline editing, sorting, pagination, 
filtering, dynamic column ordering.

## Overview

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

## Automatic type-based rendering

Pass a `schema` (an `Ecto.Schema` module) and cells render according to each
field's type. Without a schema, values render as plain strings. In query
mode the schema is already known, so typed rendering is automatic.

## Custom cell rendering

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

## Sorting

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

## Filtering

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

## Filter inputs

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

## External filter UI

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

## Pagination

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

## Tabs

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

## Exporting

The Export tab downloads the table as CSV, generated server-side and
delivered through the browser — no routes or setup beyond registering
Slab's hooks (see the [README](../README.md#javascript-hooks)). It offers two
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

## Column visibility and order

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

## Row selection

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

## Inline editing

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
