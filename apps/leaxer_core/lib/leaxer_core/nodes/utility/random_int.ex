defmodule LeaxerCore.Nodes.Utility.RandomInt do
  @moduledoc """
  Generates a random integer within a specified range.
  """
  use LeaxerCore.Nodes.Behaviour
  alias LeaxerCore.Nodes.Helpers

  @impl true
  def type, do: "RandomInt"

  @impl true
  def label, do: "Random Integer"

  @impl true
  def category, do: "Utility/Random"

  @impl true
  def description, do: "Generates a random integer between min and max values"

  @impl true
  def input_spec do
    %{
      min: %{type: :integer, label: "MIN", default: 0},
      max: %{type: :integer, label: "MAX", default: 100}
    }
  end

  @impl true
  def output_spec do
    %{
      value: %{type: :integer, label: "VALUE"}
    }
  end

  @impl true
  def process(inputs, config) do
    min_val = Helpers.get_value("min", inputs, config, 0)
    max_val = Helpers.get_value("max", inputs, config, 100)

    min_int = trunc(min_val)
    max_int = trunc(max_val)

    result =
      if max_int > min_int do
        :rand.uniform(max_int - min_int + 1) + min_int - 1
      else
        min_int
      end

    {:ok, %{"value" => result}}
  end
end
