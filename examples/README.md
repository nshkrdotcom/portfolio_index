# Examples

This directory contains runnable scripts demonstrating Portfolio Index adapters and RAG strategies.

## Requirements

- PostgreSQL with pgvector running
- Run `mix ecto.migrate` to create required tables (documents + vector index registry)
- Neo4j running
- Provider API keys configured (see the Gemini, claude_agent_sdk, and codex_sdk docs)

## Run a single example

```bash
mix run examples/anthropic_llm.exs
```

## Run everything

```bash
./examples/run_all.sh
```
