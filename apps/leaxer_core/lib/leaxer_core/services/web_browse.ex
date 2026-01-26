defmodule LeaxerCore.Services.WebBrowse do
  @moduledoc """
  Web browsing tool that combines search and content extraction.
  Used by the LLM to search the web and get relevant information.
  """

  alias LeaxerCore.Services.WebSearch
  alias LeaxerCore.Services.WebReader

  require Logger

  @doc """
  Search the web and extract content from top results.
  Returns formatted context for the LLM.

  Options:
  - :max_results - number of results to fetch (default: 3)
  - :max_chars_per_page - max characters per page (default: 1500)
  - :provider - search provider to use (default: "searxng")
  """
  def browse(query, opts \\ []) do
    max_results = Keyword.get(opts, :max_results, 3)
    max_chars = Keyword.get(opts, :max_chars_per_page, 1500)
    provider = Keyword.get(opts, :provider, "searxng")

    # Sanitize query to remove potentially outdated years
    clean_query = sanitize_query(query)

    Logger.info(
      "[WebBrowse] Browsing for: #{clean_query} (original: #{query}, provider: #{provider})"
    )

    # Step 1: Search using configured provider
    search_results = WebSearch.search(clean_query, max_results, provider)

    if Enum.empty?(search_results) do
      Logger.warning("[WebBrowse] No search results found")
      {:ok, "No search results found for: #{query}", []}
    else
      # Step 2: Fetch and extract content from each URL
      urls = Enum.map(search_results, & &1.url)
      fetched = WebReader.fetch_multiple(urls, max_chars)

      # Step 3: Extract OG tags for rich previews (async with content fetch)
      og_data = WebReader.extract_og_tags_multiple(urls)

      # Step 4: Format results for LLM context
      context = format_results(search_results, fetched)

      # Step 5: Build references list for frontend with OG data
      references =
        search_results
        |> Enum.with_index(1)
        |> Enum.map(fn {result, idx} ->
          og = Map.get(og_data, result.url, %{})

          %{
            index: idx,
            title: og[:og_title] || result.title,
            url: result.url,
            description: og[:og_description] || result.snippet,
            image: og[:og_image],
            site_name: og[:og_site_name] || extract_domain(result.url),
            favicon: og[:favicon]
          }
        end)

      {:ok, context, references}
    end
  end

  defp format_results(search_results, fetched_content) do
    # Create a map of url -> content for quick lookup
    content_map = Map.new(fetched_content)

    results =
      search_results
      |> Enum.with_index(1)
      |> Enum.map(fn {result, idx} ->
        content = Map.get(content_map, result.url, result.snippet)

        """
        [#{idx}] #{result.title}
        URL: #{result.url}
        #{content}
        """
      end)
      |> Enum.join("\n---\n")

    """
    Web Search Results:

    #{results}
    ---
    Use the above search results to help answer the user's question. Cite sources using [1], [2], etc.
    """
  end

  @doc """
  Returns the system prompt addition for web browsing capability.
  """
  def tool_system_prompt do
    """
    You have access to a web search tool. When you need current information from the internet, output ONLY this JSON (nothing else before or after):

    {"tool": "web_search", "query": "your search query"}

    IMPORTANT:
    - Output ONLY the JSON when you want to search, no other text
    - Use web search for: current events, recent news, up-to-date information, facts you're unsure about
    - DO NOT include years in your search query (e.g., use "latest iPhone" not "iPhone 2024")
    - Be specific with search queries but keep them timeless
    - After receiving search results, synthesize the information and cite sources using [1], [2], etc.
    - If you don't need to search, respond normally without any JSON
    """
  end

  @doc """
  Sanitize search query by removing year references that may be outdated.
  """
  def sanitize_query(query) do
    query
    # Remove standalone years (2020-2030)
    |> String.replace(~r/\b20[2-3]\d\b/, "")
    # Remove "in YYYY", "for YYYY", etc.
    |> String.replace(~r/\b(in|for|from|since|after|before)\s+20[2-3]\d\b/i, "")
    # Clean up extra spaces
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  @doc """
  Parse tool calls from LLM output.
  Returns {:tool_call, tool_name, params} or :no_tool_call

  Handles multiple formats including JSON embedded in explanatory text.
  """
  def parse_tool_call(text) do
    # First, try to find any JSON object containing "web_search" anywhere in the text
    # This handles cases where the model adds explanation before/after the JSON
    case extract_json_with_tool(text) do
      {:ok, %{"tool" => "web_search", "query" => query}} ->
        {:tool_call, :web_search, %{query: query}}

      _ ->
        :no_tool_call
    end
  end

  # Extract domain name from URL
  defp extract_domain(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) ->
        # Remove www. prefix if present
        String.replace_prefix(host, "www.", "")

      _ ->
        nil
    end
  end

  # Extract JSON object containing "tool" key from text
  defp extract_json_with_tool(text) do
    # Find all potential JSON object starts
    # Look for { followed eventually by "tool"
    case Regex.run(~r/\{[^{}]*"tool"[^{}]*"query"[^{}]*\}/s, text) do
      [json_str] ->
        # Clean up whitespace/newlines and parse
        clean = String.replace(json_str, ~r/[\n\r]+\s*/, " ")
        Jason.decode(clean)

      nil ->
        # Try reversed order (query before tool)
        case Regex.run(~r/\{[^{}]*"query"[^{}]*"tool"[^{}]*\}/s, text) do
          [json_str] ->
            clean = String.replace(json_str, ~r/[\n\r]+\s*/, " ")
            Jason.decode(clean)

          nil ->
            {:error, :no_json_found}
        end
    end
  end
end
