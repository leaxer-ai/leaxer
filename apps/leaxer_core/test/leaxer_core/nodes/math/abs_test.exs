defmodule LeaxerCore.Nodes.Math.AbsTest do
  use ExUnit.Case

  alias LeaxerCore.Nodes.Math.Abs

  describe "Abs node" do
    test "returns correct type" do
      assert Abs.type() == "Abs"
    end

    test "returns correct label" do
      assert Abs.label() == "Absolute Value"
    end

    test "returns correct category" do
      assert Abs.category() == "Math"
    end

    test "returns correct description" do
      assert Abs.description() == "Return the absolute value of a number"
    end

    test "has correct input specification" do
      input_spec = Abs.input_spec()
      assert %{value: %{type: :float, label: "VALUE", default: 0.0}} = input_spec
    end

    test "has correct output specification" do
      output_spec = Abs.output_spec()
      assert %{result: %{type: :float, label: "RESULT"}} = output_spec
    end
  end

  describe "process/2" do
    test "returns absolute value of positive number" do
      assert {:ok, %{"result" => 5.0}} = Abs.process(%{"value" => 5.0}, %{})
    end

    test "returns absolute value of negative number" do
      assert {:ok, %{"result" => 5.0}} = Abs.process(%{"value" => -5.0}, %{})
    end

    test "returns absolute value of zero" do
      assert {:ok, %{"result" => 0.0}} = Abs.process(%{"value" => 0.0}, %{})
    end

    test "uses config value when input is not provided" do
      assert {:ok, %{"result" => 3.0}} = Abs.process(%{}, %{"value" => -3.0})
    end

    test "prefers input over config" do
      assert {:ok, %{"result" => 7.0}} = Abs.process(%{"value" => -7.0}, %{"value" => -3.0})
    end

    test "uses default value when neither input nor config provided" do
      assert {:ok, %{"result" => 0.0}} = Abs.process(%{}, %{})
    end

    test "handles integer input" do
      assert {:ok, %{"result" => 42}} = Abs.process(%{"value" => -42}, %{})
    end

    test "handles float input" do
      assert {:ok, %{"result" => 3.14}} = Abs.process(%{"value" => -3.14}, %{})
    end
  end
end
