defmodule Slab.ExportTest do
  use ExUnit.Case, async: true

  doctest Slab.Export

  describe "csv/2" do
    test "renders a header row plus one row per record" do
      records = [%{name: "Ada", role: :admin}, %{name: "Grace", role: :member}]

      csv = Slab.Export.csv(records, [{"Name", :name}, {"Role", :role}])

      assert csv == "Name,Role\r\nAda,admin\r\nGrace,member\r\n"
    end

    test "quotes fields containing commas, quotes, or line breaks" do
      records = [%{name: ~s(Ada "the Countess", of Lovelace), note: "line one\nline two"}]

      csv = Slab.Export.csv(records, [{"Name", :name}, {"Note", :note}])

      assert csv ==
               ~s(Name,Note\r\n"Ada ""the Countess"", of Lovelace","line one\nline two"\r\n)
    end

    test "quotes headers the same way as values" do
      csv = Slab.Export.csv([], [{~s(Name, "Full"), :name}])

      assert csv == ~s("Name, ""Full"""\r\n)
    end

    test "formats nil, booleans, dates, times, lists, and maps" do
      record = %{
        missing: nil,
        active: true,
        at: ~U[2026-01-01 12:00:00Z],
        day: ~D[2026-01-01],
        tags: ["one", "two"],
        metadata: %{"role" => "admin"}
      }

      csv =
        Slab.Export.csv(
          [record],
          [
            {"Missing", :missing},
            {"Active", :active},
            {"At", :at},
            {"Day", :day},
            {"Tags", :tags},
            {"Metadata", :metadata}
          ]
        )

      [_header, row, ""] = String.split(csv, "\r\n")

      assert row ==
               ~s(,true,2026-01-01T12:00:00Z,2026-01-01,"one, two","%{""role"" => ""admin""}")
    end

    test "reads missing fields as empty" do
      csv = Slab.Export.csv([%{name: "Ada"}], [{"Name", :name}, {"Email", :email}])

      assert csv == "Name,Email\r\nAda,\r\n"
    end
  end
end
