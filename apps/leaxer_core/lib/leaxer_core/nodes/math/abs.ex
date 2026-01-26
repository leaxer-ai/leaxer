defmodule LeaxerCore.Nodes.Math.Abs do
  @moduledoc """
  Math node that returns the absolute value of a number.
  """
  use LeaxerCore.Nodes.Behaviour
  alias LeaxerCore.Nodes.Helpers

  @impl true
  @spec type() :: String.t()
  def type, do: "Abs"

  @impl true
  @spec label() :: String.t()
  def label, do: "Absolute Value"

  @impl true
  @spec category() :: String.t()
  def category, do: "Math/Range"

  @impl true
  @spec description() :: String.t()
  def description, do: "Return the absolute value of a number"

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
      result: %{type: :float, label: "RESULT"}
    }
  end

  @impl true
  @spec process(map(), map()) :: {:ok, %{String.t() => number()}}
  def process(inputs, config) do
    value = Helpers.get_value("value", inputs, config, 0.0)
    {:ok, %{"result" => abs(value)}}
  end
end
