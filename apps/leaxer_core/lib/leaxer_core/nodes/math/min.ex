defmodule LeaxerCore.Nodes.Math.Min do
  @moduledoc """
  Math node that returns the smaller of two values.
  """
  use LeaxerCore.Nodes.Behaviour

  @impl true
  @spec type() :: String.t()
  def type, do: "Min"

  @impl true
  @spec label() :: String.t()
  def label, do: "Minimum"

  @impl true
  @spec category() :: String.t()
  def category, do: "Math/Range"

  @impl true
  @spec description() :: String.t()
  def description, do: "Return the smaller of two values"

  @impl true
  @spec input_spec() :: %{a: map(), b: map()}
  def input_spec do
    %{
      a: %{type: :float, label: "A", default: 0.0},
      b: %{type: :float, label: "B", default: 0.0}
    }
  end

  @impl true
  @spec output_spec() :: %{result: map()}
  def output_spec do
    %{
      result: %{type: :float, label: "RESULT"}
    }
  end

  @impl true
  @spec process(map(), map()) :: {:ok, %{String.t() => number()}}
  def process(inputs, config) do
    a = inputs["a"] || config["a"] || 0.0
    b = inputs["b"] || config["b"] || 0.0
    {:ok, %{"result" => min(a, b)}}
  end
end
