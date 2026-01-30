defmodule LeaxerCore.Nodes.Logic.CompareTest do
  use ExUnit.Case

  alias LeaxerCore.Nodes.Logic.Compare

  describe "Compare node" do
    test "returns correct type" do
      assert Compare.type() == "Compare"
    end

    test "returns correct label" do
      assert Compare.label() == "Compare"
    end

    test "returns correct category" do
      assert Compare.category() == "Logic/Flow"
    end

    test "returns correct description" do
      expected = "Compares two values using a specified operator and returns a boolean result"
      assert Compare.description() == expected
    end

    test "has correct input specification" do
      input_spec = Compare.input_spec()
      assert %{a: %{type: :any, label: "A"}} = input_spec
      assert %{b: %{type: :any, label: "B"}} = input_spec

      operator_spec = input_spec.operator
      assert operator_spec.type == :enum
      assert operator_spec.label == "OPERATOR"
      assert operator_spec.default == "=="
      assert length(operator_spec.options) == 6
    end

    test "has correct output specification" do
      output_spec = Compare.output_spec()
      assert %{result: %{type: :boolean, label: "RESULT"}} = output_spec
      assert %{int_result: %{type: :integer, label: "INT RESULT"}} = output_spec
    end
  end

  describe "process/2 - equality operators" do
    test "== operator with equal values" do
      assert {:ok, %{"result" => true, "int_result" => 1}} =
               Compare.process(%{"a" => 5, "b" => 5}, %{"operator" => "=="})
    end

    test "== operator with different values" do
      assert {:ok, %{"result" => false, "int_result" => 0}} =
               Compare.process(%{"a" => 5, "b" => 3}, %{"operator" => "=="})
    end

    test "!= operator with equal values" do
      assert {:ok, %{"result" => false, "int_result" => 0}} =
               Compare.process(%{"a" => 5, "b" => 5}, %{"operator" => "!="})
    end

    test "!= operator with different values" do
      assert {:ok, %{"result" => true, "int_result" => 1}} =
               Compare.process(%{"a" => 5, "b" => 3}, %{"operator" => "!="})
    end
  end

  describe "process/2 - numeric comparison operators" do
    test "< operator with numbers" do
      assert {:ok, %{"result" => true, "int_result" => 1}} =
               Compare.process(%{"a" => 3, "b" => 5}, %{"operator" => "<"})

      assert {:ok, %{"result" => false, "int_result" => 0}} =
               Compare.process(%{"a" => 5, "b" => 3}, %{"operator" => "<"})
    end

    test "> operator with numbers" do
      assert {:ok, %{"result" => true, "int_result" => 1}} =
               Compare.process(%{"a" => 5, "b" => 3}, %{"operator" => ">"})

      assert {:ok, %{"result" => false, "int_result" => 0}} =
               Compare.process(%{"a" => 3, "b" => 5}, %{"operator" => ">"})
    end

    test "<= operator with numbers" do
      assert {:ok, %{"result" => true, "int_result" => 1}} =
               Compare.process(%{"a" => 3, "b" => 5}, %{"operator" => "<="})

      assert {:ok, %{"result" => true, "int_result" => 1}} =
               Compare.process(%{"a" => 5, "b" => 5}, %{"operator" => "<="})

      assert {:ok, %{"result" => false, "int_result" => 0}} =
               Compare.process(%{"a" => 5, "b" => 3}, %{"operator" => "<="})
    end

    test ">= operator with numbers" do
      assert {:ok, %{"result" => true, "int_result" => 1}} =
               Compare.process(%{"a" => 5, "b" => 3}, %{"operator" => ">="})

      assert {:ok, %{"result" => true, "int_result" => 1}} =
               Compare.process(%{"a" => 5, "b" => 5}, %{"operator" => ">="})

      assert {:ok, %{"result" => false, "int_result" => 0}} =
               Compare.process(%{"a" => 3, "b" => 5}, %{"operator" => ">="})
    end
  end

  describe "process/2 - string comparison operators" do
    test "< operator with strings" do
      assert {:ok, %{"result" => true, "int_result" => 1}} =
               Compare.process(%{"a" => "apple", "b" => "banana"}, %{"operator" => "<"})

      assert {:ok, %{"result" => false, "int_result" => 0}} =
               Compare.process(%{"a" => "banana", "b" => "apple"}, %{"operator" => "<"})
    end

    test "> operator with strings" do
      assert {:ok, %{"result" => true, "int_result" => 1}} =
               Compare.process(%{"a" => "banana", "b" => "apple"}, %{"operator" => ">"})

      assert {:ok, %{"result" => false, "int_result" => 0}} =
               Compare.process(%{"a" => "apple", "b" => "banana"}, %{"operator" => ">"})
    end
  end

  describe "process/2 - mixed types and edge cases" do
    test "comparison operators return false for incompatible types" do
      assert {:ok, %{"result" => false, "int_result" => 0}} =
               Compare.process(%{"a" => 5, "b" => "hello"}, %{"operator" => "<"})

      assert {:ok, %{"result" => false, "int_result" => 0}} =
               Compare.process(%{"a" => "hello", "b" => 5}, %{"operator" => ">"})
    end

    test "uses config values when inputs not provided" do
      assert {:ok, %{"result" => true, "int_result" => 1}} =
               Compare.process(%{}, %{"a" => 5, "b" => 5, "operator" => "=="})
    end

    test "defaults to == operator when not specified" do
      assert {:ok, %{"result" => true, "int_result" => 1}} =
               Compare.process(%{"a" => 5, "b" => 5}, %{})
    end

    test "handles invalid operator by defaulting to ==" do
      assert {:ok, %{"result" => true, "int_result" => 1}} =
               Compare.process(%{"a" => 5, "b" => 5}, %{"operator" => "invalid"})
    end

    test "handles nil values" do
      assert {:ok, %{"result" => true, "int_result" => 1}} =
               Compare.process(%{"a" => nil, "b" => nil}, %{"operator" => "=="})

      assert {:ok, %{"result" => false, "int_result" => 0}} =
               Compare.process(%{"a" => nil, "b" => 5}, %{"operator" => "=="})
    end

    test "handles float and integer comparison" do
      assert {:ok, %{"result" => true, "int_result" => 1}} =
               Compare.process(%{"a" => 5.0, "b" => 5}, %{"operator" => "=="})

      assert {:ok, %{"result" => true, "int_result" => 1}} =
               Compare.process(%{"a" => 3.5, "b" => 5}, %{"operator" => "<"})
    end
  end
end
