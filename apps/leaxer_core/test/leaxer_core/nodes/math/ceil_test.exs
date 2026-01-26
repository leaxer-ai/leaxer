defmodule LeaxerCore.Nodes.Math.CeilTest do
  use ExUnit.Case

  alias LeaxerCore.Nodes.Math.Ceil

  describe "Ceil node" do
    test "returns correct type" do
      assert Ceil.type() == "Ceil"
    end

    test "returns correct label" do
      assert Ceil.label() == "Ceiling"
    end

    test "returns correct category" do
      assert Ceil.category() == "Math"
    end

    test "returns correct description" do
      assert Ceil.description() == "Round a value up to the nearest integer"
    end

    test "has correct input specification" do
      input_spec = Ceil.input_spec()
      assert %{value: %{type: :float, label: "VALUE", default: 0.0}} = input_spec
    end

    test "has correct output specification" do
      output_spec = Ceil.output_spec()
      assert %{result: %{type: :integer, label: "RESULT"}} = output_spec
    end
  end

  describe "process/2" do
    test "rounds up positive float" do
      assert {:ok, %{"result" => 6}} = Ceil.process(%{"value" => 5.1}, %{})
    end

    test "rounds up negative float" do
      assert {:ok, %{"result" => -5}} = Ceil.process(%{"value" => -5.9}, %{})
    end

    test "handles exact integer" do
      assert {:ok, %{"result" => 5}} = Ceil.process(%{"value" => 5.0}, %{})
    end

    test "handles zero" do
      assert {:ok, %{"result" => 0}} = Ceil.process(%{"value" => 0.0}, %{})
    end

    test "uses config value when input not provided" do
      assert {:ok, %{"result" => 4}} = Ceil.process(%{}, %{"value" => 3.2})
    end

    test "prefers input over config" do
      assert {:ok, %{"result" => 8}} = Ceil.process(%{"value" => 7.1}, %{"value" => 3.2})
    end

    test "uses default when neither input nor config provided" do
      assert {:ok, %{"result" => 0}} = Ceil.process(%{}, %{})
    end
  end
end
