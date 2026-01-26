defmodule LeaxerCore.Nodes.Logic.Switch do
  @moduledoc """
  Switch node that selects from multiple inputs based on an index.
  Supports up to 4 case inputs (case_0, case_1, case_2, case_3).
  """
  use LeaxerCore.Nodes.Behaviour
  alias LeaxerCore.Nodes.Helpers

  @impl true
  def type, do: "Switch"

  @impl true
  def label, do: "Switch"

  @impl true
  def category, do: "Logic/Flow"

  @impl true
  def description, do: "Selects one of multiple values based on an index (0-3)"

  @impl true
  def input_spec do
    %{
      index: %{type: :integer, label: "INDEX", default: 0, min: 0, max: 3, configurable: true},
      case_0: %{type: :any, label: "CASE 0", configurable: false},
      case_1: %{type: :any, label: "CASE 1", configurable: false},
      case_2: %{type: :any, label: "CASE 2", configurable: false},
      case_3: %{type: :any, label: "CASE 3", configurable: false}
    }
  end

  @impl true
  def output_spec do
    %{
      result: %{type: :any, label: "RESULT"}
    }
  end

  @impl true
  def process(inputs, config) do
    index = Helpers.get_value("index", inputs, config, 0)
    index_int = trunc(index)

    # Get the case value based on index (0-3)
    result =
      case index_int do
        0 -> Helpers.get_value("case_0", inputs, config, nil)
        1 -> Helpers.get_value("case_1", inputs, config, nil)
        2 -> Helpers.get_value("case_2", inputs, config, nil)
        3 -> Helpers.get_value("case_3", inputs, config, nil)
        # Default to first case
        _ -> Helpers.get_value("case_0", inputs, config, nil)
      end

    {:ok, %{"result" => result}}
  end
end
