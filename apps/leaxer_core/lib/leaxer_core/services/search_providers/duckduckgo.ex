defmodule LeaxerCore.Services.SearchProviders.DuckDuckGo do
  @moduledoc """
  DuckDuckGo HTML search provider.
  """

  require Logger

  @ddg_url "https://html.duckduckgo.com/html/"
  @user_agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

  def search(query, max_results) do
    Logger.info("[DuckDuckGo] Searching for: #{query}")

    headers = [
      {"User-Agent", @user_agent},
      {"Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"},
      {"Accept-Language", "en-US,en;q=0.5"}
    ]

    case Req.post(@ddg_url,
           form: [q: query, kl: "us-en"],
           headers: headers,
           receive_timeout: 10_000
         ) do
      {:ok, %{status: 200, body: html}} when is_binary(html) ->
        results = parse_results(html)
        Logger.info("[DuckDuckGo] Found #{length(results)} results")
        {:ok, Enum.take(results, max_results)}

      {:ok, %{status: status}} ->
        Logger.error("[DuckDuckGo] HTTP #{status}")
        {:error, "DuckDuckGo returned HTTP #{status}"}

      {:error, reason} ->
        Logger.error("[DuckDuckGo] Request failed: #{inspect(reason)}")
        {:error, "DuckDuckGo request failed: #{inspect(reason)}"}
    end
  end

  defp parse_results(html) do
    {:ok, document} = Floki.parse_document(html)

    document
    |> Floki.find(".result")
    |> Enum.map(&parse_result/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_result(result_element) do
    link = Floki.find(result_element, ".result__a")
    snippet = Floki.find(result_element, ".result__snippet")

    case link do
      [link_el | _] ->
        href = Floki.attribute(link_el, "href") |> List.first()
        title = Floki.text(link_el) |> String.trim()

        snippet_text =
          case snippet do
            [snippet_el | _] -> Floki.text(snippet_el) |> String.trim()
            _ -> ""
          end

        actual_url = extract_url(href)

        if actual_url && title != "" do
          %{title: title, url: actual_url, snippet: snippet_text}
        else
          nil
        end

      _ ->
        nil
    end
  end

  defp extract_url(nil), do: nil

  defp extract_url(href) do
    cond do
      String.contains?(href, "uddg=") ->
        href
        |> URI.parse()
        |> Map.get(:query, "")
        |> URI.decode_query()
        |> Map.get("uddg")

      String.starts_with?(href, "http") ->
        href

      String.starts_with?(href, "//") ->
        "https:" <> href

      true ->
        nil
    end
  end
end
