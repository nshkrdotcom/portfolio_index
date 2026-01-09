# Examples

This directory contains runnable scripts demonstrating Portfolio Index adapters and RAG strategies.

## Requirements

- PostgreSQL with pgvector running
- Run `mix ecto.migrate` to create required tables (documents + vector index registry)
- Neo4j running
- Provider API keys configured (Gemini, Claude, OpenAI, Codex)
- Ollama running locally for the Ollama examples
- vLLM optional (not run by default)

Set environment variables as needed:

```bash
export GEMINI_API_KEY=your-key
export ANTHROPIC_API_KEY=your-key
export OPENAI_API_KEY=your-key
export CODEX_API_KEY=your-key  # or OPENAI_API_KEY for Codex SDK
export OLLAMA_BASE_URL=http://localhost:11434/api
export VLLM_BASE_URL=http://localhost:8000/v1
```

## Ollama setup

The Ollama examples expect these models to be installed:

- `llama3.2` (LLM)
- `nomic-embed-text` (embeddings)

Install them with either:

```bash
ollama pull llama3.2
ollama pull nomic-embed-text
```

Or:

```bash
mix run examples/ollama_setup.exs
```

## Run a single example

```bash
mix run examples/gemini_llm.exs
```

## Run everything

```bash
./examples/run_all.sh
```

Note: `run_all.sh` skips the vLLM example by default. Run it manually when vLLM is available:

```bash
mix run examples/vllm_llm.exs
```
