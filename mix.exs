defmodule PortfolioIndex.MixProject do
  use Mix.Project

  @version "0.5.0"
  @source_url "https://github.com/nshkrdotcom/portfolio_index"

  def project do
    [
      app: :portfolio_index,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      name: "PortfolioIndex",
      source_url: @source_url,
      aliases: aliases(),
      elixirc_paths: elixirc_paths(Mix.env()),
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        plt_add_apps: [:mix],
        flags: [:error_handling, :unknown, :unmatched_returns]
      ],
      test_coverage: [tool: ExCoveralls]
    ]
  end

  def cli do
    [
      preferred_envs: [
        "test.watch": :test,
        coveralls: :test,
        "coveralls.html": :test
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {PortfolioIndex.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Core dependency
      {:portfolio_core, path: "../portfolio_core"},

      # Agent session management
      {:agent_session_manager, "~> 0.1.1"},

      # Resilience primitives (rate limiting, retry, backoff)
      {:foundation, "~> 0.2.0"},

      # Database adapters
      {:ecto_sql, "~> 3.11"},
      {:postgrex, "~> 0.17"},
      {:pgvector, "~> 0.2"},
      {:hnswlib, "~> 0.1.6"},

      # Graph database
      {:boltx, "~> 0.0.6"},

      # AI/LLM (path for local dev)
      {:gemini_ex, "~> 0.9.1"},
      {:claude_agent_sdk, "~> 0.9.2"},
      {:codex_sdk, "~> 0.6.0"},
      {:ollixir, "~> 0.1.0"},
      {:vllm, "~> 0.2.1", optional: true},
      {:openai_ex, "~> 0.9.18"},

      # HTTP clients for APIs
      {:req, "~> 0.5"},
      {:finch, "~> 0.18"},

      # Pipeline processing
      {:broadway, "~> 1.0"},
      {:gen_stage, "~> 1.2"},

      # Telemetry
      {:telemetry, "~> 1.2"},
      {:telemetry_metrics, "~> 1.1"},
      {:telemetry_poller, "~> 1.0"},

      # JSON
      {:jason, "~> 1.4"},

      # Configuration validation
      {:nimble_options, "~> 1.1"},

      # Dev/test only
      {:ex_doc, "~> 0.40.0", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:mox, "~> 1.1", only: :test},
      {:excoveralls, "~> 0.18", only: :test},
      {:bypass, "~> 2.1", only: :test},
      {:supertester, "~> 0.5.1", only: :test}
    ]
  end

  defp description do
    "Production adapters and pipelines for PortfolioCore. Vector stores, graph stores, embedders, Broadway pipelines, and advanced RAG strategies."
  end

  defp package do
    [
      name: "portfolio_index",
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      maintainers: ["NSHKR"],
      files: ~w(lib guides assets .formatter.exs mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: @source_url,
      source_ref: "v#{@version}",
      assets: %{"assets" => "assets"},
      logo: "assets/portfolio_index.svg",
      extras: [
        "README.md",
        "guides/getting-started.md",
        "guides/vector-stores.md",
        "guides/graph-stores.md",
        "guides/embedders.md",
        "guides/llm-adapters.md",
        "guides/rag-strategies.md",
        "guides/chunkers.md",
        "guides/pipelines.md",
        "guides/agent-sessions.md",
        "guides/vcs.md",
        "guides/telemetry.md",
        "guides/evaluation.md",
        "guides/maintenance.md",
        "guides/configuration.md",
        "guides/testing.md",
        "CHANGELOG.md",
        "LICENSE"
      ],
      groups_for_extras: [
        "Getting Started": [
          "README.md",
          "guides/getting-started.md",
          "guides/configuration.md"
        ],
        Adapters: [
          "guides/vector-stores.md",
          "guides/graph-stores.md",
          "guides/embedders.md",
          "guides/llm-adapters.md",
          "guides/chunkers.md"
        ],
        "RAG & Retrieval": [
          "guides/rag-strategies.md",
          "guides/pipelines.md",
          "guides/evaluation.md"
        ],
        "Agent & VCS": [
          "guides/agent-sessions.md",
          "guides/vcs.md"
        ],
        Operations: [
          "guides/telemetry.md",
          "guides/maintenance.md",
          "guides/testing.md"
        ],
        "Release Notes": [
          "CHANGELOG.md",
          "LICENSE"
        ]
      ],
      groups_for_modules: [
        "Vector Store Adapters": ~r/PortfolioIndex\.Adapters\.VectorStore\./,
        "Vector Store Utilities": ~r/PortfolioIndex\.VectorStore\./,
        "Graph Store Adapters": ~r/PortfolioIndex\.Adapters\.GraphStore\./,
        Embedders: ~r/PortfolioIndex\.Adapters\.Embedder\./,
        "Embedder Utilities": ~r/PortfolioIndex\.Embedder\./,
        LLMs: ~r/PortfolioIndex\.Adapters\.LLM\./,
        Chunkers: ~r/PortfolioIndex\.Adapters\.Chunker\./,
        Rerankers: ~r/PortfolioIndex\.Adapters\.Reranker\./,
        "Agent Sessions": ~r/PortfolioIndex\.Adapters\.AgentSession\./,
        "Version Control": ~r/PortfolioIndex\.Adapters\.VCS\./,
        "Query Processing": ~r/PortfolioIndex\.Adapters\.Query/,
        "Collection Selection": ~r/PortfolioIndex\.Adapters\.CollectionSelector\./,
        Pipelines: ~r/PortfolioIndex\.Pipelines\./,
        "RAG Strategies": ~r/PortfolioIndex\.RAG\./,
        GraphRAG: ~r/PortfolioIndex\.GraphRAG\./,
        Schemas: ~r/PortfolioIndex\.Schemas\./,
        Evaluation: ~r/PortfolioIndex\.Evaluation/,
        Maintenance: ~r/PortfolioIndex\.Maintenance/,
        Telemetry: ~r/PortfolioIndex\.Telemetry/
      ]
    ]
  end

  defp aliases do
    [
      quality: ["format --check-formatted", "credo --strict", "dialyzer"],
      "test.all": ["quality", "test"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"]
    ]
  end
end
