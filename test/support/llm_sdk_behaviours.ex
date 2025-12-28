defmodule PortfolioIndex.Test.ClaudeAgentSdkBehaviour do
  @moduledoc "Behaviour for Claude agent SDK mocks in tests."

  @callback complete(list(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback stream(list(), (term() -> any()), keyword()) ::
              :ok | {:ok, term()} | {:error, term()}
end

defmodule PortfolioIndex.Test.CodexSdkBehaviour do
  @moduledoc "Behaviour for Codex SDK mocks in tests."

  @callback complete(list(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback stream(list(), (term() -> any()), keyword()) ::
              :ok | {:ok, term()} | {:error, term()}
end
