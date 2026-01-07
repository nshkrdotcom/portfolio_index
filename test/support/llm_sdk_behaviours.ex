defmodule PortfolioIndex.Test.ClaudeAgentSdkBehaviour do
  @moduledoc "Behaviour for Claude agent SDK mocks in tests."

  @callback complete(list(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback stream(list(), keyword()) :: {:ok, term()} | {:error, term()} | term()
  @callback stream(list(), (term() -> any()), keyword()) ::
              :ok | {:ok, term()} | {:error, term()}
end

defmodule PortfolioIndex.Test.CodexSdkBehaviour do
  @moduledoc "Behaviour for Codex SDK mocks in tests."

  @callback complete(list(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback stream(list(), keyword()) :: {:ok, term()} | {:error, term()} | term()
  @callback stream(list(), (term() -> any()), keyword()) ::
              :ok | {:ok, term()} | {:error, term()}
end

defmodule PortfolioIndex.Test.GeminiSdkBehaviour do
  @moduledoc "Behaviour for Gemini SDK mocks in tests."

  @callback generate(String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  @callback extract_text(term()) :: {:ok, String.t()} | {:error, term()}
  @callback stream_generate(String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  @callback embed_content(String.t(), keyword()) :: {:ok, term()} | {:error, term()}
end
