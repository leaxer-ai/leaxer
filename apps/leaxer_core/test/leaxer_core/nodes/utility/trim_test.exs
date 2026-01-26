defmodule LeaxerCore.Nodes.Utility.TrimTest do
  use ExUnit.Case

  alias LeaxerCore.Nodes.Utility.Trim

  describe "Trim node" do
    test "returns correct type" do
      assert Trim.type() == "Trim"
    end

    test "returns correct label" do
      assert Trim.label() == "Trim"
    end

    test "returns correct category" do
      assert Trim.category() == "Text"
    end

    test "returns correct description" do
      assert Trim.description() == "Removes leading and trailing whitespace from text"
    end

    test "has correct input specification" do
      input_spec = Trim.input_spec()
      assert %{text: %{type: :string, label: "TEXT", multiline: true}} = input_spec
    end

    test "has correct output specification" do
      output_spec = Trim.output_spec()
      assert %{result: %{type: :string, label: "RESULT"}} = output_spec
    end
  end

  describe "process/2" do
    test "removes leading whitespace" do
      assert {:ok, %{"result" => "Hello World"}} =
               Trim.process(%{"text" => "   Hello World"}, %{})
    end

    test "removes trailing whitespace" do
      assert {:ok, %{"result" => "Hello World"}} =
               Trim.process(%{"text" => "Hello World   "}, %{})
    end

    test "removes leading and trailing whitespace" do
      assert {:ok, %{"result" => "Hello World"}} =
               Trim.process(%{"text" => "   Hello World   "}, %{})
    end

    test "preserves internal whitespace" do
      assert {:ok, %{"result" => "Hello   World"}} =
               Trim.process(%{"text" => "  Hello   World  "}, %{})
    end

    test "handles string with only whitespace" do
      assert {:ok, %{"result" => ""}} =
               Trim.process(%{"text" => "   \t\n  "}, %{})
    end

    test "handles empty string" do
      assert {:ok, %{"result" => ""}} =
               Trim.process(%{"text" => ""}, %{})
    end

    test "handles string with no whitespace" do
      assert {:ok, %{"result" => "HelloWorld"}} =
               Trim.process(%{"text" => "HelloWorld"}, %{})
    end

    test "removes various types of whitespace" do
      assert {:ok, %{"result" => "Hello World"}} =
               Trim.process(%{"text" => " \t\n\r Hello World \t\n\r "}, %{})
    end

    test "uses config value when input not provided" do
      assert {:ok, %{"result" => "Config Test"}} =
               Trim.process(%{}, %{"text" => "  Config Test  "})
    end

    test "prefers input over config" do
      assert {:ok, %{"result" => "Input Test"}} =
               Trim.process(%{"text" => "  Input Test  "}, %{"text" => "  Config Test  "})
    end

    test "uses empty string default when neither input nor config provided" do
      assert {:ok, %{"result" => ""}} = Trim.process(%{}, %{})
    end

    test "handles non-string input with to_string conversion" do
      assert {:ok, %{"result" => "123"}} =
               Trim.process(%{"text" => 123}, %{})
    end

    test "handles multiline text" do
      text = "  \n  Hello\n  World  \n  "

      assert {:ok, %{"result" => "Hello\n  World"}} =
               Trim.process(%{"text" => text}, %{})
    end
  end
end
