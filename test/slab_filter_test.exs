defmodule SlabFilterTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  describe "filter/1 text" do
    test "renders a debounced text input with the current value from params" do
      html =
        render_component(
          fn assigns ->
            ~H"""
            <Slab.filter
              id="filter-name"
              field={:name}
              uri={@uri}
              params={@params}
              label="Name"
              placeholder="Search names..."
            />
            """
          end,
          uri: "https://example.com/users?filter[name]=ada",
          params: %{"filter" => %{"name" => "ada"}}
        )

      assert html =~ ~s(value="ada")
      assert html =~ ~s(placeholder="Search names...")
      assert html =~ ~s(phx-debounce="300")
      assert html =~ "Name"
      assert html =~ ~s(phx-change="change")
    end

    test "renders empty without a current filter value" do
      html =
        render_component(
          fn assigns ->
            ~H"""
            <Slab.filter id="filter-name" field={:name} uri={@uri} params={@params} />
            """
          end,
          uri: "https://example.com/users",
          params: %{}
        )

      refute html =~ ~s(value="ada")
    end

    test "operator-map filter values render as empty rather than crashing" do
      html =
        render_component(
          fn assigns ->
            ~H"""
            <Slab.filter id="filter-age" field={:age} uri={@uri} params={@params} />
            """
          end,
          uri: "https://example.com/users?filter[age][gte]=21",
          params: %{"filter" => %{"age" => %{"gte" => "21"}}}
        )

      refute html =~ ~s(value="21")
    end
  end

  describe "filter/1 select" do
    test "renders a PhoenixSelect combobox with the current value selected" do
      html =
        render_component(
          fn assigns ->
            ~H"""
            <Slab.filter
              id="filter-active"
              field={:active}
              uri={@uri}
              params={@params}
              type="select"
              label="Status"
              options={[{"Active", "true"}, {"Inactive", "false"}]}
            />
            """
          end,
          uri: "https://example.com/users?filter[active]=true",
          params: %{"filter" => %{"active" => "true"}}
        )

      assert html =~ ~s(role="combobox")
      assert html =~ ~s(data-multiple="false")
      assert html =~ "Status"
      assert html =~ ~s(data-ps-option="true")
      assert html =~ ~s(data-ps-option="false")

      # Current value from the URL is selected, held in a hidden input
      assert html =~ ~s(aria-selected="true")
      assert html =~ ~s(name="filter[active]" value="true")
    end
  end

  describe "filter/1 multiselect" do
    test "renders a multi PhoenixSelect with current values as tags" do
      html =
        render_component(
          fn assigns ->
            ~H"""
            <Slab.filter
              id="filter-role"
              field={:role}
              uri={@uri}
              params={@params}
              type="multiselect"
              label="Roles"
              options={[{"Admin", "admin"}, {"Member", "member"}, {"Guest", "guest"}]}
            />
            """
          end,
          uri: "https://example.com/users?filter[role][]=admin&filter[role][]=member",
          params: %{"filter" => %{"role" => ["admin", "member"]}}
        )

      assert html =~ ~s(data-multiple="true")

      # Both selections render as removable tags with hidden array inputs
      assert html =~ ~s(data-ps-remove="admin")
      assert html =~ ~s(data-ps-remove="member")
      refute html =~ ~s(data-ps-remove="guest")
      assert html =~ ~s(name="filter[role][]" value="admin")
      assert html =~ ~s(name="filter[role][]" value="member")
    end
  end

  describe "apply_change?/2" do
    test "empty always applies, clearing the filter" do
      assert Slab.FilterLive.apply_change?("", 3)
    end

    test "short values wait for min_chars" do
      refute Slab.FilterLive.apply_change?("ad", 3)
      assert Slab.FilterLive.apply_change?("ada", 3)
    end

    test "min_chars of zero applies every change" do
      assert Slab.FilterLive.apply_change?("a", 0)
    end
  end
end
