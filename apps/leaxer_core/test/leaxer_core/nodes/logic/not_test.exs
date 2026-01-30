defmodule LeaxerCore.Nodes.Logic.NotTest do
  use ExUnit.Case

  alias LeaxerCore.Nodes.Logic.Not

  describe "Not node" do
    test "returns correct type" do
      assert Not.type() == "Not"
    end

    test "returns correct label" do
      assert Not.label() == "Not"
    end

    test "returns correct category" do
      assert Not.category() == "Logic/Boolean"
    end

    test "returns correct description" do
      assert Not.description() == "Returns the logical inverse of the input (logical NOT)"
    end

    test "has correct input specification" do
      input_spec = Not.input_spec()

      assert %{
               value: %{type: :boolean, label: "VALUE", default: false, configurable: true}
             } = input_spec
    end

    test "has correct output specification" do
      output_spec = Not.output_spec()
      assert %{result: %{type: :boolean, label: "RESULT"}} = output_spec
    end
  end

  describe "process/2" do
    test "returns false when input is true" do
      assert {:ok, %{"result" => false}} =
               Not.process(%{"value" => true}, %{})
    end

    test "returns true when input is false" do
      assert {:ok, %{"result" => true}} =
               Not.process(%{"value" => false}, %{})
    end

    test "uses config value when input not provided" do
      assert {:ok, %{"result" => false}} =
               Not.process(%{}, %{"value" => true})

      assert {:ok, %{"result" => true}} =
               Not.process(%{}, %{"value" => false})
    end

    test "input overrides config when input is truthy" do
      assert {:ok, %{"result" => false}} =
               Not.process(%{"value" => true}, %{"value" => false})
    end

    test "config fallback when input is falsy" do
      # Due to Elixir || operator, false input falls back to config
      assert {:ok, %{"result" => false}} =
               Not.process(%{"value" => false}, %{"value" => true})
    end

    test "uses default when neither input nor config provided" do
      # Default is false, so NOT false = true
      assert {:ok, %{"result" => true}} = Not.process(%{}, %{})
    end

    test "handles type coercion via Helpers.to_bool" do
      # Truthy values become false when inverted
      assert {:ok, %{"result" => false}} =
               Not.process(%{"value" => 1}, %{})

      assert {:ok, %{"result" => false}} =
               Not.process(%{"value" => "hello"}, %{})

      assert {:ok, %{"result" => false}} =
               Not.process(%{"value" => 42}, %{})

      # Falsy values become true when inverted
      assert {:ok, %{"result" => true}} =
               Not.process(%{"value" => 0}, %{})

      assert {:ok, %{"result" => true}} =
               Not.process(%{"value" => ""}, %{})

      assert {:ok, %{"result" => true}} =
               Not.process(%{"value" => "false"}, %{})

      assert {:ok, %{"result" => true}} =
               Not.process(%{"value" => 0.0}, %{})
    end

    test "handles nil value" do
      # nil is falsy, so NOT nil = true
      assert {:ok, %{"result" => true}} =
               Not.process(%{"value" => nil}, %{})
    end

    test "handles edge cases" do
      # Empty list should be truthy (not in falsy list)
      assert {:ok, %{"result" => false}} =
               Not.process(%{"value" => []}, %{})

      # Empty map should be truthy (not in falsy list)
      assert {:ok, %{"result" => false}} =
               Not.process(%{"value" => %{}}, %{})

      # Atom other than false should be truthy
      assert {:ok, %{"result" => false}} =
               Not.process(%{"value" => true}, %{})
    end
  end
end
