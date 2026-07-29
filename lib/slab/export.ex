defmodule Slab.Export do
  @moduledoc """
  Serializes records to CSV for the Export tab downloads.

  Used internally by `Slab.table/1` when `export_tab?` is set, and public so
  applications can reuse the same serialization — for example in a custom
  export controller streaming more rows than the tab's in-socket downloads
  should carry.
  """

  @doc """
  Renders records as an RFC 4180 CSV binary.

  `columns` is a list of `{header, field}` tuples — one per CSV column, in
  order. Each row reads `field` from the record and formats the value:

    * `nil` renders as an empty field
    * dates and times render as ISO 8601
    * lists render their formatted members joined with `", "`
    * anything else renders with `to_string/1`, falling back to `inspect/1`
      for values without a string representation (like maps)

  Fields containing commas, quotes, or line breaks are quoted with internal
  quotes doubled; rows end with `\\r\\n`.

  ## Examples

      iex> Slab.Export.csv([%{name: "Ada, Countess", active: true}], [{"Name", :name}, {"Active", :active}])
      "Name,Active\\r\\n\\"Ada, Countess\\",true\\r\\n"
  """
  def csv(records, columns) do
    headers = Enum.map(columns, fn {header, _field} -> header end)

    rows =
      for record <- records do
        Enum.map(columns, fn {_header, field} -> format_value(Map.get(record, field)) end)
      end

    IO.iodata_to_binary(Enum.map([headers | rows], &encode_row/1))
  end

  defp encode_row(values) do
    [values |> Enum.map(&escape/1) |> Enum.intersperse(","), "\r\n"]
  end

  defp escape(value) do
    if String.contains?(value, ["\"", ",", "\n", "\r"]) do
      ["\"", String.replace(value, "\"", "\"\""), "\""]
    else
      value
    end
  end

  defp format_value(nil), do: ""
  defp format_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp format_value(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp format_value(%Date{} = value), do: Date.to_iso8601(value)
  defp format_value(%Time{} = value), do: Time.to_iso8601(value)

  defp format_value(value) when is_list(value) do
    Enum.map_join(value, ", ", &format_value/1)
  end

  defp format_value(value) do
    to_string(value)
  rescue
    Protocol.UndefinedError -> inspect(value)
  end
end
