defmodule LeaxerCore.Nodes.Utility.Concat do
  @moduledoc """
  Concatenates two strings together.
  """
  use LeaxerCore.Nodes.Behaviour
  alias LeaxerCore.Nodes.Helpers

  @impl true
  @spec type() :: String.t()
  def type, do: "Concat"

  @impl true
  @spec label() :: String.t()
  def label, do: "Concatenate"

  @impl true
  @spec category() :: String.t()
  def category, do: "Text/Manipulation"

  @impl true
  @spec description() :: String.t()
  def description, do: "Joins two strings together"

  @impl true
  @spec input_spec() :: %{a: map(), b: map()}
  def input_spec do
    %{
      a: %{type: :string, label: "A", default: ""},
      b: %{type: :string, label: "B", default: ""}
    }
  end

  @impl true
  @spec output_spec() :: %{result: map()}
  def output_spec do
    %{
      result: %{type: :string, label: "RESULT"}
    }
  end

  @impl true
  @spec process(map(), map()) :: {:ok, %{String.t() => String.t()}}
  def process(inputs, config) do
    a = Helpers.get_value("a", inputs, config, "") |> to_string()
    b = Helpers.get_value("b", inputs, config, "") |> to_string()
    {:ok, %{"result" => a <> b}}
  end
end
