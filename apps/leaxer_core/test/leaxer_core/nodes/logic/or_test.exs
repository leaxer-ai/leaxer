defmodule LeaxerCore.Nodes.Logic.OrTest do
  use ExUnit.Case

  alias LeaxerCore.Nodes.Logic.Or

  describe "Or node" do
    test "returns correct type" do
      assert Or.type() == "Or"
    end

    test "returns correct label" do
      assert Or.label() == "Or"
    end

    test "returns correct category" do
      assert Or.category() == "Logic"
    end

    test "returns correct description" do
      assert Or.description() == "Returns true if either input is true (logical OR)"
    end

    test "has correct input specification" do
      input_spec = Or.input_spec()

      assert %{
               a: %{type: :boolean, label: "A", default: false, configurable: true},
               b: %{type: :boolean, label: "B", default: false, configurable: true}
             } = input_spec
    end

    test "has correct output specification" do
      output_spec = Or.output_spec()
      assert %{result: %{type: :boolean, label: "RESULT"}} = output_spec
    end
  end

  describe "process/2" do
    test "returns true when both inputs are true" do
      assert {:ok, %{"result" => true}} =
               Or.process(%{"a" => true, "b" => true}, %{})
    end

    test "returns true when first input is true" do
      assert {:ok, %{"result" => true}} =
               Or.process(%{"a" => true, "b" => false}, %{})
    end

    test "returns true when second input is true" do
      assert {:ok, %{"result" => true}} =
               Or.process(%{"a" => false, "b" => true}, %{})
    end

    test "returns false when both inputs are false" do
      assert {:ok, %{"result" => false}} =
               Or.process(%{"a" => false, "b" => false}, %{})
    end

    test "uses config values when inputs not provided" do
      assert {:ok, %{"result" => true}} =
               Or.process(%{}, %{"a" => true, "b" => false})

      assert {:ok, %{"result" => false}} =
               Or.process(%{}, %{"a" => false, "b" => false})
    end

    test "prefers inputs over config" do
      assert {:ok, %{"result" => true}} =
               Or.process(%{"a" => true, "b" => false}, %{"a" => false, "b" => false})
    end

    test "mixes input and config values" do
      assert {:ok, %{"result" => true}} =
               Or.process(%{"a" => true}, %{"b" => false})

      assert {:ok, %{"result" => true}} =
               Or.process(%{"a" => false}, %{"b" => true})

      assert {:ok, %{"result" => false}} =
               Or.process(%{"a" => false}, %{"b" => false})
    end

    test "uses defaults when neither input nor config provided" do
      assert {:ok, %{"result" => false}} = Or.process(%{}, %{})
    end

    test "handles type coercion via Helpers.to_bool" do
      # Truthy values
      assert {:ok, %{"result" => true}} =
               Or.process(%{"a" => 1, "b" => 0}, %{})

      # Falsy values
      assert {:ok, %{"result" => false}} =
               Or.process(%{"a" => 0, "b" => ""}, %{})

      # Mixed - at least one truthy
      assert {:ok, %{"result" => true}} =
               Or.process(%{"a" => nil, "b" => "hello"}, %{})

      # String "false" is falsy
      assert {:ok, %{"result" => false}} =
               Or.process(%{"a" => "false", "b" => false}, %{})

      # Mixed truthy values
      assert {:ok, %{"result" => true}} =
               Or.process(%{"a" => "hello", "b" => 42}, %{})
    end

    test "handles nil values" do
      assert {:ok, %{"result" => false}} =
               Or.process(%{"a" => nil, "b" => nil}, %{})

      assert {:ok, %{"result" => true}} =
               Or.process(%{"a" => nil, "b" => true}, %{})

      assert {:ok, %{"result" => true}} =
               Or.process(%{"a" => true, "b" => nil}, %{})
    end
  end
end
