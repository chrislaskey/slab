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

        <Slab.table id="users" schema={Demo.Accounts.User} uri={@uri} params={@params}>
          <:tab name="filters" />
          <:tab name="columns" />
          <:tab name="share" />
          <:tab name="export" />
          <:tab name="help" label="Help" icon="bookmark-outline">
            <p class="text-sm text-gray-600">
              A custom tab — declare any name with a label and a body.
            </p>
          </:tab>

          <:filter field={:name} placeholder="Search names..." min_chars={2} />
          <:filter field={:email} />
          <:filter field={:role} type="multiselect" />
          <:filter field={:active} />

          <:column_checkbox />
          <:column field={:id} sortable />
          <:column field={:name} sortable />
          <:column field={:email} optional />
          <:column field={:role} sortable />
          <:column field={:active} />
          <:column field={:inserted_at} sortable />
          <:column field={:updated_at} optional />
          <:column :let={user} label="Actions">
            <span class="text-cyan-600">Edit {user.name}</span>
          </:column>

          <:pagination mode={:page} per_page={10} />
        </Slab.table>

        <p :if={Slab.checked?(@params)} class="text-sm text-gray-600">
          {Slab.get_checked_count(@params)} selected
        </p>
      </div>
    </Layouts.app>
    """
  end
end
