defmodule LeaxerCore.Nodes.Math.MapRange do
  use LeaxerCore.Nodes.Behaviour

  @impl true
  def type, do: "MapRange"

  @impl true
  def label, do: "Map Range"

  @impl true
  def category, do: "Math/Range"

  @impl true
  def description, do: "Remap a value from one range to another"

  @impl true
  def input_spec do
    %{
      value: %{type: :float, label: "VALUE", default: 0.0},
      in_min: %{type: :float, label: "IN MIN", default: 0.0},
      in_max: %{type: :float, label: "IN MAX", default: 1.0},
      out_min: %{type: :float, label: "OUT MIN", default: 0.0},
      out_max: %{type: :float, label: "OUT MAX", default: 1.0}
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
    in_min = inputs["in_min"] || config["in_min"] || 0.0
    in_max = inputs["in_max"] || config["in_max"] || 1.0
    out_min = inputs["out_min"] || config["out_min"] || 0.0
    out_max = inputs["out_max"] || config["out_max"] || 1.0

    # Avoid division by zero
    if in_max == in_min do
      {:ok, %{"result" => out_min}}
    else
      # Linear interpolation: (value - in_min) / (in_max - in_min) * (out_max - out_min) + out_min
      normalized = (value - in_min) / (in_max - in_min)
      result = normalized * (out_max - out_min) + out_min
      {:ok, %{"result" => result}}
    end
  end
end
