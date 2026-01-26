defmodule LeaxerCore.Nodes.Math.OneMinus do
  use LeaxerCore.Nodes.Behaviour

  @impl true
  def type, do: "OneMinus"

  @impl true
  def label, do: "One Minus"

  @impl true
  def category, do: "Math/Range"

  @impl true
  def description, do: "Subtract a value from one (1 - x)"

  @impl true
  def input_spec do
    %{
      value: %{type: :float, label: "VALUE", default: 0.0}
    }
  end

  @impl true
  def output_spec do
    %{
      result: %{type: :float, label: "RESULT"}
    }
  end

  @impl true
  def process(inputs, config) do
    value = inputs["value"] || config["value"] || 0.0
    {:ok, %{"result" => 1.0 - value}}
  end
end
