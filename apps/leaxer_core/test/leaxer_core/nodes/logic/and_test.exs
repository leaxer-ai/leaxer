defmodule LeaxerCore.Nodes.Logic.AndTest do
  use ExUnit.Case

  alias LeaxerCore.Nodes.Logic.And

  describe "And node" do
    test "returns correct type" do
      assert And.type() == "And"
    end

    test "returns correct label" do
      assert And.label() == "And"
    end

    test "returns correct category" do
      assert And.category() == "Logic"
    end

    test "returns correct description" do
      assert And.description() == "Returns true if both inputs are true (logical AND)"
    end

    test "has correct input specification" do
      input_spec = And.input_spec()

      assert %{
               a: %{type: :boolean, label: "A", default: false, configurable: true},
               b: %{type: :boolean, label: "B", default: false, configurable: true}
             } = input_spec
    end

    test "has correct output specification" do
      output_spec = And.output_spec()
      assert %{result: %{type: :boolean, label: "RESULT"}} = output_spec
    end
  end

  describe "process/2" do
    test "returns true when both inputs are true" do
      assert {:ok, %{"result" => true}} =
               And.process(%{"a" => true, "b" => true}, %{})
    end

    test "returns false when first input is false" do
      assert {:ok, %{"result" => false}} =
               And.process(%{"a" => false, "b" => true}, %{})
    end

    test "returns false when second input is false" do
      assert {:ok, %{"result" => false}} =
               And.process(%{"a" => true, "b" => false}, %{})
    end

    test "returns false when both inputs are false" do
      assert {:ok, %{"result" => false}} =
               And.process(%{"a" => false, "b" => false}, %{})
    end

    test "uses config values when inputs not provided" do
      assert {:ok, %{"result" => true}} =
               And.process(%{}, %{"a" => true, "b" => true})

      assert {:ok, %{"result" => false}} =
               And.process(%{}, %{"a" => false, "b" => true})
    end

    test "truthy inputs override config" do
      assert {:ok, %{"result" => true}} =
               And.process(%{"a" => true, "b" => true}, %{"a" => false, "b" => false})
    end

    test "config fallback when inputs are falsy" do
      # Due to Elixir || operator, false inputs fall back to config
      assert {:ok, %{"result" => true}} =
               And.process(%{"a" => false, "b" => true}, %{"a" => true, "b" => true})
    end

    test "mixes input and config values" do
      assert {:ok, %{"result" => true}} =
               And.process(%{"a" => true}, %{"b" => true})

      assert {:ok, %{"result" => false}} =
               And.process(%{"a" => true}, %{"b" => false})
    end

    test "uses defaults when neither input nor config provided" do
      assert {:ok, %{"result" => false}} = And.process(%{}, %{})
    end

    test "handles type coercion via Helpers.to_bool" do
      # Truthy values
      assert {:ok, %{"result" => true}} =
               And.process(%{"a" => 1, "b" => "hello"}, %{})

      # Falsy values
      assert {:ok, %{"result" => false}} =
               And.process(%{"a" => 0, "b" => ""}, %{})

      # Mixed
      assert {:ok, %{"result" => false}} =
               And.process(%{"a" => nil, "b" => "hello"}, %{})

      # String "false" is falsy
      assert {:ok, %{"result" => false}} =
               And.process(%{"a" => "false", "b" => true}, %{})
    end

    test "handles nil values" do
      assert {:ok, %{"result" => false}} =
               And.process(%{"a" => nil, "b" => nil}, %{})

      assert {:ok, %{"result" => false}} =
               And.process(%{"a" => nil, "b" => true}, %{})
    end
  end
end
