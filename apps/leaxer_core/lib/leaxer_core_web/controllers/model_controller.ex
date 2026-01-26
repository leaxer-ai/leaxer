defmodule LeaxerCoreWeb.ModelController do
  @moduledoc """
  REST API controller for model management.

  Provides endpoints for listing, inspecting, and managing
  Stable Diffusion models (.safetensors, .ckpt, .gguf).
  """
  use LeaxerCoreWeb, :controller

  alias LeaxerCore.Models.Loader

  @doc """
  GET /api/models

  Returns all models in the models directory.

  Query params:
  - type: Filter by model type (checkpoint, lora, vae, llm)
  """
  def index(conn, params) do
    models =
      case params["type"] do
        "checkpoint" -> Loader.list_checkpoints()
        "lora" -> Loader.list_loras()
        "vae" -> Loader.list_vaes()
        "llm" -> Loader.list_llms()
        _ -> Loader.list_models()
      end

    conn
    |> put_status(:ok)
    |> json(%{
      models: Enum.map(models, &serialize_model/1),
      count: length(models)
    })
  end

  @doc """
  GET /api/models/:name

  Returns details for a specific model.
  """
  def show(conn, %{"name" => name}) do
    case Loader.get_model(name) do
      {:ok, model} ->
        conn
        |> put_status(:ok)
        |> json(%{model: serialize_model(model)})

      {:error, reason} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: reason})
    end
  end

  @doc """
  GET /api/models/checkpoints

  Returns all checkpoint models (main SD models).
  """
  def checkpoints(conn, _params) do
    models = Loader.list_checkpoints()

    conn
    |> put_status(:ok)
    |> json(%{
      models: Enum.map(models, &serialize_model/1),
      count: length(models)
    })
  end

  @doc """
  GET /api/models/loras

  Returns all LoRA models.
  """
  def loras(conn, _params) do
    models = Loader.list_loras()

    conn
    |> put_status(:ok)
    |> json(%{
      models: Enum.map(models, &serialize_model/1),
      count: length(models)
    })
  end

  @doc """
  GET /api/models/vaes

  Returns all VAE models.
  """
  def vaes(conn, _params) do
    models = Loader.list_vaes()

    conn
    |> put_status(:ok)
    |> json(%{
      models: Enum.map(models, &serialize_model/1),
      count: length(models)
    })
  end

  @doc """
  GET /api/models/controlnets

  Returns all ControlNet models.
  """
  def controlnets(conn, _params) do
    models = Loader.list_controlnets()

    conn
    |> put_status(:ok)
    |> json(%{
      models: Enum.map(models, &serialize_model/1),
      count: length(models)
    })
  end

  @doc """
  GET /api/models/llms

  Returns all LLM models.
  """
  def llms(conn, _params) do
    models = Loader.list_llms()

    conn
    |> put_status(:ok)
    |> json(%{
      models: Enum.map(models, &serialize_model/1),
      count: length(models)
    })
  end

  # Serialize model info to JSON-friendly format
  defp serialize_model(model) do
    base_model = %{
      name: model.name,
      path: model.path,
      format: to_string(model.format),
      size_bytes: model.size_bytes,
      size_human: model.size_human,
      type: to_string(model.type),
      modified_at: format_datetime(model.modified_at)
    }

    # Add quantization level for LLM models
    if Map.has_key?(model, :quantization) do
      Map.put(base_model, :quantization, model.quantization)
    else
      base_model
    end
  end

  defp format_datetime({{year, month, day}, {hour, minute, second}}) do
    "#{year}-#{pad(month)}-#{pad(day)}T#{pad(hour)}:#{pad(minute)}:#{pad(second)}Z"
  end

  defp format_datetime(other), do: inspect(other)

  defp pad(n) when n < 10, do: "0#{n}"
  defp pad(n), do: to_string(n)
end
