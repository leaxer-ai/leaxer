defmodule LeaxerCore.Services.SearchProviders.Brave do
  @moduledoc """
  Brave Search HTML provider.
  Scrapes Brave Search results page.
  """

  require Logger

  @brave_url "https://search.brave.com/search"
  @user_agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

  def search(query, max_results) do
    Logger.info("[Brave] Searching for: #{query}")

    headers = [
      {"User-Agent", @user_agent},
      {"Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"},
      {"Accept-Language", "en-US,en;q=0.5"}
    ]

    url = "#{@brave_url}?q=#{URI.encode_www_form(query)}"

    case Req.get(url, headers: headers, receive_timeout: 10_000) do
      {:ok, %{status: 200, body: html}} when is_binary(html) ->
        results = parse_results(html)
        Logger.info("[Brave] Found #{length(results)} results")
        {:ok, Enum.take(results, max_results)}

      {:ok, %{status: status}} ->
        Logger.error("[Brave] HTTP #{status}")
        {:error, "Brave Search returned HTTP #{status}"}

      {:error, reason} ->
        Logger.error("[Brave] Request failed: #{inspect(reason)}")
        {:error, "Brave Search request failed: #{inspect(reason)}"}
    end
  end

  defp parse_results(html) do
    {:ok, document} = Floki.parse_document(html)

    # Brave uses different selectors - try multiple
    selectors = [
      "#results .snippet",
      ".result",
      "[data-type=\"web\"]",
      ".fdb"
    ]

    result_elements =
      Enum.find_value(selectors, [], fn selector ->
        elements = Floki.find(document, selector)
        if length(elements) > 0, do: elements, else: nil
      end) || []

    result_elements
    |> Enum.map(&parse_result/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_result(result_element) do
    # Try multiple link selectors
    link =
      case Floki.find(result_element, "a.result-header") do
        [] ->
          case Floki.find(result_element, "a[href]") do
            [] -> []
            found -> Enum.take(found, 1)
          end

        found ->
          found
      end

    # Try multiple snippet selectors
    snippet =
      case Floki.find(result_element, ".snippet-description") do
        [] -> Floki.find(result_element, ".snippet-content")
        found -> found
      end

    case link do
      [link_el | _] ->
        href = Floki.attribute(link_el, "href") |> List.first()

        # Title might be in the link or a child element
        title =
          case Floki.find(link_el, ".title") do
            [] -> Floki.text(link_el) |> String.trim()
            [title_el | _] -> Floki.text(title_el) |> String.trim()
          end

        snippet_text =
          case snippet do
            [snippet_el | _] -> Floki.text(snippet_el) |> String.trim()
            _ -> ""
          end

        if href && String.starts_with?(href, "http") && title != "" do
          %{title: title, url: href, snippet: snippet_text}
        else
          nil
        end

      _ ->
        nil
    end
  end
end
