defmodule LeaxerCore.Nodes.Primitives.BooleanTest do
  use ExUnit.Case, async: true

  alias LeaxerCore.Nodes.Primitives.Boolean

  describe "type/0" do
    test "returns correct type" do
      assert Boolean.type() == "Boolean"
    end
  end

  describe "label/0" do
    test "returns correct label" do
      assert Boolean.label() == "Boolean"
    end
  end

  describe "category/0" do
    test "returns correct category" do
      assert Boolean.category() == "Primitives"
    end
  end

  describe "description/0" do
    test "returns correct description" do
      assert Boolean.description() == "A constant boolean value (true/false)"
    end
  end

  describe "input_spec/0" do
    test "returns correct input specification" do
      spec = Boolean.input_spec()

      assert spec == %{
               value: %{type: :boolean, label: "VALUE", default: false}
             }
    end
  end

  describe "output_spec/0" do
    test "returns correct output specification" do
      spec = Boolean.output_spec()

      assert spec == %{
               value: %{type: :boolean, label: "VALUE"}
             }
    end
  end

  describe "process/2" do
    test "returns true when config value is true" do
      config = %{"value" => true}
      assert {:ok, %{"value" => true}} = Boolean.process(%{}, config)
    end

    test "returns false when config value is false" do
      config = %{"value" => false}
      assert {:ok, %{"value" => false}} = Boolean.process(%{}, config)
    end

    test "returns false when value is nil in config" do
      config = %{"value" => nil}
      assert {:ok, %{"value" => false}} = Boolean.process(%{}, config)
    end

    test "returns false when value key is missing from config" do
      config = %{}
      assert {:ok, %{"value" => false}} = Boolean.process(%{}, config)
    end

    test "ignores inputs parameter" do
      inputs = %{"ignored" => "value"}
      config = %{"value" => true}
      assert {:ok, %{"value" => true}} = Boolean.process(inputs, config)
    end
  end
end
