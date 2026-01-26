defmodule LeaxerCore.Nodes.Utility.PreviewText do
  @moduledoc """
  A node that displays text input for preview/debugging purposes.
  Similar to PreviewImage but for text content.
  """
  use LeaxerCore.Nodes.Behaviour
  alias LeaxerCore.Nodes.Helpers

  @impl true
  def type, do: "PreviewText"

  @impl true
  def label, do: "Preview Text"

  @impl true
  def category, do: "Utility/Display"

  @impl true
  def description, do: "Displays text content for preview and debugging"

  @impl true
  def ui_component, do: {:custom, "PreviewTextNode"}

  @impl true
  def input_spec do
    %{
      text: %{type: :string, label: "TEXT", multiline: true}
    }
  end

  @impl true
  def output_spec, do: %{}

  @impl true
  def process(inputs, config) do
    text = Helpers.get_value("text", inputs, config, "") |> to_string()
    # Return the text as preview data for the frontend to display
    {:ok, %{"preview" => text}}
  end
end
