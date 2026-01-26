defmodule LeaxerCore.Nodes.Dataset.ListLength do
  @moduledoc """
  Count items in a list.

  Essential for progress tracking and validation in batch workflows.

  ## Examples

      iex> ListLength.process(%{"list" => ["a", "b", "c"]}, %{})
      {:ok, %{"count" => 3}}
  """

  use LeaxerCore.Nodes.Behaviour
  require Logger

  @impl true
  def type, do: "ListLength"

  @impl true
  def label, do: "List Length"

  @impl true
  def category, do: "Data/List"

  @impl true
  def description, do: "Count items in a list"

  @impl true
  def input_spec do
    %{
      list: %{
        type: {:list, :string},
        label: "LIST",
        description: "List to count"
      }
    }
  end

  @impl true
  def output_spec do
    %{
      count: %{
        type: :integer,
        label: "COUNT",
        description: "Number of items in list"
      }
    }
  end

  @impl true
  def process(inputs, config) do
    list = inputs["list"] || config["list"] || []

    count =
      if is_list(list) do
        length(list)
      else
        0
      end

    {:ok, %{"count" => count}}
  rescue
    e ->
      Logger.error("ListLength exception: #{inspect(e)}")
      {:error, "Failed to count list: #{Exception.message(e)}"}
  end
end
