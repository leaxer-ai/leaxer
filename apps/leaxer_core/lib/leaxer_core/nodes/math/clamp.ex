defmodule LeaxerCore.Nodes.Math.Clamp do
  use LeaxerCore.Nodes.Behaviour

  @impl true
  def type, do: "Clamp"

  @impl true
  def label, do: "Clamp"

  @impl true
  def category, do: "Math/Range"

  @impl true
  def description, do: "Constrain a value between minimum and maximum bounds"

  @impl true
  def input_spec do
    %{
      value: %{type: :float, label: "VALUE", default: 0.0},
      min: %{type: :float, label: "MIN", default: 0.0},
      max: %{type: :float, label: "MAX", default: 1.0}
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
    min_val = inputs["min"] || config["min"] || 0.0
    max_val = inputs["max"] || config["max"] || 1.0

    result = value |> max(min_val) |> min(max_val)
    {:ok, %{"result" => result}}
  end
end
