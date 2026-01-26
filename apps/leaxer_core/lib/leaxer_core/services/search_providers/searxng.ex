defmodule LeaxerCore.Services.SearchProviders.SearXNG do
  @moduledoc """
  SearXNG search provider.
  Uses public SearXNG instances with JSON API.
  """

  require Logger

  # List of public SearXNG instances (with JSON enabled)
  @default_instances [
    "https://searx.be",
    "https://search.bus-hit.me",
    "https://searx.tiekoetter.com",
    "https://search.ononoki.org"
  ]

  @user_agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

  def search(query, max_results, instance_url \\ nil) do
    Logger.info("[SearXNG] Searching for: #{query}")

    instances = if instance_url, do: [instance_url], else: @default_instances

    # Try instances until one works
    Enum.find_value(instances, {:error, "All SearXNG instances failed"}, fn instance ->
      case search_instance(instance, query, max_results) do
        {:ok, results} -> {:ok, results}
        {:error, _} -> nil
      end
    end)
  end

  defp search_instance(instance, query, max_results) do
    Logger.debug("[SearXNG] Trying instance: #{instance}")

    headers = [
      {"User-Agent", @user_agent},
      {"Accept", "application/json"}
    ]

    url = "#{instance}/search?q=#{URI.encode_www_form(query)}&format=json&categories=general"

    case Req.get(url, headers: headers, receive_timeout: 10_000) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        results = parse_json_results(body)
        Logger.info("[SearXNG] Found #{length(results)} results from #{instance}")
        {:ok, Enum.take(results, max_results)}

      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        case Jason.decode(body) do
          {:ok, json} ->
            results = parse_json_results(json)
            Logger.info("[SearXNG] Found #{length(results)} results from #{instance}")
            {:ok, Enum.take(results, max_results)}

          {:error, _} ->
            Logger.error("[SearXNG] Failed to parse JSON from #{instance}")
            {:error, "Invalid JSON response"}
        end

      {:ok, %{status: status}} ->
        Logger.debug("[SearXNG] #{instance} returned HTTP #{status}")
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        Logger.debug("[SearXNG] #{instance} failed: #{inspect(reason)}")
        {:error, inspect(reason)}
    end
  end

  defp parse_json_results(%{"results" => results}) when is_list(results) do
    results
    |> Enum.map(fn result ->
      url = Map.get(result, "url")
      title = Map.get(result, "title", "")
      snippet = Map.get(result, "content", "")

      if url && title != "" do
        %{title: title, url: url, snippet: snippet}
      else
        nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_json_results(_), do: []
end
