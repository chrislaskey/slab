defmodule DemoWeb.EditLive do
  @moduledoc """
  Inline editing: editable columns render their inputs directly — no edit
  mode — and a save column appears at the end. Saving calls this module's
  `save_user/2` with the changed fields; Slab never writes to the database
  itself.
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
          <.link navigate={~p"/feed"} class="text-cyan-600 hover:underline">
            Feed (cursor pagination)
          </.link>
          <span class="font-semibold">Edit (inline editing)</span>
        </nav>

        <h1 class="text-xl font-semibold">Edit Users</h1>

        <p class="text-sm text-gray-600 max-w-2xl">
          Change a value and the row's save button lights up — click it (or
          press Enter) to save. Multiple columns can change before one save.
          Clear a name or break an email to see a changeset error render
          under the row.
        </p>

        <Slab.table
          id="edit-users"
          schema={Demo.Accounts.User}
          uri={@uri}
          params={@params}
          on_save={&save_user/2}
        >
          <:tab name="filters" />
          <:filter field={:name} placeholder="Search names..." />

          <:column field={:id} sortable />
          <:column field={:name} editable />
          <:column field={:email} editable />
          <:column field={:role} editable />
          <:column field={:active} editable />

          <:pagination mode={:page} per_page={10} />
        </Slab.table>
      </div>
    </Layouts.app>
    """
  end

  defp save_user(user, params) do
    user
    |> Demo.Accounts.User.changeset(params)
    |> Demo.Repo.update()
  end
end
