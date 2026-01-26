defmodule LeaxerCore.Nodes.Utility.RandomSeed do
  @moduledoc """
  Generates a random seed value for use with other nodes.
  """
  use LeaxerCore.Nodes.Behaviour

  @impl true
  def type, do: "RandomSeed"

  @impl true
  def label, do: "Random Seed"

  @impl true
  def category, do: "Utility/Random"

  @impl true
  def description, do: "Generates a random 64-bit seed value"

  @impl true
  def input_spec, do: %{}

  @impl true
  def output_spec do
    %{
      seed: %{type: :bigint, label: "SEED"}
    }
  end

  @impl true
  def process(_inputs, _config) do
    # Generate a random 64-bit seed
    seed = :rand.uniform(trunc(:math.pow(2, 63))) - 1
    {:ok, %{"seed" => seed}}
  end
end
