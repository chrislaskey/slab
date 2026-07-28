defmodule Slab.Components do
  @moduledoc """
  Function components used internally by `Slab`.

  These are public so applications can reuse the same table primitives for
  hand-rolled tables that need to match the `Slab` look.
  """

  use Phoenix.Component

  @doc """
  Renders a `<table>` element wrapped in a horizontally-scrollable container.

  ## Slots

    * `:thead` - optional table header content
    * `:inner_block` - table body rows
  """
  slot(:thead)
  slot(:inner_block, required: true)

  @spec table(map()) :: Phoenix.LiveView.Rendered.t()
  def table(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <table class="w-full">
        <%= if assigns[:thead] != [] do %>
          {render_slot(@thead)}
        <% end %>
        <tbody>
          {render_slot(@inner_block)}
        </tbody>
      </table>
    </div>
    """
  end

  @doc """
  Renders a `<tr>` element.
  """
  slot(:inner_block, required: true)

  @spec tr(map()) :: Phoenix.LiveView.Rendered.t()
  def tr(assigns) do
    ~H"""
    <tr>
      {render_slot(@inner_block)}
    </tr>
    """
  end

  @doc """
  Renders a `<th>` element.
  """
  slot(:inner_block, required: true)

  @spec th(map()) :: Phoenix.LiveView.Rendered.t()
  def th(assigns) do
    ~H"""
    <th class="pb-3 text-left text-bold">
      {render_slot(@inner_block)}
    </th>
    """
  end

  @doc """
  Renders a `<td>` element.
  """
  slot(:inner_block, required: true)

  @spec td(map()) :: Phoenix.LiveView.Rendered.t()
  def td(assigns) do
    ~H"""
    <td class="pt-1 pb-2.5 align-top">
      {render_slot(@inner_block)}
    </td>
    """
  end

  @doc """
  Renders a styled checkbox input.
  """
  attr(:name, :string, required: true)
  attr(:checked, :boolean, default: false)
  attr(:rest, :global)

  @spec checkbox(map()) :: Phoenix.LiveView.Rendered.t()
  def checkbox(assigns) do
    ~H"""
    <input
      type="checkbox"
      name={@name}
      value="true"
      checked={@checked}
      class={[
        "rounded size-5 border-gray-600 text-blue-900 hover:border-blue-900",
        "checked:border-blue-900 checked:bg-blue-900",
        "disabled:cursor-default disabled:border-gray-400 disabled:bg-gray-400",
        "focus:outline-none focus:ring-1 focus:ring-blue-900"
      ]}
      {@rest}
    />
    """
  end

  @doc """
  Renders a scrollable `<pre><code>` block for large values like maps.
  """
  attr(:value, :any, required: true)

  @spec codeblock(map()) :: Phoenix.LiveView.Rendered.t()
  def codeblock(assigns) do
    ~H"""
    <pre class="text-sm overflow-y-scroll" style="max-height: 16rem;"><code>{inspect(@value, pretty: true, limit: :infinity, printable_limit: :infinity)}</code></pre>
    """
  end

  @doc """
  Renders one of the SVG icons used by the data table.

  ## Supported types

    * `"check-circle-outline"`
    * `"x-circle-outline"`
    * `"chevron-up-outline"`
    * `"chevron-down-outline"`
    * `"chevron-left-outline"`
    * `"chevron-right-outline"`
    * `"funnel-outline"`
    * `"bookmark-outline"`
    * `"clipboard-outline"`
    * `"view-columns-outline"`
  """
  attr(:type, :string, required: true)
  attr(:class, :any, default: "h-6 w-6 flex-shrink-0 text-gray-400")

  @spec icon(map()) :: Phoenix.LiveView.Rendered.t()
  def icon(assigns) do
    ~H"""
    {render_icon(@type, %{class: @class})}
    """
  end

  defp render_icon("check-circle-outline", assigns) do
    ~H"""
    <svg
      class={assigns.class}
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
      stroke="currentColor"
      stroke-width="2"
    >
      <path stroke-linecap="round" stroke-linejoin="round" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
    </svg>
    """
  end

  defp render_icon("x-circle-outline", assigns) do
    ~H"""
    <svg
      class={assigns.class}
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
      stroke="currentColor"
      stroke-width="2"
    >
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z"
      />
    </svg>
    """
  end

  defp render_icon("chevron-up-outline", assigns) do
    ~H"""
    <svg
      class={assigns.class}
      viewBox="0 0 24 24"
      fill="none"
      stroke-width="1.5"
      stroke="currentColor"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path stroke-linecap="round" stroke-linejoin="round" d="M4.5 15.75l7.5-7.5 7.5 7.5" />
    </svg>
    """
  end

  defp render_icon("chevron-down-outline", assigns) do
    ~H"""
    <svg
      class={assigns.class}
      viewBox="0 0 24 24"
      fill="none"
      stroke-width="1.5"
      stroke="currentColor"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path stroke-linecap="round" stroke-linejoin="round" d="M19.5 8.25l-7.5 7.5-7.5-7.5" />
    </svg>
    """
  end

  defp render_icon("chevron-left-outline", assigns) do
    ~H"""
    <svg
      class={assigns.class}
      viewBox="0 0 24 24"
      fill="none"
      stroke-width="1.5"
      stroke="currentColor"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path stroke-linecap="round" stroke-linejoin="round" d="M15.75 19.5L8.25 12l7.5-7.5" />
    </svg>
    """
  end

  defp render_icon("chevron-right-outline", assigns) do
    ~H"""
    <svg
      class={assigns.class}
      viewBox="0 0 24 24"
      fill="none"
      stroke-width="1.5"
      stroke="currentColor"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path stroke-linecap="round" stroke-linejoin="round" d="M8.25 4.5l7.5 7.5-7.5 7.5" />
    </svg>
    """
  end

  defp render_icon("funnel-outline", assigns) do
    ~H"""
    <svg
      class={assigns.class}
      viewBox="0 0 24 24"
      fill="none"
      stroke-width="1.5"
      stroke="currentColor"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="M12 3c2.755 0 5.455.232 8.083.678.533.09.917.556.917 1.096v1.044a2.25 2.25 0 01-.659 1.591l-5.432 5.432a2.25 2.25 0 00-.659 1.591v2.927a2.25 2.25 0 01-1.244 2.013L9.75 21v-6.568a2.25 2.25 0 00-.659-1.591L3.659 7.409A2.25 2.25 0 013 5.818V4.774c0-.54.384-1.006.917-1.096A48.32 48.32 0 0112 3z"
      />
    </svg>
    """
  end

  defp render_icon("bookmark-outline", assigns) do
    ~H"""
    <svg
      class={assigns.class}
      viewBox="0 0 24 24"
      fill="none"
      stroke-width="1.5"
      stroke="currentColor"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="M17.593 3.322c1.1.128 1.907 1.077 1.907 2.185V21L12 17.25 4.5 21V5.507c0-1.108.806-2.057 1.907-2.185a48.507 48.507 0 0111.186 0z"
      />
    </svg>
    """
  end

  defp render_icon("view-columns-outline", assigns) do
    ~H"""
    <svg
      class={assigns.class}
      viewBox="0 0 24 24"
      fill="none"
      stroke-width="1.5"
      stroke="currentColor"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="M9 4.5v15m6-15v15m-10.875 0h15.75c.621 0 1.125-.504 1.125-1.125V5.625c0-.621-.504-1.125-1.125-1.125H4.125C3.504 4.5 3 5.004 3 5.625v12.75c0 .621.504 1.125 1.125 1.125z"
      />
    </svg>
    """
  end

  defp render_icon("clipboard-outline", assigns) do
    ~H"""
    <svg
      class={assigns.class}
      viewBox="0 0 24 24"
      fill="none"
      stroke-width="1.5"
      stroke="currentColor"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="M15.666 3.888A2.25 2.25 0 0013.5 2.25h-3c-1.03 0-1.9.693-2.166 1.638m7.332 0c.055.194.084.4.084.612v0a.75.75 0 01-.75.75H9a.75.75 0 01-.75-.75v0c0-.212.03-.418.084-.612m7.332 0c.646.049 1.288.11 1.927.184 1.1.128 1.907 1.077 1.907 2.185V19.5a2.25 2.25 0 01-2.25 2.25H6.75A2.25 2.25 0 014.5 19.5V6.257c0-1.108.806-2.057 1.907-2.185a48.208 48.208 0 011.927-.184"
      />
    </svg>
    """
  end
end
