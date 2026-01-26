defmodule LeaxerCoreWeb.ChatController do
  @moduledoc """
  REST API controller for chat session operations.

  Provides endpoints for:
  - Session CRUD (list, get, save, delete)
  - Session renaming
  - PDF text extraction
  """
  use LeaxerCoreWeb, :controller

  alias LeaxerCore.Paths
  alias LeaxerCore.Pdf

  @doc """
  GET /api/chats

  Lists all chat session files in the chats directory.

  Response:
  ```json
  {
    "sessions": [
      {
        "id": "chat_1234567890_abc12",
        "name": "My Chat Session",
        "filename": "chat_1234567890_abc12.chat",
        "modified_at": "2024-01-15T10:30:00Z"
      },
      ...
    ]
  }
  ```
  """
  def index(conn, _params) do
    chats_dir = Paths.chats_dir()

    # Ensure directory exists
    File.mkdir_p!(chats_dir)

    sessions =
      case File.ls(chats_dir) do
        {:ok, files} ->
          files
          |> Enum.filter(&String.ends_with?(&1, ".chat"))
          |> Enum.map(fn filename ->
            path = Path.join(chats_dir, filename)
            stat = File.stat!(path)
            id = String.replace_suffix(filename, ".chat", "")

            # Try to read name from file content
            name =
              case File.read(path) do
                {:ok, content} ->
                  case Jason.decode(content) do
                    {:ok, %{"name" => n}} when is_binary(n) -> n
                    _ -> id
                  end

                _ ->
                  id
              end

            %{
              id: id,
              name: name,
              filename: filename,
              modified_at: stat.mtime |> NaiveDateTime.from_erl!() |> NaiveDateTime.to_iso8601()
            }
          end)
          |> Enum.sort_by(& &1.modified_at, :desc)

        {:error, _} ->
          []
      end

    json(conn, %{sessions: sessions})
  end

  @doc """
  GET /api/chats/:id

  Gets a specific chat session by ID.

  Response: The session JSON content
  """
  def show(conn, %{"id" => id}) do
    filename = ensure_extension(id, ".chat")
    path = Path.join(Paths.chats_dir(), filename)

    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, session} ->
            json(conn, session)

          {:error, _} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Invalid session JSON"})
        end

      {:error, :enoent} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Session not found"})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to read session: #{inspect(reason)}"})
    end
  end

  @doc """
  POST /api/chats

  Creates a new chat session or updates an existing one.

  Request body:
  ```json
  {
    "id": "chat_1234567890_abc12",
    "name": "My Chat Session",
    "messages": [...],
    "created_at": 1234567890,
    "updated_at": 1234567890,
    "model": "/path/to/model.gguf",
    "settings": {...}
  }
  ```

  Response:
  ```json
  {
    "success": true,
    "id": "chat_1234567890_abc12",
    "filename": "chat_1234567890_abc12.chat",
    "path": "/path/to/chats/chat_1234567890_abc12.chat"
  }
  ```
  """
  def create(conn, %{"id" => id} = session) do
    filename = ensure_extension(id, ".chat")
    path = Path.join(Paths.chats_dir(), filename)

    # Ensure chats directory exists
    File.mkdir_p!(Paths.chats_dir())

    case Jason.encode(session, pretty: true) do
      {:ok, content} ->
        case File.write(path, content) do
          :ok ->
            json(conn, %{
              success: true,
              id: id,
              filename: filename,
              path: path
            })

          {:error, reason} ->
            conn
            |> put_status(:internal_server_error)
            |> json(%{error: "Failed to save session: #{inspect(reason)}"})
        end

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Invalid session data: #{inspect(reason)}"})
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required parameter: id"})
  end

  @doc """
  DELETE /api/chats/:id

  Deletes a chat session.

  Response:
  ```json
  {"success": true}
  ```
  """
  def delete(conn, %{"id" => id}) do
    filename = ensure_extension(id, ".chat")
    path = Path.join(Paths.chats_dir(), filename)

    case File.rm(path) do
      :ok ->
        json(conn, %{success: true})

      {:error, :enoent} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Session not found"})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to delete session: #{inspect(reason)}"})
    end
  end

  @doc """
  PUT /api/chats/:id/rename

  Renames a chat session.

  Request body:
  ```json
  {
    "name": "New Session Name"
  }
  ```

  Response:
  ```json
  {"success": true, "name": "New Session Name"}
  ```
  """
  def rename(conn, %{"id" => id, "name" => new_name}) do
    filename = ensure_extension(id, ".chat")
    path = Path.join(Paths.chats_dir(), filename)

    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, session} ->
            updated_session = Map.put(session, "name", new_name)

            case Jason.encode(updated_session, pretty: true) do
              {:ok, new_content} ->
                case File.write(path, new_content) do
                  :ok ->
                    json(conn, %{success: true, name: new_name})

                  {:error, reason} ->
                    conn
                    |> put_status(:internal_server_error)
                    |> json(%{error: "Failed to save: #{inspect(reason)}"})
                end

              {:error, reason} ->
                conn
                |> put_status(:unprocessable_entity)
                |> json(%{error: "Failed to encode: #{inspect(reason)}"})
            end

          {:error, _} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Invalid session JSON"})
        end

      {:error, :enoent} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Session not found"})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to read session: #{inspect(reason)}"})
    end
  end

  def rename(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required parameter: name"})
  end

  @doc """
  POST /api/extract-pdf

  Extracts text content from a PDF file.

  Request: multipart/form-data with "file" field containing the PDF

  Response:
  ```json
  {
    "success": true,
    "text": "Extracted text content..."
  }
  ```
  """
  def extract_pdf(conn, %{"file" => upload}) do
    # Validate it's a PDF
    if not String.ends_with?(String.downcase(upload.filename), ".pdf") do
      conn
      |> put_status(:bad_request)
      |> json(%{error: "File must be a PDF"})
    else
      case File.read(upload.path) do
        {:ok, pdf_data} ->
          case Pdf.extract_text_from_binary(pdf_data) do
            {:ok, text} ->
              json(conn, %{success: true, text: text})

            {:error, reason} ->
              conn
              |> put_status(:unprocessable_entity)
              |> json(%{error: reason})
          end

        {:error, reason} ->
          conn
          |> put_status(:internal_server_error)
          |> json(%{error: "Failed to read uploaded file: #{inspect(reason)}"})
      end
    end
  end

  def extract_pdf(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required file upload"})
  end

  @doc """
  GET /api/pdf-available

  Checks if pdftotext is available on the system.

  Response:
  ```json
  {"available": true}
  ```
  """
  def pdf_available(conn, _params) do
    json(conn, %{available: Pdf.available?()})
  end

  # Helper to ensure filename has correct extension
  defp ensure_extension(name, ext) do
    if String.ends_with?(name, ext), do: name, else: name <> ext
  end
end
