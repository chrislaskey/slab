defmodule Slab.Helpers.RelativeTime do
  @moduledoc """
  Formats a datetime relative to now, e.g. `"3 hours ago"` or `"in 2 days"`.

  A dependency-free replacement for Timex's `{relative}` formatting, covering
  the ranges a data table typically displays.
  """

  @minute 60
  @hour 3600
  @day 86_400
  @month 2_629_746
  @year 31_556_952

  @doc """
  Returns a human-readable relative time string.

  Accepts a `DateTime` or a `NaiveDateTime` (assumed UTC). An optional second
  argument fixes the reference "now", which is useful in tests.

  ## Examples

      iex> now = ~U[2026-01-01 12:00:00Z]
      iex> Slab.Helpers.RelativeTime.format(~U[2026-01-01 09:00:00Z], now)
      "3 hours ago"

      iex> now = ~U[2026-01-01 12:00:00Z]
      iex> Slab.Helpers.RelativeTime.format(~U[2026-01-03 12:00:00Z], now)
      "in 2 days"

      iex> now = ~U[2026-01-01 12:00:00Z]
      iex> Slab.Helpers.RelativeTime.format(~U[2026-01-01 11:59:58Z], now)
      "just now"
  """
  @spec format(DateTime.t() | NaiveDateTime.t(), DateTime.t()) :: String.t()
  def format(value, now \\ DateTime.utc_now())

  def format(%NaiveDateTime{} = value, now) do
    value
    |> DateTime.from_naive!("Etc/UTC")
    |> format(now)
  end

  def format(%DateTime{} = value, now) do
    seconds = DateTime.diff(now, value)

    cond do
      abs(seconds) < 30 -> "just now"
      seconds > 0 -> "#{humanize(seconds)} ago"
      true -> "in #{humanize(-seconds)}"
    end
  end

  defp humanize(seconds) when seconds < @minute, do: pluralize(seconds, "second")
  defp humanize(seconds) when seconds < @hour, do: pluralize(div(seconds, @minute), "minute")
  defp humanize(seconds) when seconds < @day, do: pluralize(div(seconds, @hour), "hour")
  defp humanize(seconds) when seconds < @month, do: pluralize(div(seconds, @day), "day")
  defp humanize(seconds) when seconds < @year, do: pluralize(div(seconds, @month), "month")
  defp humanize(seconds), do: pluralize(div(seconds, @year), "year")

  defp pluralize(1, unit), do: "1 #{unit}"
  defp pluralize(count, unit), do: "#{count} #{unit}s"
end
