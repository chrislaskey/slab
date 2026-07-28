defmodule Slab.Helpers.RelativeTimeTest do
  use ExUnit.Case, async: true

  alias Slab.Helpers.RelativeTime

  doctest Slab.Helpers.RelativeTime

  @now ~U[2026-01-01 12:00:00Z]

  test "seconds, minutes, hours, days, months, years" do
    assert RelativeTime.format(~U[2026-01-01 11:59:15Z], @now) == "45 seconds ago"
    assert RelativeTime.format(~U[2026-01-01 11:59:00Z], @now) == "1 minute ago"
    assert RelativeTime.format(~U[2026-01-01 11:00:00Z], @now) == "1 hour ago"
    assert RelativeTime.format(~U[2025-12-30 12:00:00Z], @now) == "2 days ago"
    assert RelativeTime.format(~U[2025-10-01 12:00:00Z], @now) == "3 months ago"
    assert RelativeTime.format(~U[2024-01-01 12:00:00Z], @now) == "2 years ago"
  end

  test "future times" do
    assert RelativeTime.format(~U[2026-01-01 13:00:00Z], @now) == "in 1 hour"
  end

  test "naive datetimes are treated as UTC" do
    assert RelativeTime.format(~N[2026-01-01 11:00:00], @now) == "1 hour ago"
  end
end
