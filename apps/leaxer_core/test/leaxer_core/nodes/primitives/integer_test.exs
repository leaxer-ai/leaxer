defmodule LeaxerCore.Nodes.Primitives.IntegerTest do
  use ExUnit.Case, async: true

  alias LeaxerCore.Nodes.Primitives.Integer

  describe "type/0" do
    test "returns correct type" do
      assert Integer.type() == "Integer"
    end
  end

  describe "label/0" do
    test "returns correct label" do
      assert Integer.label() == "Integer"
    end
  end

  describe "category/0" do
    test "returns correct category" do
      assert Integer.category() == "Primitives"
    end
  end

  describe "description/0" do
    test "returns correct description" do
      assert Integer.description() == "A constant integer value"
    end
  end

  describe "input_spec/0" do
    test "returns correct input specification" do
      spec = Integer.input_spec()

      assert spec == %{
               value: %{type: :integer, label: "VALUE", default: 0}
             }
    end
  end

  describe "output_spec/0" do
    test "returns correct output specification" do
      spec = Integer.output_spec()

      assert spec == %{
               value: %{type: :integer, label: "VALUE"}
             }
    end
  end

  describe "process/2" do
    test "returns value from config when provided" do
      config = %{"value" => 42}
      assert {:ok, %{"value" => 42}} = Integer.process(%{}, config)
    end

    test "returns zero when value is nil in config" do
      config = %{"value" => nil}
      assert {:ok, %{"value" => 0}} = Integer.process(%{}, config)
    end

    test "returns zero when value key is missing from config" do
      config = %{}
      assert {:ok, %{"value" => 0}} = Integer.process(%{}, config)
    end

    test "handles negative integers" do
      config = %{"value" => -123}
      assert {:ok, %{"value" => -123}} = Integer.process(%{}, config)
    end

    test "handles large integers" do
      config = %{"value" => 999_999_999}
      assert {:ok, %{"value" => 999_999_999}} = Integer.process(%{}, config)
    end

    test "ignores inputs parameter" do
      inputs = %{"ignored" => "value"}
      config = %{"value" => 100}
      assert {:ok, %{"value" => 100}} = Integer.process(inputs, config)
    end
  end
end
