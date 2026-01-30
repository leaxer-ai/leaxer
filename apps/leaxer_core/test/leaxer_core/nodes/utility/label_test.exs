defmodule LeaxerCore.Nodes.Utility.LabelTest do
  use ExUnit.Case, async: true

  alias LeaxerCore.Nodes.Utility.Label

  describe "type/0" do
    test "returns correct type" do
      assert Label.type() == "Label"
    end
  end

  describe "label/0" do
    test "returns correct label" do
      assert Label.label() == "Label"
    end
  end

  describe "category/0" do
    test "returns correct category" do
      assert Label.category() == "Utility/Display"
    end
  end

  describe "description/0" do
    test "returns correct description" do
      assert Label.description() == "Visual section heading on canvas (no-op processing)"
    end
  end

  describe "input_spec/0" do
    test "returns correct input specification" do
      spec = Label.input_spec()

      assert spec == %{
               text: %{
                 type: :string,
                 label: "TEXT",
                 default: "Section Label",
                 description: "Label text for visual organization"
               },
               color: %{
                 type: :enum,
                 label: "COLOR",
                 default: "default",
                 options: [
                   %{value: "default", label: "Default"},
                   %{value: "red", label: "Red"},
                   %{value: "blue", label: "Blue"},
                   %{value: "green", label: "Green"},
                   %{value: "yellow", label: "Yellow"},
                   %{value: "purple", label: "Purple"}
                 ],
                 description: "Label color"
               }
             }
    end

    test "includes all expected color options" do
      spec = Label.input_spec()
      color_options = spec.color.options

      expected_values = ["default", "red", "blue", "green", "yellow", "purple"]
      actual_values = Enum.map(color_options, & &1.value)

      assert actual_values == expected_values
    end
  end

  describe "output_spec/0" do
    test "returns empty output specification" do
      spec = Label.output_spec()
      assert spec == %{}
    end
  end

  describe "process/2" do
    test "returns empty map regardless of inputs or config" do
      inputs = %{"some" => "input"}
      config = %{"text" => "My Label", "color" => "blue"}
      assert {:ok, %{}} = Label.process(inputs, config)
    end

    test "returns empty map with empty inputs and config" do
      assert {:ok, %{}} = Label.process(%{}, %{})
    end

    test "ignores all parameters and returns empty map" do
      inputs = %{"complex" => %{"nested" => "data"}}

      config = %{
        "text" => "Section: Data Processing",
        "color" => "green"
      }

      assert {:ok, %{}} = Label.process(inputs, config)
    end

    test "documented example works correctly" do
      # From the module documentation
      assert {:ok, %{}} = Label.process(%{}, %{"text" => "Input Section", "color" => "blue"})
    end
  end
end
