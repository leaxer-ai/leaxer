defmodule LeaxerCore.Nodes.Utility.Substring do
  @moduledoc """
  Extracts a portion of a string based on start and end indices.
  """
  use LeaxerCore.Nodes.Behaviour
  alias LeaxerCore.Nodes.Helpers

  @impl true
  @spec type() :: String.t()
  def type, do: "Substring"

  @impl true
  @spec label() :: String.t()
  def label, do: "Substring"

  @impl true
  @spec category() :: String.t()
  def category, do: "Text/Manipulation"

  @impl true
  @spec description() :: String.t()
  def description, do: "Extracts a portion of text between start and end positions"

  @impl true
  @spec input_spec() :: %{text: map(), start: map(), end: map()}
  def input_spec do
    %{
      text: %{type: :string, label: "TEXT", default: "", multiline: true},
      start: %{type: :integer, label: "START", default: 0, min: 0},
      end: %{type: :integer, label: "END", default: 10, min: 0}
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
    start_idx = Helpers.get_value("start", inputs, config, 0)
    end_idx = Helpers.get_value("end", inputs, config, String.length(text))

    start_int = max(0, trunc(start_idx))
    end_int = trunc(end_idx)
    length = max(0, end_int - start_int)

    result = String.slice(text, start_int, length)
    {:ok, %{"result" => result}}
  end
end
