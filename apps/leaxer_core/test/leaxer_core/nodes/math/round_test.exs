defmodule LeaxerCore.Nodes.Math.RoundTest do
  use ExUnit.Case

  alias LeaxerCore.Nodes.Math.Round

  describe "Round node" do
    test "returns correct type" do
      assert Round.type() == "Round"
    end

    test "returns correct label" do
      assert Round.label() == "Round"
    end

    test "returns correct category" do
      assert Round.category() == "Math"
    end

    test "returns correct description" do
      assert Round.description() == "Round a value to the nearest integer"
    end

    test "has correct input specification" do
      input_spec = Round.input_spec()
      assert %{value: %{type: :float, label: "VALUE", default: 0.0}} = input_spec
    end

    test "has correct output specification" do
      output_spec = Round.output_spec()
      assert %{result: %{type: :integer, label: "RESULT"}} = output_spec
    end
  end

  describe "process/2" do
    test "rounds to nearest integer - up" do
      assert {:ok, %{"result" => 6}} = Round.process(%{"value" => 5.6}, %{})
    end

    test "rounds to nearest integer - down" do
      assert {:ok, %{"result" => 5}} = Round.process(%{"value" => 5.4}, %{})
    end

    test "rounds midpoint up (banker's rounding)" do
      assert {:ok, %{"result" => 6}} = Round.process(%{"value" => 5.5}, %{})
    end

    test "handles negative numbers" do
      assert {:ok, %{"result" => -6}} = Round.process(%{"value" => -5.6}, %{})
      assert {:ok, %{"result" => -5}} = Round.process(%{"value" => -5.4}, %{})
    end

    test "handles exact integer" do
      assert {:ok, %{"result" => 5}} = Round.process(%{"value" => 5.0}, %{})
    end

    test "handles zero" do
      assert {:ok, %{"result" => 0}} = Round.process(%{"value" => 0.0}, %{})
    end

    test "uses config value when input not provided" do
      assert {:ok, %{"result" => 4}} = Round.process(%{}, %{"value" => 3.7})
    end

    test "prefers input over config" do
      assert {:ok, %{"result" => 8}} = Round.process(%{"value" => 7.6}, %{"value" => 3.7})
    end

    test "uses default when neither input nor config provided" do
      assert {:ok, %{"result" => 0}} = Round.process(%{}, %{})
    end
  end
end
