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

echo "4. Anthropic LLM (v0.2.0)"
mix run examples/anthropic_llm.exs
echo ""

echo "5. OpenAI LLM (v0.2.0)"
mix run examples/openai_llm.exs
echo ""

echo "6. Hybrid RAG"
mix run examples/hybrid_rag.exs
echo ""

echo "7. GraphRAG (v0.2.0)"
mix run examples/graph_rag.exs
echo ""

echo "8. Agentic RAG (v0.2.0)"
mix run examples/agentic_rag.exs
echo ""

echo "=== All examples completed successfully ==="
