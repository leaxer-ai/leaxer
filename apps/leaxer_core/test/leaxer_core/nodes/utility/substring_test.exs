defmodule LeaxerCore.Nodes.Utility.SubstringTest do
  use ExUnit.Case

  alias LeaxerCore.Nodes.Utility.Substring

  describe "Substring node" do
    test "returns correct type" do
      assert Substring.type() == "Substring"
    end

    test "returns correct label" do
      assert Substring.label() == "Substring"
    end

    test "returns correct category" do
      assert Substring.category() == "Text/Manipulation"
    end

    test "returns correct description" do
      assert Substring.description() ==
               "Extracts a portion of text between start and end positions"
    end

    test "has correct input specification" do
      input_spec = Substring.input_spec()

      assert %{
               text: %{type: :string, label: "TEXT", default: "", multiline: true},
               start: %{type: :integer, label: "START", default: 0, min: 0},
               end: %{type: :integer, label: "END", default: 10, min: 0}
             } = input_spec
    end

    test "has correct output specification" do
      output_spec = Substring.output_spec()
      assert %{result: %{type: :string, label: "RESULT"}} = output_spec
    end
  end

  describe "process/2" do
    test "extracts substring from middle" do
      assert {:ok, %{"result" => "ello"}} =
               Substring.process(%{"text" => "Hello World", "start" => 1, "end" => 5}, %{})
    end

    test "extracts from beginning" do
      assert {:ok, %{"result" => "Hello"}} =
               Substring.process(%{"text" => "Hello World", "start" => 0, "end" => 5}, %{})
    end

    test "extracts to end" do
      assert {:ok, %{"result" => "World"}} =
               Substring.process(%{"text" => "Hello World", "start" => 6, "end" => 11}, %{})
    end

    test "handles entire string" do
      assert {:ok, %{"result" => "Hello World"}} =
               Substring.process(%{"text" => "Hello World", "start" => 0, "end" => 11}, %{})
    end

    test "handles empty result when start equals end" do
      assert {:ok, %{"result" => ""}} =
               Substring.process(%{"text" => "Hello World", "start" => 5, "end" => 5}, %{})
    end

    test "handles end beyond string length by using string length" do
      assert {:ok, %{"result" => "World"}} =
               Substring.process(%{"text" => "Hello World", "start" => 6, "end" => 100}, %{})
    end

    test "clamps negative start to 0" do
      assert {:ok, %{"result" => "Hello"}} =
               Substring.process(%{"text" => "Hello World", "start" => -5, "end" => 5}, %{})
    end

    test "handles start greater than end" do
      assert {:ok, %{"result" => ""}} =
               Substring.process(%{"text" => "Hello World", "start" => 10, "end" => 5}, %{})
    end

    test "uses config values when inputs not provided" do
      assert {:ok, %{"result" => "Test"}} =
               Substring.process(%{}, %{"text" => "Testing", "start" => 0, "end" => 4})
    end

    test "uses string length as default end when not provided" do
      assert {:ok, %{"result" => "World"}} =
               Substring.process(%{"text" => "Hello World", "start" => 6}, %{})
    end

    test "uses defaults when neither input nor config provided" do
      assert {:ok, %{"result" => ""}} = Substring.process(%{}, %{})
    end

    test "handles float indices by truncating" do
      assert {:ok, %{"result" => "ello"}} =
               Substring.process(%{"text" => "Hello World", "start" => 1.7, "end" => 5.9}, %{})
    end

    test "handles multiline text" do
      text = "Hello\nWorld\nTest"

      assert {:ok, %{"result" => "llo\nWor"}} =
               Substring.process(%{"text" => text, "start" => 2, "end" => 9}, %{})
    end
  end
end
