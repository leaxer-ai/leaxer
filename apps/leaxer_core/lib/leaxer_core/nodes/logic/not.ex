defmodule LeaxerCore.Nodes.Logic.Not do
  @moduledoc """
  Logical NOT node that returns the inverse of the input value.
  """
  use LeaxerCore.Nodes.Behaviour

  alias LeaxerCore.Nodes.Helpers

  @impl true
  @spec type() :: String.t()
  def type, do: "Not"

  @impl true
  @spec label() :: String.t()
  def label, do: "Not"

  @impl true
  @spec category() :: String.t()
  def category, do: "Logic/Boolean"

  @impl true
  @spec description() :: String.t()
  def description, do: "Returns the logical inverse of the input (logical NOT)"

  @impl true
  @spec input_spec() :: %{value: map()}
  def input_spec do
    %{
      value: %{type: :boolean, label: "VALUE", default: false, configurable: true}
    }
  end

  @impl true
  @spec output_spec() :: %{result: map()}
  def output_spec do
    %{
      result: %{type: :boolean, label: "RESULT"}
    }
  end

  @impl true
  @spec process(map(), map()) :: {:ok, %{String.t() => boolean()}}
  def process(inputs, config) do
    value = Helpers.get_value("value", inputs, config, false) |> Helpers.to_bool()
    {:ok, %{"result" => not value}}
  end
end
