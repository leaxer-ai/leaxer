defmodule LeaxerCore.Nodes.Logic.BooleanLogicTest do
  use ExUnit.Case

  alias LeaxerCore.Nodes.Logic.BooleanLogic

  describe "BooleanLogic node" do
    test "returns correct type" do
      assert BooleanLogic.type() == "BooleanLogic"
    end

    test "returns correct label" do
      assert BooleanLogic.label() == "Boolean Logic"
    end

    test "returns correct category" do
      assert BooleanLogic.category() == "Logic/Boolean"
    end

    test "returns correct description" do
      assert BooleanLogic.description() == "Boolean operations (AND, OR, XOR, NOT, NAND, NOR)"
    end

    test "has correct input specification" do
      input_spec = BooleanLogic.input_spec()
      assert %{a: %{type: :boolean, label: "A", default: false}} = input_spec
      assert %{b: %{type: :boolean, label: "B", default: false, optional: true}} = input_spec

      operation_spec = input_spec.operation
      assert operation_spec.type == :enum
      assert operation_spec.label == "OPERATION"
      assert operation_spec.default == "AND"
      assert length(operation_spec.options) == 6
    end

    test "has correct output specification" do
      output_spec = BooleanLogic.output_spec()
      assert %{result: %{type: :boolean, label: "RESULT"}} = output_spec
      assert %{int_result: %{type: :integer, label: "INT RESULT"}} = output_spec
    end
  end

  describe "process/2 - AND operation" do
    test "AND with both true" do
      assert {:ok, %{"result" => true, "int_result" => 1}} =
               BooleanLogic.process(%{"a" => true, "b" => true, "operation" => "AND"}, %{})
    end

    test "AND with both false" do
      assert {:ok, %{"result" => false, "int_result" => 0}} =
               BooleanLogic.process(%{"a" => false, "b" => false, "operation" => "AND"}, %{})
    end

    test "AND with mixed values" do
      assert {:ok, %{"result" => false, "int_result" => 0}} =
               BooleanLogic.process(%{"a" => true, "b" => false, "operation" => "AND"}, %{})

      assert {:ok, %{"result" => false, "int_result" => 0}} =
               BooleanLogic.process(%{"a" => false, "b" => true, "operation" => "AND"}, %{})
    end
  end

  describe "process/2 - OR operation" do
    test "OR with both true" do
      assert {:ok, %{"result" => true, "int_result" => 1}} =
               BooleanLogic.process(%{"a" => true, "b" => true, "operation" => "OR"}, %{})
    end

    test "OR with both false" do
      assert {:ok, %{"result" => false, "int_result" => 0}} =
               BooleanLogic.process(%{"a" => false, "b" => false, "operation" => "OR"}, %{})
    end

    test "OR with mixed values" do
      assert {:ok, %{"result" => true, "int_result" => 1}} =
               BooleanLogic.process(%{"a" => true, "b" => false, "operation" => "OR"}, %{})

      assert {:ok, %{"result" => true, "int_result" => 1}} =
               BooleanLogic.process(%{"a" => false, "b" => true, "operation" => "OR"}, %{})
    end
  end

  describe "process/2 - XOR operation" do
    test "XOR with same values" do
      assert {:ok, %{"result" => false, "int_result" => 0}} =
               BooleanLogic.process(%{"a" => true, "b" => true, "operation" => "XOR"}, %{})

      assert {:ok, %{"result" => false, "int_result" => 0}} =
               BooleanLogic.process(%{"a" => false, "b" => false, "operation" => "XOR"}, %{})
    end

    test "XOR with different values" do
      assert {:ok, %{"result" => true, "int_result" => 1}} =
               BooleanLogic.process(%{"a" => true, "b" => false, "operation" => "XOR"}, %{})

      assert {:ok, %{"result" => true, "int_result" => 1}} =
               BooleanLogic.process(%{"a" => false, "b" => true, "operation" => "XOR"}, %{})
    end
  end

  describe "process/2 - NOT operation" do
    test "NOT with true" do
      assert {:ok, %{"result" => false, "int_result" => 0}} =
               BooleanLogic.process(%{"a" => true, "operation" => "NOT"}, %{})
    end

    test "NOT with false" do
      assert {:ok, %{"result" => true, "int_result" => 1}} =
               BooleanLogic.process(%{"a" => false, "operation" => "NOT"}, %{})
    end

    test "NOT ignores b parameter" do
      assert {:ok, %{"result" => false, "int_result" => 0}} =
               BooleanLogic.process(%{"a" => true, "b" => false, "operation" => "NOT"}, %{})
    end
  end

  describe "process/2 - NAND operation" do
    test "NAND is opposite of AND" do
      assert {:ok, %{"result" => false, "int_result" => 0}} =
               BooleanLogic.process(%{"a" => true, "b" => true, "operation" => "NAND"}, %{})

      assert {:ok, %{"result" => true, "int_result" => 1}} =
               BooleanLogic.process(%{"a" => true, "b" => false, "operation" => "NAND"}, %{})

      assert {:ok, %{"result" => true, "int_result" => 1}} =
               BooleanLogic.process(%{"a" => false, "b" => true, "operation" => "NAND"}, %{})

      assert {:ok, %{"result" => true, "int_result" => 1}} =
               BooleanLogic.process(%{"a" => false, "b" => false, "operation" => "NAND"}, %{})
    end
  end

  describe "process/2 - NOR operation" do
    test "NOR is opposite of OR" do
      assert {:ok, %{"result" => false, "int_result" => 0}} =
               BooleanLogic.process(%{"a" => true, "b" => true, "operation" => "NOR"}, %{})

      assert {:ok, %{"result" => false, "int_result" => 0}} =
               BooleanLogic.process(%{"a" => true, "b" => false, "operation" => "NOR"}, %{})

      assert {:ok, %{"result" => false, "int_result" => 0}} =
               BooleanLogic.process(%{"a" => false, "b" => true, "operation" => "NOR"}, %{})

      assert {:ok, %{"result" => true, "int_result" => 1}} =
               BooleanLogic.process(%{"a" => false, "b" => false, "operation" => "NOR"}, %{})
    end
  end

  describe "process/2 - type coercion and edge cases" do
    test "uses config values when inputs not provided" do
      assert {:ok, %{"result" => true, "int_result" => 1}} =
               BooleanLogic.process(%{}, %{"a" => true, "b" => false, "operation" => "OR"})
    end

    test "defaults to AND operation when not specified" do
      assert {:ok, %{"result" => false, "int_result" => 0}} =
               BooleanLogic.process(%{"a" => true, "b" => false}, %{})
    end

    test "defaults to false for all values when nothing provided" do
      assert {:ok, %{"result" => false, "int_result" => 0}} =
               BooleanLogic.process(%{}, %{})
    end

    test "handles invalid operation by defaulting to false" do
      assert {:ok, %{"result" => false, "int_result" => 0}} =
               BooleanLogic.process(%{"a" => true, "b" => true, "operation" => "INVALID"}, %{})
    end

    test "handles NOT operation correctly" do
      # NOT operation inverts the 'a' value
      assert {:ok, %{"result" => false, "int_result" => 0}} =
               BooleanLogic.process(%{"a" => true, "operation" => "NOT"}, %{})
    end

    test "coerces non-boolean values correctly" do
      # The module uses its internal to_bool function which follows these rules:
      # nil, false, 0, 0.0, "", "false" -> false
      # everything else -> true

      # Test truthy values
      assert {:ok, %{"result" => true, "int_result" => 1}} =
               BooleanLogic.process(%{"a" => 1, "b" => "hello", "operation" => "AND"}, %{})

      # Test falsy values
      assert {:ok, %{"result" => false, "int_result" => 0}} =
               BooleanLogic.process(%{"a" => 0, "b" => "", "operation" => "OR"}, %{})

      # Test mixed falsy/truthy
      assert {:ok, %{"result" => false, "int_result" => 0}} =
               BooleanLogic.process(%{"a" => nil, "b" => "hello", "operation" => "AND"}, %{})
    end
  end
end
