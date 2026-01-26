defmodule LeaxerCore.Nodes.Math.FloorTest do
  use ExUnit.Case

  alias LeaxerCore.Nodes.Math.Floor

  describe "Floor node" do
    test "returns correct type" do
      assert Floor.type() == "Floor"
    end

    test "returns correct label" do
      assert Floor.label() == "Floor"
    end

    test "returns correct category" do
      assert Floor.category() == "Math"
    end

    test "returns correct description" do
      assert Floor.description() == "Round a value down to the nearest integer"
    end

    test "has correct input specification" do
      input_spec = Floor.input_spec()
      assert %{value: %{type: :float, label: "VALUE", default: 0.0}} = input_spec
    end

    test "has correct output specification" do
      output_spec = Floor.output_spec()
      assert %{result: %{type: :integer, label: "RESULT"}} = output_spec
    end
  end

  describe "process/2" do
    test "rounds down positive float" do
      assert {:ok, %{"result" => 5}} = Floor.process(%{"value" => 5.9}, %{})
    end

    test "rounds down negative float" do
      assert {:ok, %{"result" => -6}} = Floor.process(%{"value" => -5.1}, %{})
    end

    test "handles exact integer" do
      assert {:ok, %{"result" => 5}} = Floor.process(%{"value" => 5.0}, %{})
    end

    test "handles zero" do
      assert {:ok, %{"result" => 0}} = Floor.process(%{"value" => 0.0}, %{})
    end

    test "uses config value when input not provided" do
      assert {:ok, %{"result" => 3}} = Floor.process(%{}, %{"value" => 3.8})
    end

    test "prefers input over config" do
      assert {:ok, %{"result" => 7}} = Floor.process(%{"value" => 7.9}, %{"value" => 3.8})
    end

    test "uses default when neither input nor config provided" do
      assert {:ok, %{"result" => 0}} = Floor.process(%{}, %{})
    end
  end
end
