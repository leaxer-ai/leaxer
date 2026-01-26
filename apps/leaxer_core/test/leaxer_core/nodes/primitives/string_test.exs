defmodule LeaxerCore.Nodes.Primitives.StringTest do
  use ExUnit.Case, async: true

  alias LeaxerCore.Nodes.Primitives.String

  describe "type/0" do
    test "returns correct type" do
      assert String.type() == "String"
    end
  end

  describe "label/0" do
    test "returns correct label" do
      assert String.label() == "String"
    end
  end

  describe "category/0" do
    test "returns correct category" do
      assert String.category() == "Primitives"
    end
  end

  describe "description/0" do
    test "returns correct description" do
      assert String.description() == "A constant string value"
    end
  end

  describe "input_spec/0" do
    test "returns correct input specification" do
      spec = String.input_spec()

      assert spec == %{
               value: %{type: :string, label: "VALUE", default: "", multiline: true}
             }
    end
  end

  describe "output_spec/0" do
    test "returns correct output specification" do
      spec = String.output_spec()

      assert spec == %{
               value: %{type: :string, label: "VALUE"}
             }
    end
  end

  describe "process/2" do
    test "returns value from config when provided" do
      config = %{"value" => "hello world"}
      assert {:ok, %{"value" => "hello world"}} = String.process(%{}, config)
    end

    test "returns empty string when value is nil in config" do
      config = %{"value" => nil}
      assert {:ok, %{"value" => ""}} = String.process(%{}, config)
    end

    test "returns empty string when value key is missing from config" do
      config = %{}
      assert {:ok, %{"value" => ""}} = String.process(%{}, config)
    end

    test "handles multiline strings" do
      config = %{"value" => "line 1\nline 2\nline 3"}
      assert {:ok, %{"value" => "line 1\nline 2\nline 3"}} = String.process(%{}, config)
    end

    test "handles special characters" do
      config = %{"value" => "Hello! @#$%^&*()"}
      assert {:ok, %{"value" => "Hello! @#$%^&*()"}} = String.process(%{}, config)
    end

    test "handles unicode characters" do
      config = %{"value" => "🚀 Hello 世界"}
      assert {:ok, %{"value" => "🚀 Hello 世界"}} = String.process(%{}, config)
    end

    test "ignores inputs parameter" do
      inputs = %{"ignored" => "value"}
      config = %{"value" => "test"}
      assert {:ok, %{"value" => "test"}} = String.process(inputs, config)
    end
  end
end
