#!/usr/bin/env bash
#
# Regenerates the demo app from scratch:
#
#   1. Generates a fresh Phoenix app with `mix phx.new` (pinned version)
#   2. Applies Slab-specific edits (path dep, routes, Tailwind, repo config)
#   3. Copies the Slab demo code from overlay/ over the skeleton
#   4. Installs deps, creates + migrates + seeds the SQLite database
#
# Run it whenever the generated skeleton drifts out of date:
#
#   ./examples/regenerate.sh
#
# The interesting demo code lives in overlay/ (version controlled); the
# generated skeleton is disposable.

set -euo pipefail
cd "$(dirname "$0")"

PHX_NEW_VERSION="1.8.5"

# 1. Ensure the pinned Phoenix generator
if ! mix phx.new --version 2>/dev/null | grep -q "v${PHX_NEW_VERSION}$"; then
  echo "==> Installing phx_new ${PHX_NEW_VERSION}"
  mix archive.install hex phx_new "${PHX_NEW_VERSION}" --force
fi

# 2. Generate a fresh skeleton
echo "==> Generating demo app (phx.new ${PHX_NEW_VERSION})"
rm -rf demo
mix phx.new demo --module Demo --database sqlite3 --no-mailer --no-dashboard --no-gettext --no-install

# 3. Slab-specific edits to generated files

echo "==> Adding slab as a path dependency"
perl -0777 -pi -e 's/(defp deps do\s*\n\s*\[\n)/$1      {:slab, path: "..\/.."},\n/' demo/mix.exs

echo "==> Replacing the default route with the demo LiveViews"
perl -pi -e 's{get "/", PageController, :home}{live "/", UsersLive\n    live "/feed", FeedLive\n    live "/edit", EditLive}' demo/lib/demo_web/router.ex

# The generated home page test asserts the default Phoenix marketing copy,
# but the route above replaced that page with the Slab demo
rm -f demo/test/demo_web/controllers/page_controller_test.exs

echo "==> Pointing Tailwind at Slab's and PhoenixSelect's classes"
perl -pi -e 's{\@source "\.\./\.\./lib/demo_web";}{$&\n/* Slab is a path dependency here, so point Tailwind at its source directly.\n   Apps installing slab from Hex use "../../deps/slab/lib" instead. */\n\@source "../../../../lib";\n\@source "../../deps/phoenix_select/lib";}' demo/assets/css/app.css

echo "==> Registering Slab's and PhoenixSelect's colocated hooks"
perl -pi -e 's{import \{hooks as colocatedHooks\} from "phoenix-colocated/demo"}{$&\nimport {hooks as slabHooks} from "phoenix-colocated/slab"\nimport {hooks as phoenixSelectHooks} from "phoenix-colocated/phoenix_select"}' demo/assets/js/app.js
perl -pi -e 's{hooks: \{\.\.\.colocatedHooks\},}{hooks: {...colocatedHooks, ...slabHooks, ...phoenixSelectHooks},}' demo/assets/js/app.js

echo "==> Configuring the Slab repo"
perl -0777 -pi -e 's/(# Import environment specific config)/# Slab query mode uses this repo unless one is passed explicitly\nconfig :slab, repo: Demo.Repo\n\n$1/' demo/config/config.exs

# 4. Copy the demo code over the skeleton
echo "==> Applying overlay/"
cp -R overlay/. demo/

# 5. Install, migrate, seed
echo "==> mix setup (deps, database, assets)"
(cd demo && mix setup)

echo
echo "Done. Run the demo with:"
echo
echo "    cd examples/demo && mix phx.server"
echo
echo "then open http://localhost:4000"
