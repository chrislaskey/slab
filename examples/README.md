# Slab demo app

A full Phoenix application demonstrating Slab against a seeded SQLite
database — no external services required.

## Running it

```
cd examples/demo
mix setup
mix phx.server
```

Then open [http://localhost:4000](http://localhost:4000):

- `/` — query mode with page pagination: sortable headers, text and select
  filters, row selection
- `/feed` — cursor (keyset) pagination for constantly-updated data

## Layout

- `demo/` — the generated app. The interesting files are:
  - `lib/demo_web/live/users_live.ex` and `feed_live.ex` — each is ~30 lines
    of real logic: track `uri` and `params` in `handle_params/3`, render
    `<Slab.table>` / `<Slab.filter>`
  - `config/config.exs` — the `config :slab, repo: Demo.Repo` line
  - `assets/css/app.css` — the Tailwind `@source` line (pointing at Slab's
    source directly, since the demo uses a path dependency; Hex-installed
    apps use `../../deps/slab/lib`)
- `overlay/` — the Slab-specific demo code, copied over the generated
  skeleton by the regenerate script
- `regenerate.sh` — regenerates `demo/` from scratch with a pinned
  `phx.new` version, reapplies the edits and overlay, and sets up the
  database. Run it whenever the skeleton drifts out of date.

## Distribution note

None of this ships to library users installing from Hex — the package
includes only the files whitelisted in `mix.exs` (`lib`, `mix.exs`,
`README.md`, `LICENSE.md`). Git dependencies clone the repo including this
directory, but it is a few hundred KB of text and is never compiled as part
of the dependency.
