defmodule Slab.Helpers.URI do
  @moduledoc """
  Helpers for reading and writing URL query parameters.

  `Slab` stores UI state — checked rows, visible columns — in the URL
  query string so that table state survives navigation, refreshes, and can be
  shared as a link. These helpers manipulate query params on a URI string and
  return paths suitable for `Phoenix.LiveView.push_patch/2`.

  Keys support single-level bracket notation (e.g. `"filter[status]"`), which
  encodes to nested query params.
  """

  alias Plug.Conn.Query

  @doc """
  Returns the decoded value of a query param, or `nil` when absent.

  Array params (`checked[]=1&checked[]=2`) decode to lists, bracket params
  decode to maps.

  ## Examples

      iex> Slab.Helpers.URI.get_query_param("/users?sort=name", "sort")
      "name"

      iex> Slab.Helpers.URI.get_query_param("/users?checked[]=1&checked[]=2", "checked")
      ["1", "2"]

      iex> Slab.Helpers.URI.get_query_param("/users", "sort")
      nil
  """
  @spec get_query_param(String.t(), String.t()) :: String.t() | list() | map() | nil
  def get_query_param(uri, key) do
    uri
    |> URI.parse()
    |> Map.get(:query)
    |> Kernel.||("")
    |> Query.decode()
    |> Map.get(key)
  end

  @doc """
  Returns the number of query params on a URI, counting nested params
  recursively.

  Useful as the `count` badge on a share tab — it reflects how much state
  the shareable URL carries.

  ## Examples

      iex> Slab.Helpers.URI.get_query_param_count("/users?sort=name&filter[role]=admin")
      2

      iex> Slab.Helpers.URI.get_query_param_count("/users")
      0
  """
  @spec get_query_param_count(String.t() | nil) :: non_neg_integer()
  def get_query_param_count(uri) when is_bitstring(uri) do
    uri
    |> URI.parse()
    |> Map.get(:query)
    |> Kernel.||("")
    |> Query.decode()
    |> recursive_count()
  end

  def get_query_param_count(_uri), do: 0

  defp recursive_count(%{} = map) do
    Enum.reduce(map, 0, fn
      {_key, %{} = value}, acc -> acc + recursive_count(value)
      {_key, _value}, acc -> acc + 1
    end)
  end

  @doc """
  Sets a query param on the given URI string, replacing any existing value.

  ## Examples

      iex> Slab.Helpers.URI.create_or_update_query_param("/users", "sort", "name")
      "/users?sort=name"

      iex> Slab.Helpers.URI.create_or_update_query_param("/users?sort=name", "sort", "email")
      "/users?sort=email"
  """
  @spec create_or_update_query_param(String.t(), String.t() | atom(), any()) :: String.t()
  def create_or_update_query_param(uri, key, value) do
    current_uri = URI.parse(uri)
    key_path = parse_bracket_key(key)

    updated_query_params =
      current_uri
      |> Map.get(:query)
      |> Kernel.||("")
      |> Query.decode()
      |> deep_put(key_path, value)
      |> Query.encode()

    current_uri
    |> Map.put(:query, updated_query_params)
    |> URI.to_string()
  end

  @doc """
  Removes a query param from the given URI string.

  ## Examples

      iex> Slab.Helpers.URI.delete_query_param("/users?sort=name&page=2", "sort")
      "/users?page=2"

      iex> Slab.Helpers.URI.delete_query_param("/users?sort=name", "sort")
      "/users"
  """
  @spec delete_query_param(String.t(), String.t() | atom()) :: String.t()
  def delete_query_param(uri, key) do
    current_uri = URI.parse(uri)
    key_path = parse_bracket_key(key)

    updated_query_params =
      current_uri
      |> Map.get(:query)
      |> Kernel.||("")
      |> Query.decode()
      |> deep_delete(key_path)
      |> Query.encode()

    current_uri
    |> Map.put(:query, updated_query_params)
    |> URI.to_string()
    |> String.trim_trailing("?")
  end

  @doc """
  Sets a query param, or removes it when the value is `nil`, `""`, or `[]`.
  """
  @spec create_or_update_or_delete_query_param(String.t(), String.t() | atom(), any()) ::
          String.t()
  def create_or_update_or_delete_query_param(uri, key, value) when value in [nil, "", []] do
    delete_query_param(uri, key)
  end

  def create_or_update_or_delete_query_param(uri, key, value) do
    create_or_update_query_param(uri, key, value)
  end

  @doc """
  Returns the path, query, and fragment of a URI as a single string, stripping
  scheme and host. Suitable for `push_patch/2`.

  ## Examples

      iex> Slab.Helpers.URI.extract_full_path("https://example.com/users?sort=name#top")
      "/users?sort=name#top"
  """
  @spec extract_full_path(String.t()) :: String.t()
  def extract_full_path(value) do
    parsed_uri = URI.parse(value)

    simplified_uri = %URI{
      path: parsed_uri.path,
      query: parsed_uri.query,
      fragment: parsed_uri.fragment
    }

    full_path_string = URI.to_string(simplified_uri)
    trimmed_full_path = String.trim_leading(full_path_string, "/")

    "/#{trimmed_full_path}"
  end

  @doc """
  Returns the path and query string of a URI as a single string.

  ## Examples

      iex> Slab.Helpers.URI.query_path("https://example.com/users?sort=name")
      "/users?sort=name"

      iex> Slab.Helpers.URI.query_path("https://example.com/users")
      "/users"
  """
  @spec query_path(String.t()) :: String.t()
  def query_path(value) when is_bitstring(value) do
    parsed = URI.parse(value)

    if parsed.query do
      "#{parsed.path}?#{parsed.query}"
    else
      parsed.path
    end
  end

  # Parses a bracket-notation key like "filter[status]" into a list of access
  # keys ["filter", "status"]. Simple keys return a single-element list.
  @spec parse_bracket_key(String.t() | atom()) :: [String.t() | atom()]
  defp parse_bracket_key(key) when is_atom(key), do: [key]

  defp parse_bracket_key(key) when is_binary(key) do
    case Regex.run(~r/^([^\[]+)\[([^\]]+)\]$/, key) do
      [_, parent, child] -> [parent, child]
      _ -> [key]
    end
  end

  @spec deep_put(map(), [String.t() | atom()], any()) :: map()
  defp deep_put(params, [key], value) do
    Map.put(params, key, value)
  end

  defp deep_put(params, [parent | rest], value) do
    child = Map.get(params, parent, %{})
    child = if is_map(child), do: child, else: %{}
    Map.put(params, parent, deep_put(child, rest, value))
  end

  # Deletes a nested key. If that leaves the parent map empty, the parent key
  # is removed as well.
  @spec deep_delete(map(), [String.t() | atom()]) :: map()
  defp deep_delete(params, [key]) do
    Map.delete(params, key)
  end

  defp deep_delete(params, [parent | rest]) do
    case Map.get(params, parent) do
      child_map when is_map(child_map) ->
        updated = deep_delete(child_map, rest)

        if map_size(updated) == 0 do
          Map.delete(params, parent)
        else
          Map.put(params, parent, updated)
        end

      _ ->
        params
    end
  end
end
