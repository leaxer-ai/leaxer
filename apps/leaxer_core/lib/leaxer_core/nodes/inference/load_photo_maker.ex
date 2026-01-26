defmodule LeaxerCore.Nodes.Inference.LoadPhotoMaker do
  @moduledoc """
  Load a PhotoMaker model for personalized image generation.

  PhotoMaker is a method for customizing realistic human photos via stacked
  ID embedding. This node allows loading PhotoMaker models with configurable
  identity images directory and style strength settings.

  Note: PhotoMaker requires SDXL-based models for proper functionality.
  """

  use LeaxerCore.Nodes.Behaviour

  @impl true
  def type, do: "LoadPhotoMaker"

  @impl true
  def label, do: "Load PhotoMaker"

  @impl true
  def category, do: "Inference/Loaders"

  @impl true
  def description, do: "Load a PhotoMaker model for personalized image generation (SDXL only)"

  @impl true
  def input_spec do
    %{
      model_path: %{
        type: :string,
        label: "MODEL PATH",
        default: "",
        description: "Path to PhotoMaker model file"
      },
      id_images_dir: %{
        type: :string,
        label: "ID IMAGES DIR",
        default: "",
        description: "Directory containing identity images for the subject"
      },
      style_strength: %{
        type: :integer,
        label: "STYLE STRENGTH",
        default: 20,
        min: 0,
        max: 100,
        step: 5,
        description: "Style strength percentage (0-100)"
      },
      id_embed_path: %{
        type: :string,
        label: "ID EMBED PATH",
        default: "",
        optional: true,
        description: "Path to pre-computed ID embedding file (for PhotoMaker v2)"
      }
    }
  end

  @impl true
  def output_spec do
    %{
      photo_maker: %{type: :photo_maker, label: "PHOTOMAKER"}
    }
  end

  @impl true
  def ui_component, do: {:custom, "LoadPhotoMakerNode"}

  @impl true
  def process(inputs, config) do
    model_path = inputs["model_path"] || config["model_path"]
    id_images_dir = inputs["id_images_dir"] || config["id_images_dir"]

    cond do
      is_nil(model_path) or model_path == "" ->
        {:error, "PhotoMaker model path is required"}

      is_nil(id_images_dir) or id_images_dir == "" ->
        {:error, "ID images directory is required"}

      not File.exists?(model_path) ->
        {:error, "PhotoMaker model not found: #{model_path}"}

      not File.dir?(id_images_dir) ->
        {:error, "ID images directory not found: #{id_images_dir}"}

      true ->
        style_strength = inputs["style_strength"] || config["style_strength"] || 20
        id_embed_path = inputs["id_embed_path"] || config["id_embed_path"]

        # Clamp style_strength to valid range
        style_strength = max(0, min(100, style_strength))

        # Build PhotoMaker info struct
        photo_maker_info = %{
          model_path: model_path,
          id_images_dir: id_images_dir,
          style_strength: style_strength,
          id_embed_path: if(id_embed_path != "", do: id_embed_path, else: nil),
          type: :photo_maker
        }

        {:ok, %{"photo_maker" => photo_maker_info}}
    end
  end
end
