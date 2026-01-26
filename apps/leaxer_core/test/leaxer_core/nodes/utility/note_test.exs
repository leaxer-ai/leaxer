defmodule LeaxerCore.Nodes.Utility.NoteTest do
  use ExUnit.Case, async: true

  alias LeaxerCore.Nodes.Utility.Note

  describe "type/0" do
    test "returns correct type" do
      assert Note.type() == "Note"
    end
  end

  describe "label/0" do
    test "returns correct label" do
      assert Note.label() == "Note"
    end
  end

  describe "category/0" do
    test "returns correct category" do
      assert Note.category() == "Utility"
    end
  end

  describe "description/0" do
    test "returns correct description" do
      assert Note.description() == "A note for adding comments and documentation to your workflow"
    end
  end

  describe "input_spec/0" do
    test "returns correct input specification" do
      spec = Note.input_spec()

      assert spec == %{
               text: %{type: :string, label: "TEXT", default: "", multiline: true}
             }
    end
  end

  describe "output_spec/0" do
    test "returns empty output specification" do
      spec = Note.output_spec()
      assert spec == %{}
    end
  end

  describe "process/2" do
    test "returns empty map regardless of inputs or config" do
      inputs = %{"some" => "input"}
      config = %{"text" => "Some note text"}
      assert {:ok, %{}} = Note.process(inputs, config)
    end

    test "returns empty map with empty inputs and config" do
      assert {:ok, %{}} = Note.process(%{}, %{})
    end

    test "ignores all parameters and returns empty map" do
      inputs = %{"complex" => %{"nested" => "data"}}
      config = %{"text" => "This is a multiline\nnote with\nspecial characters!@#$%"}
      assert {:ok, %{}} = Note.process(inputs, config)
    end
  end
end
