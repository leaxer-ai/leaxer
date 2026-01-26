defmodule LeaxerCore.Nodes.Utility.Label do
  @moduledoc """
  Visual section heading on canvas (no-op processing).

  Large workflows need visual sections - better than Note for pure annotation.
  This node has no inputs/outputs and is purely for visual organization.

  ## Examples

      iex> Label.process(%{}, %{"text" => "Input Section", "color" => "blue"})
      {:ok, %{}}
  """

  use LeaxerCore.Nodes.Behaviour
  require Logger

  @impl true
  def type, do: "Label"

  @impl true
  def label, do: "Label"

  @impl true
  def category, do: "Utility/Display"

  @impl true
  def description, do: "Visual section heading on canvas (no-op processing)"

  @impl true
  def input_spec do
    %{
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

  @impl true
  def output_spec do
    %{}
  end

  @impl true
  def process(_inputs, _config) do
    # Pure annotation node - no actual processing
    {:ok, %{}}
  end
end
