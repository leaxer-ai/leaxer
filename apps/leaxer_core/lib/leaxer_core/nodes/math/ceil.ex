defmodule LeaxerCore.Nodes.Math.Ceil do
  @moduledoc """
  Math node that rounds a value up to the nearest integer.
  """
  use LeaxerCore.Nodes.Behaviour

  @impl true
  @spec type() :: String.t()
  def type, do: "Ceil"

  @impl true
  @spec label() :: String.t()
  def label, do: "Ceiling"

  @impl true
  @spec category() :: String.t()
  def category, do: "Math/Rounding"

  @impl true
  @spec description() :: String.t()
  def description, do: "Round a value up to the nearest integer"

  @impl true
  @spec input_spec() :: %{value: map()}
  def input_spec do
    %{
      value: %{type: :float, label: "VALUE", default: 0.0}
    }
  end

  @impl true
  @spec output_spec() :: %{result: map()}
  def output_spec do
    %{
      result: %{type: :integer, label: "RESULT"}
    }
  end

  @impl true
  @spec process(map(), map()) :: {:ok, %{String.t() => integer()}}
  def process(inputs, config) do
    value = inputs["value"] || config["value"] || 0.0
    {:ok, %{"result" => ceil(value)}}
  end
end
