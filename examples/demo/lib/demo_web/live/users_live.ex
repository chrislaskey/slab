defmodule DemoWeb.UsersLive do
  @moduledoc """
  Query mode with page pagination: Slab fetches from the repo (configured
  via `config :slab, repo: Demo.Repo`), applying URL-driven sorting,
  filtering, and pagination. The LiveView only tracks `uri` and `params`.
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
          <span class="font-semibold">Users (page pagination)</span>
          <.link navigate={~p"/feed"} class="text-cyan-600 hover:underline">
            Feed (cursor pagination)
          </.link>
        </nav>

        <h1 class="text-xl font-semibold">Users</h1>

        <Slab.table
          id="users"
          schema={Demo.Accounts.User}
          uri={@uri}
          params={@params}
          checkable?
          paginate={:page}
          per_page={10}
          columns_tab?
          share_tab?
        >
          <:col field={:id} sortable />
          <:col
            field={:name}
            sortable
            filterable
            filter_placeholder="Search names..."
            filter_min_chars={2}
          />
          <:col field={:email} filterable optional />
          <:col field={:role} sortable filterable filter_type="multiselect" />
          <:col field={:active} filterable />
          <:col field={:inserted_at} sortable />
          <:col field={:updated_at} optional />
          <:col :let={user} label="Actions">
            <span class="text-cyan-600">Edit {user.name}</span>
          </:col>
        </Slab.table>

        <p :if={Slab.checked?(@params)} class="text-sm text-gray-600">
          {Slab.get_checked_count(@params)} selected
        </p>
      </div>
    </Layouts.app>
    """
  end
end
