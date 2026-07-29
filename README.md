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
  blocks), custom bodies, URL-driven sorting, and inline editing.
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

## Examples

Start small: a table over records you already have, with sortable columns —
sorting patches `sort` params onto the URL, and the LiveView requeries in
`handle_params/3`:

```heex
<Slab.table id="users-table" data={@users} uri={@uri} params={@params}>
  <:column field={:name} sortable />
  <:column field={:email} />
  <:column field={:inserted_at} sortable />
</Slab.table>
```

And everything at once — query mode, where Slab fetches through your repo
and the URL drives filtering, sorting, pagination, column layout, selection,
exports, and inline editing:

```heex
<Slab.table id="users-table" schema={MyApp.User} repo={MyApp.Repo}
  uri={@uri} params={@params} on_save={&save_user/2}>
  <:tab name="filters" />
  <:tab name="columns" />
  <:tab name="share" />
  <:tab name="export" limit={5000} />
  <:tab name="help" label="Help" icon="bookmark-outline">
    <p>Contact #data-team for access questions.</p>
  </:tab>

  <:filter field={:name} placeholder="Search names..." min_chars={2} />
  <:filter field={:role} type="multiselect" />
  <:filter field={:organization} query={&filter_by_organization/2} />

  <:column_checkbox />
  <:column field={:name} sortable editable />
  <:column field={:role} sortable />
  <:column field={:email} optional />
  <:column :let={user} label="Products" export_value={&products_export/1}>
    {Enum.map_join(user.products, ", ", & &1.name)}
  </:column>
  <:column :let={user} label="Actions">
    <.link navigate={~p"/users/#{user}/edit"}>Edit</.link>
  </:column>

  <:pagination mode={:page} per_page={25} />
</Slab.table>
```

Every piece is explained feature-by-feature in the [Usage guide](guides/usage.md),
and there is a runnable demo app in `examples/` (see
[Development](guides/development.md)).

## Documentation

- **[Usage](guides/usage.md)** — every feature in depth: data modes, sorting,
  filtering (including external filter UIs), pagination, tabs, exporting,
  column visibility, row selection, and inline editing
- **[Reference](guides/reference.md)** — quick tables for every attribute,
  slot, URL param, and helper function
- **[Development](guides/development.md)** — the demo app, architecture
  notes, testing, and releasing
- **[HexDocs](https://hexdocs.pm/slab)** — generated API documentation,
  including these guides

## License

MIT — see [LICENSE.md](LICENSE.md).
