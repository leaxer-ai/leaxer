defmodule LeaxerCore.Nodes.Logic.IfElse do
  use LeaxerCore.Nodes.Behaviour

  alias LeaxerCore.Nodes.Helpers

  @impl true
  def type, do: "IfElse"

  @impl true
  def label, do: "If/Else"

  @impl true
  def category, do: "Logic/Flow"

  @impl true
  def description, do: "Returns one of two values based on a boolean condition"

  @impl true
  def input_spec do
    %{
      condition: %{type: :boolean, label: "CONDITION", default: false, configurable: true},
      if_true: %{type: :any, label: "IF TRUE", configurable: false},
      if_false: %{type: :any, label: "IF FALSE", configurable: false}
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
    condition = Helpers.to_bool(inputs["condition"] || config["condition"])
    if_true = inputs["if_true"] || config["if_true"]
    if_false = inputs["if_false"] || config["if_false"]

    result = if condition, do: if_true, else: if_false
    {:ok, %{"result" => result}}
  end
end
