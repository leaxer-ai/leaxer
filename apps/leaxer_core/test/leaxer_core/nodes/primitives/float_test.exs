defmodule LeaxerCore.Nodes.Primitives.FloatTest do
  use ExUnit.Case, async: true

  alias LeaxerCore.Nodes.Primitives.Float

  describe "type/0" do
    test "returns correct type" do
      assert Float.type() == "Float"
    end
  end

  describe "label/0" do
    test "returns correct label" do
      assert Float.label() == "Float"
    end
  end

  describe "category/0" do
    test "returns correct category" do
      assert Float.category() == "Primitives"
    end
  end

  describe "description/0" do
    test "returns correct description" do
      assert Float.description() == "A constant floating-point value"
    end
  end

  describe "input_spec/0" do
    test "returns correct input specification" do
      spec = Float.input_spec()

      assert spec == %{
               value: %{type: :float, label: "VALUE", default: 0.0, step: 0.1}
             }
    end
  end

  describe "output_spec/0" do
    test "returns correct output specification" do
      spec = Float.output_spec()

      assert spec == %{
               value: %{type: :float, label: "VALUE"}
             }
    end
  end

  describe "process/2" do
    test "returns value from config when provided" do
      config = %{"value" => 3.14}
      assert {:ok, %{"value" => 3.14}} = Float.process(%{}, config)
    end

    test "returns zero when value is nil in config" do
      config = %{"value" => nil}
      assert {:ok, %{"value" => 0.0}} = Float.process(%{}, config)
    end

    test "returns zero when value key is missing from config" do
      config = %{}
      assert {:ok, %{"value" => 0.0}} = Float.process(%{}, config)
    end

    test "handles negative floats" do
      config = %{"value" => -2.5}
      assert {:ok, %{"value" => -2.5}} = Float.process(%{}, config)
    end

    test "handles very small floats" do
      config = %{"value" => 0.00001}
      assert {:ok, %{"value" => 0.00001}} = Float.process(%{}, config)
    end

    test "handles very large floats" do
      config = %{"value" => 999_999.99999}
      assert {:ok, %{"value" => 999_999.99999}} = Float.process(%{}, config)
    end

    test "handles integer values as floats" do
      config = %{"value" => 5}
      assert {:ok, %{"value" => 5}} = Float.process(%{}, config)
    end

    test "ignores inputs parameter" do
      inputs = %{"ignored" => "value"}
      config = %{"value" => 2.718}
      assert {:ok, %{"value" => 2.718}} = Float.process(inputs, config)
    end
  end
end
