defmodule Slab.Helpers.Params do
  @moduledoc """
  Parsing helpers for pagination-related URL params.

  URL params are user input — these helpers normalize them into safe values,
  falling back to defaults rather than raising on tampered or malformed input.
  """

  @doc """
  Returns the current page from params, defaulting to 1.

  ## Examples

      iex> Slab.Helpers.Params.page(%{"page" => "3"})
      3

      iex> Slab.Helpers.Params.page(%{"page" => "-1"})
      1

      iex> Slab.Helpers.Params.page(%{})
      1
  """
  def page(params), do: positive_int(Map.get(params, "page"), 1)

  @doc """
  Returns the page size from params, defaulting to `default` and clamped
  to `max`.

  ## Examples

      iex> Slab.Helpers.Params.per_page(%{"per_page" => "50"}, 25, 100)
      50

      iex> Slab.Helpers.Params.per_page(%{"per_page" => "9999"}, 25, 100)
      100

      iex> Slab.Helpers.Params.per_page(%{}, 25, 100)
      25
  """
  def per_page(params, default, max) do
    params
    |> Map.get("per_page")
    |> positive_int(default)
    |> min(max)
  end

  @doc """
  Parses a positive integer from a param value, falling back to `default`
  for anything invalid.
  """
  def positive_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int >= 1 -> int
      _ -> default
    end
  end

  def positive_int(value, _default) when is_integer(value) and value >= 1, do: value
  def positive_int(_value, default), do: default
end
