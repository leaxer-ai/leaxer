defmodule LeaxerCore.Services.WebReader do
  @moduledoc """
  Fetches and extracts clean text content from web pages.
  Uses Floki to parse HTML and extract readable content.
  """

  require Logger

  @user_agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
  @max_chars_per_page 1500
  @timeout 10_000

  @doc """
  Fetch a URL and extract clean text content.
  Returns {:ok, text} or {:error, reason}.
  """
  def fetch_and_extract(url, max_chars \\ @max_chars_per_page) do
    Logger.info("[WebReader] Fetching: #{url}")

    case fetch(url) do
      {:ok, html} ->
        text = extract_content(html)
        truncated = String.slice(text, 0, max_chars)
        Logger.info("[WebReader] Extracted #{String.length(truncated)} chars from #{url}")
        {:ok, truncated}

      {:error, reason} ->
        Logger.error("[WebReader] Failed to fetch #{url}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Fetch and extract content from multiple URLs.
  Returns a list of {url, content} tuples.
  """
  def fetch_multiple(urls, max_chars \\ @max_chars_per_page) do
    urls
    |> Task.async_stream(
      fn url ->
        case fetch_and_extract(url, max_chars) do
          {:ok, content} -> {url, content}
          {:error, _} -> {url, nil}
        end
      end,
      timeout: @timeout + 2_000,
      on_timeout: :kill_task
    )
    |> Enum.map(fn
      {:ok, result} -> result
      {:exit, _} -> {nil, nil}
    end)
    |> Enum.reject(fn {_, content} -> is_nil(content) end)
  end

  defp fetch(url) do
    headers = [
      {"User-Agent", @user_agent},
      {"Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"},
      {"Accept-Language", "en-US,en;q=0.5"}
    ]

    case Req.get(url, headers: headers, receive_timeout: @timeout, redirect: true) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_content(html) when is_binary(html) do
    case Floki.parse_document(html) do
      {:ok, document} ->
        document
        |> remove_unwanted_elements()
        |> extract_main_content()
        |> clean_text()

      {:error, _} ->
        ""
    end
  end

  defp extract_content(_), do: ""

  defp remove_unwanted_elements(document) do
    # Remove scripts, styles, nav, footer, aside, forms, etc.
    unwanted_selectors = [
      "script",
      "style",
      "noscript",
      "nav",
      "header",
      "footer",
      "aside",
      "form",
      "iframe",
      "svg",
      "img",
      "video",
      "audio",
      ".nav",
      ".navigation",
      ".menu",
      ".sidebar",
      ".footer",
      ".header",
      ".advertisement",
      ".ads",
      ".ad",
      ".social",
      ".share",
      ".comments",
      ".comment",
      "#nav",
      "#navigation",
      "#menu",
      "#sidebar",
      "#footer",
      "#header",
      "#comments"
    ]

    Enum.reduce(unwanted_selectors, document, fn selector, doc ->
      Floki.filter_out(doc, selector)
    end)
  end

  defp extract_main_content(document) do
    # Try to find main content areas in order of preference
    content_selectors = [
      "article",
      "main",
      "[role=main]",
      ".article",
      ".post",
      ".content",
      ".entry-content",
      ".post-content",
      "#content",
      "#main",
      ".main"
    ]

    content =
      Enum.find_value(content_selectors, fn selector ->
        case Floki.find(document, selector) do
          [] -> nil
          found -> Floki.text(found)
        end
      end)

    # Fallback to body if no specific content area found
    content || Floki.find(document, "body") |> Floki.text()
  end

  defp clean_text(text) when is_binary(text) do
    text
    # Collapse whitespace
    |> String.replace(~r/\s+/, " ")
    # Normalize paragraph breaks
    |> String.replace(~r/\n\s*\n+/, "\n\n")
    |> String.trim()
  end

  defp clean_text(_), do: ""

  @doc """
  Extract Open Graph metadata from HTML.
  Returns a map with :og_title, :og_description, :og_image, :og_site_name, :favicon
  """
  def extract_og_tags(url) do
    case fetch(url) do
      {:ok, html} ->
        {:ok, parse_og_tags(html, url)}

      {:error, reason} ->
        Logger.warning("[WebReader] Failed to fetch OG tags for #{url}: #{inspect(reason)}")
        {:ok, %{}}
    end
  end

  @doc """
  Extract OG tags from multiple URLs concurrently.
  Returns a map of url -> og_data
  """
  def extract_og_tags_multiple(urls) do
    urls
    |> Task.async_stream(
      fn url ->
        case extract_og_tags(url) do
          {:ok, og_data} -> {url, og_data}
          _ -> {url, %{}}
        end
      end,
      timeout: @timeout + 2_000,
      on_timeout: :kill_task
    )
    |> Enum.map(fn
      {:ok, result} -> result
      {:exit, _} -> {nil, %{}}
    end)
    |> Enum.reject(fn {url, _} -> is_nil(url) end)
    |> Map.new()
  end

  defp parse_og_tags(html, url) when is_binary(html) do
    case Floki.parse_document(html) do
      {:ok, document} ->
        og_title =
          get_meta_content(document, "og:title") || get_meta_content(document, "twitter:title")

        og_description =
          get_meta_content(document, "og:description") ||
            get_meta_content(document, "twitter:description") ||
            get_meta_content(document, "description")

        og_image =
          get_meta_content(document, "og:image") || get_meta_content(document, "twitter:image")

        og_site_name = get_meta_content(document, "og:site_name")
        favicon = extract_favicon(document, url)

        %{
          og_title: og_title,
          og_description: truncate_string(og_description, 200),
          og_image: normalize_url(og_image, url),
          og_site_name: og_site_name,
          favicon: favicon
        }

      {:error, _} ->
        %{}
    end
  end

  defp parse_og_tags(_, _), do: %{}

  defp get_meta_content(document, property) do
    # Try property attribute first (for og: tags)
    result =
      Floki.find(document, "meta[property=\"#{property}\"]")
      |> Floki.attribute("content")
      |> List.first()

    # Fall back to name attribute (for standard meta tags)
    result ||
      Floki.find(document, "meta[name=\"#{property}\"]")
      |> Floki.attribute("content")
      |> List.first()
  end

  defp extract_favicon(document, base_url) do
    # Try various favicon selectors in order of preference
    favicon_selectors = [
      "link[rel=\"icon\"]",
      "link[rel=\"shortcut icon\"]",
      "link[rel=\"apple-touch-icon\"]",
      "link[rel=\"apple-touch-icon-precomposed\"]"
    ]

    favicon_href =
      Enum.find_value(favicon_selectors, fn selector ->
        Floki.find(document, selector)
        |> Floki.attribute("href")
        |> List.first()
      end)

    # If no favicon found in HTML, try default /favicon.ico
    favicon_href = favicon_href || "/favicon.ico"
    normalize_url(favicon_href, base_url)
  end

  defp normalize_url(nil, _base_url), do: nil
  defp normalize_url("", _base_url), do: nil

  defp normalize_url(url, base_url) do
    cond do
      # Already absolute URL
      String.starts_with?(url, "http://") or String.starts_with?(url, "https://") ->
        url

      # Protocol-relative URL
      String.starts_with?(url, "//") ->
        "https:" <> url

      # Absolute path
      String.starts_with?(url, "/") ->
        uri = URI.parse(base_url)
        "#{uri.scheme}://#{uri.host}#{url}"

      # Relative path
      true ->
        uri = URI.parse(base_url)
        base_path = uri.path || "/"
        base_dir = Path.dirname(base_path)
        "#{uri.scheme}://#{uri.host}#{Path.join(base_dir, url)}"
    end
  end

  defp truncate_string(nil, _max), do: nil
  defp truncate_string(str, max) when byte_size(str) <= max, do: str

  defp truncate_string(str, max) do
    String.slice(str, 0, max - 3) <> "..."
  end
end
