# Slab

> A composable data table component for Phoenix LiveView.

<p align="center">
  <img title="v1.0.0 Screenshot" src="https://raw.githubusercontent.com/chrislaskey/slab/refs/heads/main/examples/screenshot-v1.0.0.png" width="600">
</p>

## Architecture

Slab is composed from Phoenix Component slots — every region is declared by the
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

## Examples

Slab can render a simple table over records you already have with sortable columns:

```heex
<Slab.table id="users-table" data={@users} uri={@uri} params={@params}>
  <:column field={:name} sortable />
  <:column field={:inserted_at} />
</Slab.table>
```

Or it can render a complex component. On the backend it can query, filter, and
sort results directly from the database. In the UI, all state is stored in
query params in the URL. These drive filtering, sorting, pagination, column
layout, selection, exports, tabs, and inline editing:

```heex
<Slab.table id="users-table" schema={MyApp.User} repo={MyApp.Repo}
  uri={@uri} params={@params} on_save={&save_user/2}>
  <:tab name="filters" />
  <:tab name="columns" />
  <:tab name="share" />
  <:tab name="export" limit={1000} />
  <:tab name="custom" label="Custom">Custom tab content</:tab>

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

## Demo app

The `/examples` directory contains a full Phoenix demo app exercising every
feature — page and cursor pagination, filters, tabs, exports, and inline
editing:

```
git clone https://github.com/chrislaskey/slab.git
cd slab/examples/demo
mix setup && iex -S mix phx.server
```

The demo is generated: `examples/regenerate.sh` rebuilds it from a pinned
`phx.new` release, then applies the version-controlled `examples/overlay/`
directory on top. The interesting demo code — LiveViews, schema, seeds,
layout tweaks — lives in the overlay; edit there, copy over the demo
(`cp -R overlay/. demo/`), and never edit generated files directly.

## Additional documentation

- **[Usage](guides/usage.md)** — every feature in depth: data modes, sorting,
  filtering (including external filter UIs), pagination, tabs, exporting,
  column visibility, row selection, and inline editing
- **[Reference](guides/reference.md)** — quick tables for every attribute,
  slot, URL param, and helper function
- **[Development](guides/development.md)** — the demo app, architecture
  notes, testing, and releasing
- **[HexDocs](https://hexdocs.pm/slab)** — generated API documentation,
  including these guides

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

## License

MIT — see [LICENSE.md](LICENSE.md).
