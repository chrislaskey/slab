# Development

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

## Architecture

`Slab.table/1` is a function component — it declares and validates attributes
and slots at compile time, and is the stable public interface. Internally it
renders `Slab.Live`, a live component that owns interactive state: row
selection, inline edits, and in query mode the data fetching itself —
queries only re-run when their inputs (source, repo, sort, filters,
pagination) actually change, not on every parent re-render. Sorting needs no
events at all: headers are plain patch links built with `Slab.sort_path/3`.

Cross-slot reads are the core of the design: because every slot is a sibling
under one component, the Filters tab reads the `<:filter>` declarations, the
Columns tab and exports read the `<:column>` declarations, and the query
whitelists derive from both — one declaration, consistently enforced.

## Testing

```
mix test
```

The demo app has its own integration tests exercising Slab through a real
LiveView (`cd examples/demo && mix test`).

## Releasing

```
mix test && mix credo
mix docs        # inspect generated docs locally, including these guides
mix hex.publish
```
