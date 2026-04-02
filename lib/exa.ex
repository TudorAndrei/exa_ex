defmodule Exa do
  @moduledoc """
  Elixir client for the Exa Search API.

  ## Configuration

  Pass an API key when creating a client:

      client = Exa.client("your-api-key")

  Or configure globally:

      config :exa, api_key: "your-api-key"

  Then use `Exa.client/0`.
  """

  @base_url "https://api.exa.ai"

  @type client :: Req.Request.t()

  @doc """
  Creates a new Exa API client with the given API key.
  """
  @spec client(String.t(), keyword()) :: client()
  def client(api_key, opts \\ []) do
    base_url = Keyword.get(opts, :base_url, @base_url)

    Req.new(
      base_url: base_url,
      headers: [{"x-api-key", api_key}, {"content-type", "application/json"}],
      receive_timeout: Keyword.get(opts, :receive_timeout, 30_000)
    )
  end

  @doc """
  Creates a client using the configured API key from application config.
  """
  @spec client() :: client()
  def client do
    api_key =
      Application.get_env(:exa, :api_key) ||
        raise "Exa API key not configured. Set config :exa, api_key: \"your-key\""

    opts =
      case Application.get_env(:exa, :base_url) do
        nil -> []
        url -> [base_url: url]
      end

    client(api_key, opts)
  end

  @doc """
  Search the web with a query. Returns results with optional content.

  ## Options

  Core:
    * `:type` - Search type: `"neural"`, `"fast"`, `"auto"` (default), or `"deep"`
    * `:category` - Focus category: `"company"`, `"research paper"`, `"news"`, `"pdf"`,
      `"github"`, `"personal site"`, `"people"`, `"financial report"`
    * `:num_results` - Number of results (1-100, default 10)

  Content (set to get content inline with search results):
    * `:text` - `true` for full text, or `%{max_characters: n}` for limited text
    * `:summary` - `%{query: "..."}` for LLM summaries
    * `:highlights` - `%{num_sentences: n, highlights_per_url: n, query: "..."}`
    * `:context` - `true` or `%{max_characters: n}` for LLM-ready context string

  Filters:
    * `:include_domains` - List of domains to restrict to
    * `:exclude_domains` - List of domains to exclude
    * `:start_published_date` - ISO 8601 date string
    * `:end_published_date` - ISO 8601 date string
    * `:include_text` - List of strings that must appear in results
    * `:exclude_text` - List of strings that must not appear

  ## Examples

      Exa.search(client, "Latest research in LLMs", text: true)
      Exa.search(client, "Elixir web frameworks", type: "neural", num_results: 5)
  """
  @spec search(client(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def search(client, query, opts \\ []) do
    body = build_search_body(query, opts)
    post(client, "/search", body)
  end

  @doc """
  Find similar pages to a given URL.

  Accepts the same content and filter options as `search/3`.

  ## Examples

      Exa.find_similar(client, "https://arxiv.org/abs/2307.06435", text: true)
  """
  @spec find_similar(client(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def find_similar(client, url, opts \\ []) do
    body =
      opts
      |> build_common_params()
      |> Map.put(:url, url)

    post(client, "/findSimilar", body)
  end

  @doc """
  Get contents for a list of URLs.

  ## Options

  Same content options as `search/3`: `:text`, `:summary`, `:highlights`, `:context`.

  Additional:
    * `:livecrawl` - `"never"`, `"fallback"`, `"always"`, or `"preferred"`
    * `:livecrawl_timeout` - Timeout in milliseconds (default 10000)

  ## Examples

      Exa.get_contents(client, ["https://example.com"], text: true)
  """
  @spec get_contents(client(), [String.t()], keyword()) :: {:ok, map()} | {:error, term()}
  def get_contents(client, urls, opts \\ []) do
    body =
      opts
      |> build_contents_params()
      |> Map.put(:urls, urls)

    post(client, "/contents", body)
  end

  @doc """
  Generate an answer from search results.

  ## Options

    * `:text` - Include full text in citations (default false)
    * `:stream` - Stream response via SSE (default false)

  ## Examples

      Exa.answer(client, "What is the latest valuation of SpaceX?", text: true)
  """
  @spec answer(client(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def answer(client, query, opts \\ []) do
    body =
      %{query: query}
      |> maybe_put(:text, Keyword.get(opts, :text))
      |> maybe_put(:stream, Keyword.get(opts, :stream))

    post(client, "/answer", body)
  end

  # --- Private helpers ---

  defp post(client, path, body) do
    case Req.post(client, url: path, json: body) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, %{status: status, body: body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_search_body(query, opts) do
    opts
    |> build_common_params()
    |> Map.put(:query, query)
    |> maybe_put(:type, Keyword.get(opts, :type))
    |> maybe_put(:category, Keyword.get(opts, :category))
    |> maybe_put(:additionalQueries, Keyword.get(opts, :additional_queries))
    |> maybe_put(:userLocation, Keyword.get(opts, :user_location))
  end

  defp build_common_params(opts) do
    %{}
    |> maybe_put(:numResults, Keyword.get(opts, :num_results))
    |> maybe_put(:includeDomains, Keyword.get(opts, :include_domains))
    |> maybe_put(:excludeDomains, Keyword.get(opts, :exclude_domains))
    |> maybe_put(:startCrawlDate, Keyword.get(opts, :start_crawl_date))
    |> maybe_put(:endCrawlDate, Keyword.get(opts, :end_crawl_date))
    |> maybe_put(:startPublishedDate, Keyword.get(opts, :start_published_date))
    |> maybe_put(:endPublishedDate, Keyword.get(opts, :end_published_date))
    |> maybe_put(:includeText, Keyword.get(opts, :include_text))
    |> maybe_put(:excludeText, Keyword.get(opts, :exclude_text))
    |> maybe_put(:context, Keyword.get(opts, :context))
    |> maybe_put_contents(opts)
  end

  defp build_contents_params(opts) do
    %{}
    |> maybe_put(:livecrawl, Keyword.get(opts, :livecrawl))
    |> maybe_put(:livecrawlTimeout, Keyword.get(opts, :livecrawl_timeout))
    |> maybe_put_contents(opts)
  end

  defp maybe_put_contents(body, opts) do
    contents =
      %{}
      |> maybe_put(:text, Keyword.get(opts, :text))
      |> maybe_put(:highlights, camelize_keys(Keyword.get(opts, :highlights)))
      |> maybe_put(:summary, Keyword.get(opts, :summary))
      |> maybe_put(:subpages, Keyword.get(opts, :subpages))
      |> maybe_put(:subpageTarget, Keyword.get(opts, :subpage_target))
      |> maybe_put(:extras, camelize_keys(Keyword.get(opts, :extras)))
      |> maybe_put(:context, Keyword.get(opts, :context))

    case contents do
      empty when map_size(empty) == 0 -> body
      _ -> Map.put(body, :contents, contents)
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp camelize_keys(nil), do: nil

  defp camelize_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {camelize(to_string(k)), v} end)
  end

  defp camelize(str) do
    [first | rest] = String.split(str, "_")
    Enum.join([first | Enum.map(rest, &String.capitalize/1)])
  end
end
