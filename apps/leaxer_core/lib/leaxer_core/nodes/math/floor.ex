defmodule LeaxerCore.Nodes.Math.Floor do
  @moduledoc """
  Math node that rounds a value down to the nearest integer.
  """
  use LeaxerCore.Nodes.Behaviour

  @impl true
  @spec type() :: String.t()
  def type, do: "Floor"

  @impl true
  @spec label() :: String.t()
  def label, do: "Floor"

  @impl true
  @spec category() :: String.t()
  def category, do: "Math/Rounding"

  @impl true
  @spec description() :: String.t()
  def description, do: "Round a value down to the nearest integer"

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
    {:ok, %{"result" => floor(value)}}
  end
end
