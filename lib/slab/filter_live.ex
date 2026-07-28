defmodule Slab.FilterLive do
  @moduledoc """
  The stateful core of `Slab.filter/1` text inputs.

  This live component is an internal implementation detail — render filter
  inputs with `Slab.filter/1`, which validates attributes at compile time and
  forwards them here. On change it patches the `filter[field]` query param;
  the table (in query mode) and the parent LiveView react through
  `handle_params/3`.

  Select and multiselect filter types are rendered by `PhoenixSelect.select/1`
  in URL mode and never reach this module.
  """

  use Phoenix.LiveComponent

  @impl true
  def update(assigns, socket) do
    value =
      assigns
      |> Map.get(:params, %{})
      |> current_value(Map.get(assigns, :field))

    socket =
      socket
      |> assign(assigns)
      |> assign(:value, value)

    {:ok, socket}
  end

  # The input reflects the URL's current filter value. Operator-map filters
  # (filter[field][gte]=...) are not editable by this simple input and
  # render as empty.
  defp current_value(params, field) do
    case params |> Map.get("filter", %{}) |> get_filter_value(field) do
      value when is_binary(value) -> value
      _operator_map_or_missing -> nil
    end
  end

  defp get_filter_value(filters, field) when is_map(filters),
    do: Map.get(filters, to_string(field))

  defp get_filter_value(_filters, _field), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <form id={"#{@id}-form"} phx-target={@myself} phx-change="change" phx-submit="submit">
        <div class="w-full flex items-center min-h-10 rounded-lg border border-zinc-300 bg-white focus-within:border-cyan-600">
          <input
            id={"#{@id}-input"}
            type="text"
            name="value"
            value={@value}
            placeholder={@placeholder}
            phx-debounce={@debounce}
            class="m-0 py-1 px-4 w-full text-sm border-0 rounded-lg bg-transparent text-zinc-700 placeholder:text-zinc-500 outline-0 focus:ring-0 focus:outline-none"
          />
        </div>
      </form>
    </div>
    """
  end

  @impl true
  def handle_event("change", %{"value" => value}, socket) do
    if apply_change?(value, socket.assigns.min_chars) do
      {:noreply, push_patch(socket, to: filter_to(socket, value))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("submit", %{"value" => value}, socket) do
    {:noreply, push_patch(socket, to: filter_to(socket, value))}
  end

  @doc false
  # Text changes apply once the value is long enough to be a useful query —
  # or empty, which clears the filter. Submit always applies.
  def apply_change?(value, min_chars) when is_binary(value) do
    value == "" or String.length(value) >= min_chars
  end

  def apply_change?(_value, _min_chars), do: true

  defp filter_to(socket, value) do
    Slab.filter_path(socket.assigns.uri, socket.assigns.field, value)
  end
end
