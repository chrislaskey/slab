defmodule DemoWeb.ReadmeLive do
  @moduledoc """
  The README's Examples section, live: each example shows its narrative,
  the exact code being rendered, and the rendered table itself. The code
  matches the README structurally — only the app-specific names differ
  (`Demo.Accounts.User` for `MyApp.User`, `Demo.Repo` for `MyApp.Repo`,
  and unique table ids so the examples can share one page).
  """

  use DemoWeb, :live_view

  import Ecto.Query

  @example_simple ~S"""
  <Slab.table id="readme-simple" data={@users} uri={@uri} params={@params}>
    <:column field={:name} />
    <:column field={:inserted_at} />
  </Slab.table>
  """

  @example_query ~S"""
  <Slab.table id="readme-query" schema={Demo.Accounts.User} repo={Demo.Repo} uri={@uri} params={@params}>
    <:column field={:name} sortable />
    <:column field={:inserted_at} sortable />
    <:pagination mode={:page} per_page={5} />
  </Slab.table>
  """

  @example_tabs ~S"""
  <Slab.table id="readme-tabs" schema={Demo.Accounts.User} repo={Demo.Repo} uri={@uri} params={@params}>
    <:tab name="filters" />
    <:tab name="columns" />
    <:filter field={:name} />
    <:column field={:name} sortable />
    <:column field={:inserted_at} sortable />
    <:pagination mode={:page} per_page={5} />
  </Slab.table>
  """

  @example_full ~S"""
  <Slab.table id="readme-full" schema={Demo.Accounts.User} repo={Demo.Repo} preload={:products} on_save={&save_user/2} uri={@uri} params={@params}>
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

    <:pagination mode={:page} per_page={5} />
  </Slab.table>
  """

  @example_helpers ~S"""
  defp save_user(user, params) do
    user
    |> Demo.Accounts.User.changeset(params)
    |> Demo.Repo.update()
  end

  defp filter_by_organization(query, value) do
    from u in query,
      join: o in assoc(u, :organization),
      where: like(o.name, ^"%#{value}%")
  end

  defp products_export(user) do
    Enum.map_join(user.products, ", ", & &1.name)
  end
  """

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:users, Demo.Repo.all(from(u in Demo.Accounts.User, limit: 5)))
      |> assign(:example_simple, @example_simple)
      |> assign(:example_query, @example_query)
      |> assign(:example_tabs, @example_tabs)
      |> assign(:example_full, @example_full)
      |> assign(:example_helpers, @example_helpers)

    {:ok, socket}
  end

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
          <.link navigate={~p"/users"} class="text-cyan-600 hover:underline">
            Full Example
          </.link>
          <.link navigate={~p"/feed"} class="text-cyan-600 hover:underline">
            Feed Example
          </.link>
          <.link navigate={~p"/edit"} class="text-cyan-600 hover:underline">
            Edit Example
          </.link>
          <span class="font-semibold">Readme Examples</span>
        </nav>

        <h1 class="text-2xl font-semibold">Readme examples</h1>

        <.example code={@example_simple}>
          <:text>
            Slab can render a simple table over records you already have:
          </:text>
          <Slab.table id="readme-simple" data={@users} uri={@uri} params={@params}>
            <:column field={:name} />
            <:column field={:inserted_at} />
          </Slab.table>
        </.example>

        <.example code={@example_query}>
          <:text>
            Or have Slab do the data fetching for you, which gets sorting and
            pagination for free:
          </:text>
          <Slab.table
            id="readme-query"
            schema={Demo.Accounts.User}
            repo={Demo.Repo}
            uri={@uri}
            params={@params}
          >
            <:column field={:name} sortable />
            <:column field={:inserted_at} sortable />
            <:pagination mode={:page} per_page={5} />
          </Slab.table>
        </.example>

        <.example code={@example_tabs}>
          <:text>
            Now add some tabs for filters and custom columns:
          </:text>
          <Slab.table
            id="readme-tabs"
            schema={Demo.Accounts.User}
            repo={Demo.Repo}
            uri={@uri}
            params={@params}
          >
            <:tab name="filters" />
            <:tab name="columns" />
            <:filter field={:name} />
            <:column field={:name} sortable />
            <:column field={:inserted_at} sortable />
            <:pagination mode={:page} per_page={5} />
          </Slab.table>
        </.example>

        <.example code={@example_full}>
          <:text>
            Slab's composition lets you continue to layer in features with
            declarative syntax. Here's an example with many additional
            features - inline editing, row selection, export to CSV, custom
            tabs, custom column rendering, and more:
          </:text>
          <Slab.table
            id="readme-full"
            schema={Demo.Accounts.User}
            repo={Demo.Repo}
            preload={:products}
            on_save={&save_user/2}
            uri={@uri}
            params={@params}
          >
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
              <.link navigate={~p"/users/#{user}/edit"} class="text-cyan-600 hover:underline">
                Edit
              </.link>
            </:column>

            <:pagination mode={:page} per_page={5} />
          </Slab.table>
        </.example>

        <section class="space-y-4 pt-4">
          <p class="text-gray-600">
            The functions referenced above — Slab passes the record and raw
            values, and the LiveView owns the queries and writes:
          </p>
          <.code_block code={@example_helpers} />
        </section>
      </div>
    </Layouts.app>
    """
  end

  attr :code, :string, required: true
  slot :text, required: true
  slot :inner_block, required: true

  defp example(assigns) do
    ~H"""
    <section class="space-y-4 pt-4">
      <p class="text-gray-600">{render_slot(@text)}</p>
      <.code_block code={@code} />
      {render_slot(@inner_block)}
    </section>
    """
  end

  attr :code, :string, required: true

  defp code_block(assigns) do
    ~H"""
    <pre class="p-4 rounded-lg bg-gray-50 border border-gray-200 text-sm text-zinc-700 overflow-x-auto"><code>{String.trim_trailing(@code)}</code></pre>
    """
  end

  defp save_user(user, params) do
    user
    |> Demo.Accounts.User.changeset(params)
    |> Demo.Repo.update()
  end

  defp filter_by_organization(query, value) do
    from u in query,
      join: o in assoc(u, :organization),
      where: like(o.name, ^"%#{value}%")
  end

  defp products_export(user) do
    Enum.map_join(user.products, ", ", & &1.name)
  end
end
