defmodule LeaxerCore.Services.WebSearch do
  @moduledoc """
  Web search module with multiple provider support.
  Routes search queries to the configured provider.
  """

  require Logger

  alias LeaxerCore.Services.SearchProviders.{DuckDuckGo, Brave, SearXNG}

  @providers %{
    "duckduckgo" => DuckDuckGo,
    "brave" => Brave,
    "searxng" => SearXNG
  }

  @default_provider "duckduckgo"

  @doc """
  Returns list of available search providers.
  """
  def available_providers do
    [
      %{
        id: "duckduckgo",
        name: "DuckDuckGo",
        description: "Privacy-focused search engine (recommended)"
      },
      %{id: "brave", name: "Brave Search", description: "Independent search engine"},
      %{id: "searxng", name: "SearXNG", description: "Privacy-respecting meta search"}
    ]
  end

  @doc """
  Search using the specified provider.
  Returns a list of results, each with :title, :url, and :snippet.
  """
  def search(query, max_results \\ 3, provider \\ @default_provider) do
    Logger.info("[WebSearch] Searching with provider '#{provider}' for: #{query}")

    provider_module = Map.get(@providers, provider, SearXNG)

    case provider_module.search(query, max_results) do
      {:ok, results} ->
        Logger.info("[WebSearch] Found #{length(results)} results")
        results

      {:error, reason} ->
        Logger.error("[WebSearch] Search failed: #{inspect(reason)}")
        # Try fallback to DuckDuckGo if primary fails
        if provider != "duckduckgo" do
          Logger.info("[WebSearch] Trying DuckDuckGo as fallback...")

          case DuckDuckGo.search(query, max_results) do
            {:ok, results} -> results
            {:error, _} -> []
          end
        else
          []
        end
    end
  end
end
