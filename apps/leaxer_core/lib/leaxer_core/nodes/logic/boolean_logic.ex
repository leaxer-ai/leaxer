defmodule LeaxerCore.Nodes.Logic.BooleanLogic do
  @moduledoc """
  Boolean logic operations.

  Ported from isekai-comfy-node's IsekaiBoolean.
  Supports: AND, OR, XOR, NOT, NAND, NOR
  Returns both boolean and integer results for flexible chaining.

  ## Examples

      iex> BooleanLogic.process(%{"a" => true, "b" => false, "operation" => "AND"}, %{})
      {:ok, %{"result" => false, "int_result" => 0}}
  """

  use LeaxerCore.Nodes.Behaviour
  alias LeaxerCore.Nodes.Helpers
  require Logger

  @impl true
  @spec type() :: String.t()
  def type, do: "BooleanLogic"

  @impl true
  @spec label() :: String.t()
  def label, do: "Boolean Logic"

  @impl true
  @spec category() :: String.t()
  def category, do: "Logic/Boolean"

  @impl true
  @spec description() :: String.t()
  def description, do: "Boolean operations (AND, OR, XOR, NOT, NAND, NOR)"

  @impl true
  @spec input_spec() :: %{a: map(), operation: map(), b: map()}
  def input_spec do
    %{
      a: %{
        type: :boolean,
        label: "A",
        default: false
      },
      operation: %{
        type: :enum,
        label: "OPERATION",
        default: "AND",
        options: [
          %{value: "AND", label: "AND"},
          %{value: "OR", label: "OR"},
          %{value: "XOR", label: "XOR"},
          %{value: "NOT", label: "NOT"},
          %{value: "NAND", label: "NAND"},
          %{value: "NOR", label: "NOR"}
        ]
      },
      b: %{
        type: :boolean,
        label: "B",
        default: false,
        optional: true,
        description: "Not used for NOT operation"
      }
    }
  end

  @impl true
  @spec output_spec() :: %{result: map(), int_result: map()}
  def output_spec do
    %{
      result: %{
        type: :boolean,
        label: "RESULT"
      },
      int_result: %{
        type: :integer,
        label: "INT RESULT",
        description: "1 for true, 0 for false"
      }
    }
  end

  @impl true
  @spec process(map(), map()) :: {:ok, %{String.t() => boolean() | integer()}}
  def process(inputs, config) do
    a = Helpers.get_value("a", inputs, config, false) |> Helpers.to_bool()
    b = Helpers.get_value("b", inputs, config, false) |> Helpers.to_bool()
    operation = Helpers.get_value("operation", inputs, config, "AND")

    result =
      case operation do
        "AND" -> a and b
        "OR" -> a or b
        # XOR: true if different
        "XOR" -> a != b
        "NOT" -> not a
        "NAND" -> not (a and b)
        "NOR" -> not (a or b)
        _ -> false
      end

    int_result = if result, do: 1, else: 0

    if operation == "NOT" do
      Logger.info("BooleanLogic: #{operation} #{a} = #{result}")
    else
      Logger.info("BooleanLogic: #{a} #{operation} #{b} = #{result}")
    end

    {:ok,
     %{
       "result" => result,
       "int_result" => int_result
     }}
  rescue
    e ->
      Logger.error("BooleanLogic exception: #{inspect(e)}")
      {:ok, %{"result" => false, "int_result" => 0}}
  end
end
