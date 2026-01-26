defmodule LeaxerCore.Nodes.Logic.And do
  @moduledoc """
  Logical AND node that returns true if both inputs are true.
  """
  use LeaxerCore.Nodes.Behaviour

  alias LeaxerCore.Nodes.Helpers

  @impl true
  @spec type() :: String.t()
  def type, do: "And"

  @impl true
  @spec label() :: String.t()
  def label, do: "And"

  @impl true
  @spec category() :: String.t()
  def category, do: "Logic/Boolean"

  @impl true
  @spec description() :: String.t()
  def description, do: "Returns true if both inputs are true (logical AND)"

  @impl true
  @spec input_spec() :: %{a: map(), b: map()}
  def input_spec do
    %{
      a: %{type: :boolean, label: "A", default: false, configurable: true},
      b: %{type: :boolean, label: "B", default: false, configurable: true}
    }
  end

  @impl true
  @spec output_spec() :: %{result: map()}
  def output_spec do
    %{
      result: %{type: :boolean, label: "RESULT"}
    }
  end

  @impl true
  @spec process(map(), map()) :: {:ok, %{String.t() => boolean()}}
  def process(inputs, config) do
    a = Helpers.get_value("a", inputs, config, false) |> Helpers.to_bool()
    b = Helpers.get_value("b", inputs, config, false) |> Helpers.to_bool()
    {:ok, %{"result" => a and b}}
  end
end
