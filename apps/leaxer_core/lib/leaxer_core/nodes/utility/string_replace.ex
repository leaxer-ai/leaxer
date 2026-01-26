defmodule LeaxerCore.Nodes.Utility.StringReplace do
  @moduledoc """
  Replaces occurrences of a substring with another string.
  """
  use LeaxerCore.Nodes.Behaviour
  alias LeaxerCore.Nodes.Helpers

  @impl true
  def type, do: "StringReplace"

  @impl true
  def label, do: "String Replace"

  @impl true
  def category, do: "Text/Manipulation"

  @impl true
  def description, do: "Replaces all occurrences of a substring with a replacement"

  @impl true
  def input_spec do
    %{
      text: %{type: :string, label: "TEXT", default: "", multiline: true},
      find: %{type: :string, label: "FIND", default: ""},
      replace: %{type: :string, label: "REPLACE", default: ""}
    }
  end

  @impl true
  def output_spec do
    %{
      result: %{type: :string, label: "RESULT"}
    }
  end

  @impl true
  def process(inputs, config) do
    text = Helpers.get_value("text", inputs, config, "") |> to_string()
    find = Helpers.get_value("find", inputs, config, "") |> to_string()
    replace = Helpers.get_value("replace", inputs, config, "") |> to_string()

    result = String.replace(text, find, replace)
    {:ok, %{"result" => result}}
  end
end
