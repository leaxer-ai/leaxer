defmodule LeaxerCore.Nodes.LLM.Generate do
  @moduledoc """
  Generate text using a Large Language Model via llama.cpp.

  This node takes an LLM model and prompt, runs text generation via the LLM worker,
  and outputs the generated text string.
  """

  use LeaxerCore.Nodes.Behaviour

  @impl true
  def type, do: "LLMGenerate"

  @impl true
  def label, do: "LLM Generate"

  @impl true
  def category, do: "Inference/LLM"

  @impl true
  def description, do: "Generate text using a Large Language Model"

  @impl true
  def input_spec do
    %{
      llm: %{type: :llm, label: "LLM MODEL"},
      prompt: %{
        type: :string,
        label: "PROMPT",
        default: "",
        multiline: true,
        description: "Text prompt for generation"
      },
      max_tokens: %{
        type: :integer,
        label: "MAX TOKENS",
        default: 512,
        min: 1,
        max: 4096,
        step: 16,
        description: "Maximum tokens to generate"
      },
      temperature: %{
        type: :float,
        label: "TEMPERATURE",
        default: 0.7,
        min: 0.0,
        max: 2.0,
        step: 0.1,
        description: "Sampling temperature (0 = deterministic, higher = more creative)"
      },
      top_p: %{
        type: :float,
        label: "TOP-P",
        default: 0.9,
        min: 0.0,
        max: 1.0,
        step: 0.05,
        description: "Nucleus sampling cutoff probability"
      },
      top_k: %{
        type: :integer,
        label: "TOP-K",
        default: 40,
        min: 0,
        max: 100,
        step: 5,
        description: "Top-K sampling cutoff (0 = disabled)"
      },
      stop_sequences: %{
        type: :string,
        label: "STOP SEQUENCES",
        default: "",
        multiline: true,
        optional: true,
        description: "Stop sequences separated by newlines (optional)"
      }
    }
  end

  @impl true
  def output_spec do
    %{
      text: %{type: :string, label: "GENERATED TEXT"}
    }
  end

  @impl true
  def ui_component, do: {:custom, "LLMGenerateNode"}

  @impl true
  def process(inputs, config) do
    # Get LLM model from connected input or config
    llm_model =
      case inputs["llm"] do
        %{path: path} -> path
        path when is_binary(path) -> path
        _ -> config["llm"]
      end

    if is_nil(llm_model) or llm_model == "" do
      {:error, "No LLM model selected"}
    else
      prompt = inputs["prompt"] || config["prompt"] || ""

      if prompt == "" do
        {:error, "Prompt is required"}
      else
        # Extract generation parameters with validation
        max_tokens = validate_range(inputs["max_tokens"] || config["max_tokens"] || 512, 1, 4096)

        temperature =
          validate_range(inputs["temperature"] || config["temperature"] || 0.7, 0.0, 2.0)

        top_p = validate_range(inputs["top_p"] || config["top_p"] || 0.9, 0.0, 1.0)
        top_k = validate_range(inputs["top_k"] || config["top_k"] || 40, 0, 100)

        # Process stop sequences (split by newlines, filter empty)
        stop_sequences =
          case inputs["stop_sequences"] || config["stop_sequences"] do
            nil ->
              nil

            "" ->
              nil

            sequences when is_binary(sequences) ->
              sequences
              |> String.split("\n")
              |> Enum.map(&String.trim/1)
              |> Enum.reject(&(&1 == ""))
              |> case do
                [] -> nil
                list -> list
              end
          end

        opts = [
          model: llm_model,
          max_tokens: max_tokens,
          temperature: temperature,
          top_p: top_p,
          top_k: top_k,
          node_id: config["node_id"],
          job_id: config["job_id"]
        ]

        # Add stop sequences if provided
        opts =
          if stop_sequences, do: Keyword.put(opts, :stop_sequences, stop_sequences), else: opts

        case LeaxerCore.Workers.LLM.generate(prompt, opts) do
          {:ok, result} ->
            {:ok, %{"text" => result.text}}

          {:error, reason} ->
            {:error, reason}
        end
      end
    end
  end

  # Private helper to validate numeric ranges
  defp validate_range(value, min_val, max_val) do
    value
    |> max(min_val)
    |> min(max_val)
  end
end
