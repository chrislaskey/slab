defmodule Slab.Helpers.URITest do
  use ExUnit.Case, async: true

  doctest Slab.Helpers.URI

  describe "get_query_param/2" do
    test "decodes bracket params into maps" do
      assert Slab.Helpers.URI.get_query_param("/users?filter[status]=active", "filter") ==
               %{"status" => "active"}
    end
  end

  describe "create_or_update_query_param/3" do
    test "encodes list values as array params" do
      assert Slab.Helpers.URI.create_or_update_query_param("/users", "checked", ["1", "2"]) ==
               "/users?checked[]=1&checked[]=2"
    end

    test "supports bracket keys" do
      assert Slab.Helpers.URI.create_or_update_query_param(
               "/users",
               "filter[status]",
               "active"
             ) ==
               "/users?filter[status]=active"
    end

    test "preserves other params" do
      assert Slab.Helpers.URI.create_or_update_query_param("/users?page=2", "sort", "name") ==
               "/users?page=2&sort=name"
    end
  end

  describe "delete_query_param/2" do
    test "removes empty parent maps when deleting nested keys" do
      assert Slab.Helpers.URI.delete_query_param(
               "/users?filter[status]=active",
               "filter[status]"
             ) ==
               "/users"
    end
  end

  describe "create_or_update_or_delete_query_param/3" do
    test "deletes on nil, empty string, and empty list" do
      assert Slab.Helpers.URI.create_or_update_or_delete_query_param("/users?a=1", "a", nil) ==
               "/users"

      assert Slab.Helpers.URI.create_or_update_or_delete_query_param("/users?a=1", "a", "") ==
               "/users"

      assert Slab.Helpers.URI.create_or_update_or_delete_query_param("/users?a=1", "a", []) ==
               "/users"
    end

    test "updates on non-empty values" do
      assert Slab.Helpers.URI.create_or_update_or_delete_query_param("/users", "a", "1") ==
               "/users?a=1"
    end
  end
end
