defmodule Slab.Helpers.ParamsTest do
  use ExUnit.Case, async: true

  alias Slab.Helpers.Params

  doctest Slab.Helpers.Params

  describe "positive_int/2" do
    test "rejects garbage, zero, negatives, and partial numbers" do
      assert Params.positive_int("abc", 7) == 7
      assert Params.positive_int("0", 7) == 7
      assert Params.positive_int("-2", 7) == 7
      assert Params.positive_int("3x", 7) == 7
      assert Params.positive_int(nil, 7) == 7
      assert Params.positive_int(%{"nested" => "1"}, 7) == 7
    end

    test "accepts positive integers and numeric strings" do
      assert Params.positive_int("3", 7) == 3
      assert Params.positive_int(3, 7) == 3
    end
  end

  describe "per_page/3" do
    test "clamps to the maximum" do
      assert Params.per_page(%{"per_page" => "500"}, 25, 100) == 100
    end
  end
end
