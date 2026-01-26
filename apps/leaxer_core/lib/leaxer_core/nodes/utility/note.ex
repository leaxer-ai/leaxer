defmodule LeaxerCore.Nodes.Utility.Note do
  @moduledoc """
  A note node that displays text but does not execute or produce outputs.
  Used for documentation/annotation purposes in the graph.
  """
  use LeaxerCore.Nodes.Behaviour

  @impl true
  def type, do: "Note"

  @impl true
  def label, do: "Note"

  @impl true
  def category, do: "Utility/Display"

  @impl true
  def description, do: "A note for adding comments and documentation to your workflow"

  @impl true
  def input_spec do
    %{
      text: %{type: :string, label: "TEXT", default: "", multiline: true}
    }
  end

  @impl true
  def output_spec, do: %{}

  @impl true
  def process(_inputs, _config) do
    # Note node does nothing - it's purely visual
    {:ok, %{}}
  end
end
