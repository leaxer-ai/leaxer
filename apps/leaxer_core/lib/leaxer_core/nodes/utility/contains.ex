defmodule LeaxerCore.Nodes.Utility.Contains do
  @moduledoc """
  Checks if a string contains a specified substring.
  """
  use LeaxerCore.Nodes.Behaviour
  alias LeaxerCore.Nodes.Helpers

  @impl true
  @spec type() :: String.t()
  def type, do: "Contains"

  @impl true
  @spec label() :: String.t()
  def label, do: "Contains"

  @impl true
  @spec category() :: String.t()
  def category, do: "Text/Regex"

  @impl true
  @spec description() :: String.t()
  def description, do: "Checks if text contains a specified substring"

  @impl true
  @spec input_spec() :: %{text: map(), search: map()}
  def input_spec do
    %{
      text: %{type: :string, label: "TEXT", multiline: true},
      search: %{type: :string, label: "SEARCH", default: ""}
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
    text = Helpers.get_value("text", inputs, config, "") |> to_string()
    search = Helpers.get_value("search", inputs, config, "") |> to_string()

    result = String.contains?(text, search)
    {:ok, %{"result" => result}}
  end
end
