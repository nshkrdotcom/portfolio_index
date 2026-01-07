defmodule PortfolioIndex.Adapters.LLM.CodexTest do
  use PortfolioIndex.SupertesterCase, async: true

  import Mox

  alias PortfolioIndex.Adapters.LLM.Codex

  setup :verify_on_exit!

  describe "complete/2" do
    test "returns content using the configured sdk" do
      original_config = Application.get_env(:portfolio_index, :codex)
      Application.put_env(:portfolio_index, :codex, model: "gpt-4o-mini")

      on_exit(fn ->
        if is_nil(original_config) do
          Application.delete_env(:portfolio_index, :codex)
        else
          Application.put_env(:portfolio_index, :codex, original_config)
        end
      end)

      CodexSdkMock
      |> expect(:complete, fn messages, opts ->
        assert [%{role: "user", content: "Hi"}] = messages
        assert Keyword.get(opts, :model) == "gpt-4o-mini"

        {:ok,
         %{
           content: "Hello from Codex",
           model: "gpt-4o-mini",
           usage: %{input_tokens: 1, output_tokens: 2},
           finish_reason: "stop"
         }}
      end)

      {:ok, result} = Codex.complete([%{role: :user, content: "Hi"}])

      assert result.content == "Hello from Codex"
      assert result.model == "gpt-4o-mini"
      assert result.finish_reason == :stop
    end
  end

  describe "stream/2" do
    test "streams chunks using the configured sdk" do
      CodexSdkMock
      |> expect(:stream, fn messages, _opts ->
        assert [%{role: "user", content: "Stream"}] = messages
        ["Hello", " ", "Codex"]
      end)

      {:ok, stream} = Codex.stream([%{role: :user, content: "Stream"}])
      chunks = Enum.to_list(stream)

      assert Enum.map(chunks, & &1.delta) == ["Hello", " ", "Codex"]
    end
  end

  describe "complete/2 live" do
    if System.get_env("CODEX_API_KEY") || System.get_env("OPENAI_API_KEY") do
      @tag :live
      test "completes messages via Codex SDK" do
        original_sdk = Application.get_env(:portfolio_index, :codex_sdk)
        Application.put_env(:portfolio_index, :codex_sdk, CodexSdk)

        on_exit(fn ->
          Application.put_env(:portfolio_index, :codex_sdk, original_sdk)
        end)

        {:ok, result} =
          Codex.complete([%{role: :user, content: "Say hello in one word"}], max_tokens: 10)

        assert is_binary(result.content)
        assert result.model != nil
      end
    else
      @tag :live
      @tag skip: "CODEX_API_KEY or OPENAI_API_KEY is not set"
      test "completes messages via Codex SDK" do
        :ok
      end
    end
  end
end
