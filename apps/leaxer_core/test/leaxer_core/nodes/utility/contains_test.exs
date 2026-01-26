defmodule LeaxerCore.Nodes.Utility.ContainsTest do
  use ExUnit.Case

  alias LeaxerCore.Nodes.Utility.Contains

  describe "Contains node" do
    test "returns correct type" do
      assert Contains.type() == "Contains"
    end

    test "returns correct label" do
      assert Contains.label() == "Contains"
    end

    test "returns correct category" do
      assert Contains.category() == "Text"
    end

    test "returns correct description" do
      assert Contains.description() == "Checks if text contains a specified substring"
    end

    test "has correct input specification" do
      input_spec = Contains.input_spec()

      assert %{
               text: %{type: :string, label: "TEXT", multiline: true},
               search: %{type: :string, label: "SEARCH", default: ""}
             } = input_spec
    end

    test "has correct output specification" do
      output_spec = Contains.output_spec()
      assert %{result: %{type: :boolean, label: "RESULT"}} = output_spec
    end
  end

  describe "process/2" do
    test "returns true when substring is found" do
      assert {:ok, %{"result" => true}} =
               Contains.process(%{"text" => "Hello World", "search" => "World"}, %{})
    end

    test "returns false when substring is not found" do
      assert {:ok, %{"result" => false}} =
               Contains.process(%{"text" => "Hello World", "search" => "Galaxy"}, %{})
    end

    test "returns true for exact match" do
      assert {:ok, %{"result" => true}} =
               Contains.process(%{"text" => "Hello", "search" => "Hello"}, %{})
    end

    test "returns true for substring at beginning" do
      assert {:ok, %{"result" => true}} =
               Contains.process(%{"text" => "Hello World", "search" => "Hello"}, %{})
    end

    test "returns true for substring at end" do
      assert {:ok, %{"result" => true}} =
               Contains.process(%{"text" => "Hello World", "search" => "World"}, %{})
    end

    test "returns true for empty search string" do
      assert {:ok, %{"result" => true}} =
               Contains.process(%{"text" => "Hello World", "search" => ""}, %{})
    end

    test "returns true when both strings are empty" do
      assert {:ok, %{"result" => true}} =
               Contains.process(%{"text" => "", "search" => ""}, %{})
    end

    test "returns false when searching in empty text" do
      assert {:ok, %{"result" => false}} =
               Contains.process(%{"text" => "", "search" => "Hello"}, %{})
    end

    test "is case sensitive" do
      assert {:ok, %{"result" => false}} =
               Contains.process(%{"text" => "Hello World", "search" => "hello"}, %{})

      assert {:ok, %{"result" => false}} =
               Contains.process(%{"text" => "Hello World", "search" => "WORLD"}, %{})
    end

    test "handles special characters" do
      assert {:ok, %{"result" => true}} =
               Contains.process(%{"text" => "Hello, World!", "search" => "o, W"}, %{})
    end

    test "handles whitespace" do
      assert {:ok, %{"result" => true}} =
               Contains.process(%{"text" => "Hello World", "search" => " "}, %{})
    end

    test "uses config values when inputs not provided" do
      assert {:ok, %{"result" => true}} =
               Contains.process(%{}, %{"text" => "Config Test", "search" => "Config"})
    end

    test "prefers inputs over config" do
      assert {:ok, %{"result" => true}} =
               Contains.process(
                 %{"text" => "Input Test", "search" => "Input"},
                 %{"text" => "Config Test", "search" => "Config"}
               )
    end

    test "mixes input and config values" do
      assert {:ok, %{"result" => true}} =
               Contains.process(%{"text" => "Hello World"}, %{"search" => "World"})
    end

    test "uses defaults when neither input nor config provided" do
      assert {:ok, %{"result" => true}} = Contains.process(%{}, %{})
    end

    test "handles non-string inputs with to_string conversion" do
      assert {:ok, %{"result" => true}} =
               Contains.process(%{"text" => 12345, "search" => "23"}, %{})

      assert {:ok, %{"result" => true}} =
               Contains.process(%{"text" => 3.14159, "search" => "14"}, %{})
    end

    test "handles multiline text" do
      text = "Hello\nWorld\nTest"

      assert {:ok, %{"result" => true}} =
               Contains.process(%{"text" => text, "search" => "\n"}, %{})

      assert {:ok, %{"result" => true}} =
               Contains.process(%{"text" => text, "search" => "World\nTest"}, %{})
    end
  end
end
