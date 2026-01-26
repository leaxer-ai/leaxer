defmodule LeaxerCore.Workers.ArtifactGenerator do
  @moduledoc """
  Generates compiled markdown documents from chat conversations with streaming support.
  """

  alias LeaxerCore.Workers.LLMServer
  require Logger

  @create_system_prompt """
  You are a document compiler. Create a comprehensive, well-structured markdown document that compiles and organizes all the researched information from this conversation.

  Requirements:
  - Start with a clear, descriptive title as a level 1 heading (# Title)
  - Use proper markdown formatting (headers, lists, code blocks)
  - Organize information logically with clear sections
  - Include all relevant details discussed
  - Add a summary section at the top
  - Be thorough but concise

  IMPORTANT: If source references are provided at the end, you MUST include a "## References" section that copies the EXACT markdown links provided. Do NOT make up your own references - ONLY use the ones provided. Copy them exactly as given.

  Output ONLY the markdown document, nothing else.
  """

  @refine_system_prompt """
  You are a document editor. You will be given an existing document and new conversation context. Your task is to REFINE and UPDATE the existing document with the new information.

  Requirements:
  - Keep the existing document structure as much as possible
  - ADD new information from the latest conversation
  - UPDATE existing sections if new information contradicts or expands on them
  - REMOVE outdated information if it has been corrected
  - Maintain proper markdown formatting
  - Keep the document well-organized and coherent
  - Preserve the title unless a better one is evident from the new context

  IMPORTANT: If source references are provided at the end, you MUST include a "## References" section that copies the EXACT markdown links provided. Do NOT make up your own references - ONLY use the ones provided. Copy them exactly as given.

  Output ONLY the refined markdown document, nothing else.
  """

  @doc """
  Generate an artifact document from the conversation with streaming.
  Streams content chunks via artifact_chunk events and returns final result.

  If existing_artifact is provided, refines the existing document instead of creating new.
  If references are provided, they will be formatted as markdown links for the document.
  """
  def generate(
        messages,
        assistant_response,
        socket_pid,
        existing_artifact \\ nil,
        references \\ []
      ) do
    endpoint = LLMServer.get_endpoint()

    if is_nil(endpoint) do
      {:error, "LLM server not available"}
    else
      # Notify pending status
      send(socket_pid, {:push, "artifact_status", %{status: "pending"}})

      # Notify generating status
      send(socket_pid, {:push, "artifact_status", %{status: "generating"}})

      # Include assistant response in the conversation for artifact generation
      full_conversation = format_conversation(messages, assistant_response)

      # Format references as markdown links for the LLM to use
      references_text = format_references(references)

      # Build messages based on whether we're creating or refining
      compile_messages =
        if existing_artifact && existing_artifact != "" do
          Logger.info(
            "[ArtifactGenerator] Refining existing document (#{String.length(existing_artifact)} chars), refs: #{length(references)}"
          )

          [
            %{"role" => "system", "content" => @refine_system_prompt},
            %{
              "role" => "user",
              "content" => """
              Here is the existing document to refine:

              ---EXISTING DOCUMENT---
              #{existing_artifact}
              ---END EXISTING DOCUMENT---

              Here is the new conversation context to incorporate:

              ---NEW CONTEXT---
              #{full_conversation}
              ---END NEW CONTEXT---
              #{references_text}
              Please refine the document with the new information.
              """
            }
          ]
        else
          Logger.info("[ArtifactGenerator] Creating new document, refs: #{length(references)}")

          [
            %{"role" => "system", "content" => @create_system_prompt},
            %{
              "role" => "user",
              "content" =>
                "Compile the following conversation into a document:\n\n#{full_conversation}#{references_text}"
            }
          ]
        end

      case stream_completion_request(endpoint, compile_messages, socket_pid) do
        {:ok, content} ->
          title = extract_title(content)
          {:ok, %{title: title, content: content}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp format_conversation(messages, assistant_response) do
    # Format user messages
    user_messages =
      messages
      |> Enum.map(fn msg ->
        role = Map.get(msg, "role", "unknown")
        content = Map.get(msg, "content", "")
        "#{String.capitalize(role)}: #{content}"
      end)
      |> Enum.join("\n\n")

    # Add assistant response
    "#{user_messages}\n\nAssistant: #{assistant_response}"
  end

  defp format_references([]), do: ""

  defp format_references(references) when is_list(references) do
    formatted =
      references
      |> Enum.with_index(1)
      |> Enum.map(fn {ref, index} ->
        title = Map.get(ref, :title) || Map.get(ref, "title") || "Source #{index}"
        url = Map.get(ref, :url) || Map.get(ref, "url") || ""
        "#{index}. [#{title}](#{url})"
      end)
      |> Enum.join("\n")

    """

    ---SOURCES TO USE---
    COPY THESE EXACT LINKS to your ## References section (do not modify or make up new ones):

    #{formatted}
    ---END SOURCES---
    """
  end

  defp extract_title(content) do
    case Regex.run(~r/^#\s+(.+)$/m, content) do
      [_, title] -> String.trim(title)
      _ -> "Research Document"
    end
  end

  defp stream_completion_request(endpoint, messages, socket_pid) do
    url = "#{endpoint}/v1/chat/completions"

    body =
      Jason.encode!(%{
        "messages" => messages,
        "stream" => true,
        "temperature" => 0.3,
        "max_tokens" => 4096
      })

    headers = [{"content-type", "application/json"}]
    request = Finch.build(:post, url, headers, body)

    Logger.info("[ArtifactGenerator] Starting streaming artifact generation...")

    # Stream and accumulate content
    content_acc = {:ok, ""}

    result =
      Finch.stream(
        request,
        LeaxerCore.Finch,
        content_acc,
        fn
          {:status, status}, acc ->
            if status == 200 do
              acc
            else
              {:error, "HTTP #{status}"}
            end

          {:headers, _headers}, acc ->
            acc

          {:data, data}, {:ok, content} ->
            # Process SSE data
            new_content = process_sse_data(data, content, socket_pid)
            {:ok, new_content}

          {:data, _data}, {:error, _} = error ->
            error
        end,
        receive_timeout: 120_000
      )

    case result do
      {:ok, {:ok, content}} ->
        Logger.info(
          "[ArtifactGenerator] Artifact streamed successfully (#{String.length(content)} chars)"
        )

        {:ok, content}

      {:ok, {:error, reason}} ->
        Logger.error("[ArtifactGenerator] Streaming error: #{reason}")
        {:error, reason}

      {:error, reason} ->
        Logger.error("[ArtifactGenerator] Request failed: #{inspect(reason)}")
        {:error, inspect(reason)}
    end
  end

  defp process_sse_data(data, content_acc, socket_pid) do
    data
    |> String.split("\n")
    |> Enum.reduce(content_acc, fn line, acc ->
      line = String.trim(line)

      cond do
        line == "" or line == "data: [DONE]" ->
          acc

        String.starts_with?(line, "data: ") ->
          json_str = String.trim_leading(line, "data: ")

          case Jason.decode(json_str) do
            {:ok, %{"choices" => [%{"delta" => delta} | _]}} ->
              chunk = Map.get(delta, "content") || ""

              if chunk != "" do
                # Send chunk to client
                Logger.debug("[ArtifactGenerator] Sending chunk: #{String.length(chunk)} chars")
                send(socket_pid, {:push, "artifact_chunk", %{content: chunk}})
                acc <> chunk
              else
                acc
              end

            _ ->
              acc
          end

        true ->
          acc
      end
    end)
  end
end
