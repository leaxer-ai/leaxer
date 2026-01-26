defmodule LeaxerCore.Nodes.LLM.PromptEnhance do
  @moduledoc """
  Enhance basic prompts into detailed image generation prompts using LLM.

  This node takes an LLM model, a basic text prompt, and a style preference,
  then uses a system prompt to transform the basic description into a detailed,
  rich prompt suitable for image generation models.
  """

  use LeaxerCore.Nodes.Behaviour

  @impl true
  def type, do: "LLMPromptEnhance"

  @impl true
  def label, do: "LLM Prompt Enhance"

  @impl true
  def category, do: "Inference/LLM"

  @impl true
  def description, do: "Enhance basic prompts into detailed image generation prompts"

  @impl true
  def input_spec do
    %{
      llm: %{type: :llm, label: "LLM MODEL"},
      basic_prompt: %{
        type: :string,
        label: "BASIC PROMPT",
        default: "",
        multiline: true,
        description: "Simple description to enhance"
      },
      style: %{
        type: :enum,
        label: "STYLE",
        default: "photorealistic",
        options: [
          %{value: "photorealistic", label: "Photorealistic"},
          %{value: "artistic", label: "Artistic"},
          %{value: "anime", label: "Anime"},
          %{value: "abstract", label: "Abstract"}
        ],
        description: "Target style for the enhanced prompt"
      }
    }
  end

  @impl true
  def output_spec do
    %{
      enhanced_prompt: %{type: :string, label: "ENHANCED PROMPT"}
    }
  end

  @impl true
  def ui_component, do: {:custom, "LLMPromptEnhanceNode"}

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
      basic_prompt = inputs["basic_prompt"] || config["basic_prompt"] || ""

      if basic_prompt == "" do
        {:error, "Basic prompt is required"}
      else
        style = inputs["style"] || config["style"] || "photorealistic"

        # Build the enhancement prompt using system prompt
        enhancement_prompt = build_enhancement_prompt(basic_prompt, style)

        opts = [
          model: llm_model,
          max_tokens: 512,
          temperature: 0.7,
          top_p: 0.9,
          top_k: 40,
          node_id: config["node_id"],
          job_id: config["job_id"]
        ]

        case LeaxerCore.Workers.LLM.generate(enhancement_prompt, opts) do
          {:ok, result} ->
            # Clean up the result text (remove quotes, extra whitespace)
            enhanced_prompt = clean_enhanced_prompt(result.text)
            {:ok, %{"enhanced_prompt" => enhanced_prompt}}

          {:error, reason} ->
            {:error, reason}
        end
      end
    end
  end

  # Build the enhancement prompt based on style
  defp build_enhancement_prompt(basic_prompt, style) do
    style_instructions = get_style_instructions(style)

    """
    You are an expert prompt engineer for AI image generation models. Your task is to enhance a basic description into a detailed, high-quality prompt that will produce excellent results.

    Style: #{style}
    #{style_instructions}

    Basic description: "#{basic_prompt}"

    Transform this basic description into a detailed, descriptive prompt. Include:
    - Specific visual details and composition
    - Lighting and atmosphere
    - Technical quality markers
    - Style-appropriate descriptors

    Output only the enhanced prompt, no explanations or quotes:
    """
  end

  # Get style-specific instructions
  defp get_style_instructions(style) do
    case style do
      "photorealistic" ->
        """
        Focus on photographic realism. Include camera settings, lighting conditions, and technical photography terms.
        Use terms like: professional photography, high resolution, detailed, realistic lighting, sharp focus, DSLR quality.
        """

      "artistic" ->
        """
        Emphasize artistic composition and creative visual elements. Include art movements, techniques, and aesthetic qualities.
        Use terms like: artistic composition, painterly, expressive, creative lighting, masterpiece, fine art, visual harmony.
        """

      "anime" ->
        """
        Focus on anime and manga art style characteristics. Include anime-specific visual elements and aesthetics.
        Use terms like: anime style, manga art, vibrant colors, expressive eyes, clean lines, cel shading, Japanese animation.
        """

      "abstract" ->
        """
        Emphasize abstract and conceptual visual elements. Include non-representational forms and artistic concepts.
        Use terms like: abstract art, conceptual, geometric forms, color theory, composition, non-representational, artistic interpretation.
        """

      _ ->
        "Focus on creating a detailed, visually rich description suitable for image generation."
    end
  end

  # Clean up the LLM output
  defp clean_enhanced_prompt(text) do
    text
    |> String.trim()
    # Remove surrounding quotes
    |> String.replace(~r/^["']|["']$/, "")
    # Normalize whitespace
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end
end
