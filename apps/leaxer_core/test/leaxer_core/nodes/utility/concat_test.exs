defmodule LeaxerCore.Nodes.Utility.ConcatTest do
  use ExUnit.Case

  alias LeaxerCore.Nodes.Utility.Concat

  describe "Concat node" do
    test "returns correct type" do
      assert Concat.type() == "Concat"
    end

    test "returns correct label" do
      assert Concat.label() == "Concatenate"
    end

    test "returns correct category" do
      assert Concat.category() == "Text"
    end

    test "returns correct description" do
      assert Concat.description() == "Joins two strings together"
    end

    test "has correct input specification" do
      input_spec = Concat.input_spec()

      assert %{
               a: %{type: :string, label: "A", default: ""},
               b: %{type: :string, label: "B", default: ""}
             } = input_spec
    end

    test "has correct output specification" do
      output_spec = Concat.output_spec()
      assert %{result: %{type: :string, label: "RESULT"}} = output_spec
    end
  end

  describe "process/2" do
    test "concatenates two strings" do
      assert {:ok, %{"result" => "HelloWorld"}} =
               Concat.process(%{"a" => "Hello", "b" => "World"}, %{})
    end

    test "concatenates with spaces" do
      assert {:ok, %{"result" => "Hello World"}} =
               Concat.process(%{"a" => "Hello ", "b" => "World"}, %{})
    end

    test "handles empty strings" do
      assert {:ok, %{"result" => "Hello"}} =
               Concat.process(%{"a" => "Hello", "b" => ""}, %{})

      assert {:ok, %{"result" => "World"}} =
               Concat.process(%{"a" => "", "b" => "World"}, %{})
    end

    test "uses config values when inputs not provided" do
      assert {:ok, %{"result" => "ConfigTest"}} =
               Concat.process(%{}, %{"a" => "Config", "b" => "Test"})
    end

    test "prefers inputs over config" do
      assert {:ok, %{"result" => "InputTest"}} =
               Concat.process(%{"a" => "Input", "b" => "Test"}, %{
                 "a" => "Config",
                 "b" => "Values"
               })
    end

    test "mixes input and config values" do
      assert {:ok, %{"result" => "InputConfig"}} =
               Concat.process(%{"a" => "Input"}, %{"b" => "Config"})
    end

    test "uses defaults when neither input nor config provided" do
      assert {:ok, %{"result" => ""}} = Concat.process(%{}, %{})
    end

    test "handles non-string inputs with to_string conversion" do
      assert {:ok, %{"result" => "123456"}} =
               Concat.process(%{"a" => 123, "b" => 456}, %{})

      assert {:ok, %{"result" => "3.14true"}} =
               Concat.process(%{"a" => 3.14, "b" => true}, %{})
    end

    test "handles special characters" do
      assert {:ok, %{"result" => "Hello\nWorld!"}} =
               Concat.process(%{"a" => "Hello\n", "b" => "World!"}, %{})
    end
  end
end
