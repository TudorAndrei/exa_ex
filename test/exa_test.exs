defmodule ExaTest do
  use ExUnit.Case, async: true

  defmodule FakeExa do
    use Plug.Router

    plug Plug.Parsers,
      parsers: [:json],
      pass: ["application/json"],
      json_decoder: Jason

    plug :match
    plug :dispatch

    defp json_resp(conn, status, data) do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(status, Jason.encode!(data))
    end

    post "/search" do
      body = conn.body_params

      json_resp(conn, 200, %{
        requestId: "test-123",
        results: [
          %{
            title: "Test Result",
            url: "https://example.com",
            id: "https://example.com",
            score: 0.95,
            publishedDate: "2026-01-01",
            text: if(body["contents"]["text"], do: "Full text content", else: nil)
          }
        ],
        searchType: "neural"
      })
    end

    post "/findSimilar" do
      json_resp(conn, 200, %{
        requestId: "test-456",
        results: [
          %{
            title: "Similar Result",
            url: "https://similar.com",
            id: "https://similar.com",
            score: 0.88
          }
        ]
      })
    end

    post "/contents" do
      body = conn.body_params

      json_resp(conn, 200, %{
        requestId: "test-789",
        results:
          Enum.map(body["urls"], fn url ->
            %{
              title: "Content for #{url}",
              url: url,
              id: url,
              text: "Page content here"
            }
          end)
      })
    end

    post "/answer" do
      body = conn.body_params

      json_resp(conn, 200, %{
        answer: "The answer to: #{body["query"]}",
        citations: [
          %{
            id: "https://source.com",
            url: "https://source.com",
            title: "Source"
          }
        ]
      })
    end

    match _ do
      send_resp(conn, 404, "not found")
    end
  end

  setup do
    port = free_port()
    start_supervised!({Bandit, plug: FakeExa, scheme: :http, port: port})
    client = Exa.client("test-api-key", base_url: "http://127.0.0.1:#{port}")
    %{client: client}
  end

  describe "search/3" do
    test "performs a basic search", %{client: client} do
      assert {:ok, result} = Exa.search(client, "test query")
      assert result["requestId"] == "test-123"
      assert [%{"title" => "Test Result"}] = result["results"]
    end

    test "passes content options", %{client: client} do
      assert {:ok, result} = Exa.search(client, "test query", text: true)
      assert [%{"text" => "Full text content"}] = result["results"]
    end
  end

  describe "find_similar/3" do
    test "finds similar pages", %{client: client} do
      assert {:ok, result} = Exa.find_similar(client, "https://example.com")
      assert result["requestId"] == "test-456"
      assert [%{"title" => "Similar Result"}] = result["results"]
    end
  end

  describe "get_contents/3" do
    test "fetches contents for URLs", %{client: client} do
      assert {:ok, result} = Exa.get_contents(client, ["https://example.com"], text: true)
      assert result["requestId"] == "test-789"
      assert [%{"text" => "Page content here"}] = result["results"]
    end
  end

  describe "answer/3" do
    test "generates an answer", %{client: client} do
      assert {:ok, result} = Exa.answer(client, "What is Elixir?")
      assert result["answer"] == "The answer to: What is Elixir?"
      assert [%{"title" => "Source"}] = result["citations"]
    end
  end

  describe "client/1" do
    test "creates a client with API key" do
      client = Exa.client("my-key")
      assert %Req.Request{} = client
    end
  end

  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, port} = :inet.port(socket)
    :ok = :gen_tcp.close(socket)
    port
  end
end
