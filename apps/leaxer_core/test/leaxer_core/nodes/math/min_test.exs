defmodule LeaxerCore.Nodes.Math.MinTest do
  use ExUnit.Case

  alias LeaxerCore.Nodes.Math.Min

  describe "Min node" do
    test "returns correct type" do
      assert Min.type() == "Min"
    end

    test "returns correct label" do
      assert Min.label() == "Minimum"
    end

    test "returns correct category" do
      assert Min.category() == "Math/Range"
    end

    test "returns correct description" do
      assert Min.description() == "Return the smaller of two values"
    end

    test "has correct input specification" do
      input_spec = Min.input_spec()

      assert %{
               a: %{type: :float, label: "A", default: 0.0},
               b: %{type: :float, label: "B", default: 0.0}
             } = input_spec
    end

    test "has correct output specification" do
      output_spec = Min.output_spec()
      assert %{result: %{type: :float, label: "RESULT"}} = output_spec
    end
  end

  describe "process/2" do
    test "returns smaller of two positive numbers" do
      assert {:ok, %{"result" => 3.0}} = Min.process(%{"a" => 5.0, "b" => 3.0}, %{})
    end

    test "returns smaller of two negative numbers" do
      assert {:ok, %{"result" => -7.0}} = Min.process(%{"a" => -5.0, "b" => -7.0}, %{})
    end

    test "returns smaller when one is positive, one negative" do
      assert {:ok, %{"result" => -3.0}} = Min.process(%{"a" => 5.0, "b" => -3.0}, %{})
    end

    test "returns same value when both are equal" do
      assert {:ok, %{"result" => 4.2}} = Min.process(%{"a" => 4.2, "b" => 4.2}, %{})
    end

    test "handles zero" do
      assert {:ok, %{"result" => 0.0}} = Min.process(%{"a" => 0.0, "b" => 5.0}, %{})
    end

    test "uses config values when inputs not provided" do
      assert {:ok, %{"result" => 2.0}} = Min.process(%{}, %{"a" => 8.0, "b" => 2.0})
    end

    test "prefers inputs over config" do
      assert {:ok, %{"result" => 1.0}} =
               Min.process(%{"a" => 1.0, "b" => 3.0}, %{"a" => 8.0, "b" => 2.0})
    end

    test "mixes input and config values" do
      assert {:ok, %{"result" => 2.0}} = Min.process(%{"a" => 5.0}, %{"b" => 2.0})
      assert {:ok, %{"result" => 2.0}} = Min.process(%{"b" => 2.0}, %{"a" => 5.0})
    end

    test "uses defaults when neither input nor config provided" do
      assert {:ok, %{"result" => 0.0}} = Min.process(%{}, %{})
    end
  end
end
