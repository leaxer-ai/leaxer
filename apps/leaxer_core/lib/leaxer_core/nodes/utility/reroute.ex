defmodule LeaxerCore.Nodes.Utility.Reroute do
  @moduledoc """
  Pass-through node to organize edge routing.

  Prevents spaghetti connections in large workflows.
  Industry standard in node-based tools.

  ## Examples

      iex> Reroute.process(%{"value" => "anything"}, %{})
      {:ok, %{"value" => "anything"}}
  """

  use LeaxerCore.Nodes.Behaviour
  require Logger

  @impl true
  def type, do: "Reroute"

  @impl true
  def label, do: "Reroute"

  @impl true
  def category, do: "Utility/Flow"

  @impl true
  def description, do: "Pass-through to organize edge routing"

  @impl true
  def input_spec do
    %{
      value: %{
        type: :any,
        label: "VALUE",
        description: "Any value to pass through"
      }
    }
  end

  @impl true
  def output_spec do
    %{
      value: %{
        type: :any,
        label: "VALUE",
        description: "Same value as input"
      }
    }
  end

  @impl true
  def process(inputs, _config) do
    # Simple pass-through
    {:ok, inputs}
  end
end
