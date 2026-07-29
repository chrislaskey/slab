defmodule DemoWeb.FeedLive do
  @moduledoc """
  Query mode with cursor (keyset) pagination: built for constantly-updated
  data. The `after` URL param carries a readable cursor — the last-seen
  record's id plus its sort value — so new inserts never shift pages
  underneath the viewer.
  """

  use DemoWeb, :live_view

  @impl true
  def handle_params(params, uri, socket) do
    socket =
      socket
      |> assign(:uri, uri)
      |> assign(:params, params)

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto max-w-5xl space-y-6">
        <nav class="flex gap-x-4 text-sm">
          <.link navigate={~p"/"} class="text-cyan-600 hover:underline">
            Users (page pagination)
          </.link>
          <span class="font-semibold">Feed (cursor pagination)</span>
        </nav>

        <h1 class="text-xl font-semibold">Feed</h1>

        <p class="text-sm text-gray-600 max-w-2xl">
          Cursor pagination pages relative to the last-seen record instead of an
          offset. Sort by "Inserted At" and watch the <code>after</code> param
          carry the cursor. Insert new users in another tab — existing pages
          stay stable.
        </p>

        <Slab.table
          id="feed"
          schema={Demo.Accounts.User}
          uri={@uri}
          params={@params}
          paginate={:cursor}
          per_page={10}
          export_tab?
          export_limit={100}
        >
          <:col field={:id} />
          <:col field={:name} />
          <:col field={:role} />
          <:col field={:inserted_at} sortable />
        </Slab.table>
      </div>
    </Layouts.app>
    """
  end
end
