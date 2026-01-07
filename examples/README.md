# Examples

This directory contains runnable scripts demonstrating Portfolio Index adapters and RAG strategies.

## Requirements

- PostgreSQL with pgvector running
- Run `mix ecto.migrate` to create required tables (documents + vector index registry)
- Neo4j running
- Provider API keys configured (Gemini, Claude, OpenAI, Codex)

Set environment variables as needed:

```bash
export GEMINI_API_KEY=your-key
export ANTHROPIC_API_KEY=your-key
export OPENAI_API_KEY=your-key
export CODEX_API_KEY=your-key  # or OPENAI_API_KEY for Codex SDK
```

## Run a single example

```bash
mix run examples/gemini_llm.exs
```

## Run everything

```bash
./examples/run_all.sh
```
