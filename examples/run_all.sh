#!/bin/bash
set -e

echo "=== Portfolio Index Examples ==="
echo ""

echo "1. Pgvector Vector Store"
mix run examples/pgvector_usage.exs
echo ""

echo "2. Neo4j Graph Store"
mix run examples/neo4j_usage.exs
echo ""

echo "3. Gemini Embedder"
mix run examples/gemini_embedder.exs
echo ""

echo "4. Ollama Embedder"
mix run examples/ollama_embedder.exs
echo ""

echo "5. Gemini LLM"
mix run examples/gemini_llm.exs
echo ""

echo "6. Anthropic LLM"
mix run examples/anthropic_llm.exs
echo ""

echo "7. OpenAI LLM"
mix run examples/openai_llm.exs
echo ""

echo "8. Codex LLM"
mix run examples/codex_llm.exs
echo ""

echo "9. Ollama LLM"
mix run examples/ollama_llm.exs
echo ""

echo "vLLM example skipped by default. Run: mix run examples/vllm_llm.exs"
echo ""

echo "10. Hybrid RAG"
mix run examples/hybrid_rag.exs
echo ""

echo "11. GraphRAG"
mix run examples/graph_rag.exs
echo ""

echo "12. Agentic RAG"
mix run examples/agentic_rag.exs
echo ""

echo "=== All examples completed successfully ==="
