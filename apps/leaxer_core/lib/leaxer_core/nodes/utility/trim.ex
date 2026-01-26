defmodule LeaxerCore.Nodes.Utility.Trim do
  @moduledoc """
  Removes leading and trailing whitespace from a string.
  """
  use LeaxerCore.Nodes.Behaviour
  alias LeaxerCore.Nodes.Helpers

  @impl true
  @spec type() :: String.t()
  def type, do: "Trim"

  @impl true
  @spec label() :: String.t()
  def label, do: "Trim"

  @impl true
  @spec category() :: String.t()
  def category, do: "Text/Manipulation"

  @impl true
  @spec description() :: String.t()
  def description, do: "Removes leading and trailing whitespace from text"

  @impl true
  @spec input_spec() :: %{text: map()}
  def input_spec do
    %{
      text: %{type: :string, label: "TEXT", multiline: true}
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
    text = Helpers.get_value("text", inputs, config, "") |> to_string()
    result = String.trim(text)
    {:ok, %{"result" => result}}
  end
end
