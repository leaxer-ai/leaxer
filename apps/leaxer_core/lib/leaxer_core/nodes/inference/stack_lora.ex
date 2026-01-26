defmodule LeaxerCore.Nodes.Inference.StackLoRA do
  @moduledoc """
  Stack multiple LoRAs into a single output for use with GenerateImage.

  Allows combining multiple LoadLoRA outputs to enable multiple LoRA effects
  in a single image generation. sd.cpp supports multiple LoRA injection natively
  by adding multiple <lora:name:weight> tags to the prompt.
  """

  use LeaxerCore.Nodes.Behaviour

  @impl true
  def type, do: "StackLoRA"

  @impl true
  def label, do: "Stack LoRAs"

  @impl true
  def category, do: "Inference/Loaders"

  @impl true
  def description, do: "Combine multiple LoRAs for stacked effects"

  @impl true
  def input_spec do
    %{
      lora_1: %{type: :lora, label: "LORA 1"},
      lora_2: %{type: :lora, label: "LORA 2", optional: true},
      lora_3: %{type: :lora, label: "LORA 3", optional: true},
      lora_4: %{type: :lora, label: "LORA 4", optional: true}
    }
  end

  @impl true
  def output_spec do
    %{
      stacked_lora: %{type: :lora_stack, label: "STACKED LORAS"}
    }
  end

  @impl true
  def ui_component, do: {:custom, "StackLoRANode"}

  @impl true
  def process(inputs, _config) do
    # Collect all non-nil LoRA inputs
    loras =
      ["lora_1", "lora_2", "lora_3", "lora_4"]
      |> Enum.map(fn key -> inputs[key] end)
      |> Enum.filter(fn lora ->
        not is_nil(lora) and is_map(lora) and is_binary(Map.get(lora, :path))
      end)

    if length(loras) == 0 do
      {:error, "At least one LoRA input is required"}
    else
      # Create stacked LoRA structure
      stacked_lora = %{
        type: :lora_stack,
        loras: loras,
        count: length(loras)
      }

      {:ok, %{"stacked_lora" => stacked_lora}}
    end
  end
end
