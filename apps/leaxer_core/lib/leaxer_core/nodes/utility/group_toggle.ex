defmodule LeaxerCore.Nodes.Utility.GroupToggle do
  @moduledoc """
  Enable/disable entire branches.

  Essential for A/B testing workflows and conditional execution.

  ## Examples

      iex> GroupToggle.process(%{"value" => "data", "enabled" => true}, %{})
      {:ok, %{"value" => "data"}}

      iex> GroupToggle.process(%{"value" => "data", "enabled" => false}, %{})
      {:ok, %{"value" => nil}}
  """

  use LeaxerCore.Nodes.Behaviour
  require Logger

  @impl true
  def type, do: "GroupToggle"

  @impl true
  def label, do: "Group Toggle"

  @impl true
  def category, do: "Utility/Flow"

  @impl true
  def description, do: "Enable/disable entire branches"

  @impl true
  def input_spec do
    %{
      value: %{
        type: :any,
        label: "VALUE",
        description: "Value to pass through or block"
      },
      enabled: %{
        type: :boolean,
        label: "ENABLED",
        default: true,
        description: "Enable or disable this branch"
      }
    }
  end

  @impl true
  def output_spec do
    %{
      value: %{
        type: :any,
        label: "VALUE",
        description: "Value if enabled, nil if disabled"
      }
    }
  end

  @impl true
  def process(inputs, config) do
    value = inputs["value"]
    enabled = inputs["enabled"] || config["enabled"] || true

    if enabled do
      {:ok, %{"value" => value}}
    else
      {:ok, %{"value" => nil}}
    end
  end
end
