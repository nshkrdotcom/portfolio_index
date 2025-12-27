defmodule PortfolioIndex.Fixtures do
  @moduledoc """
  Test fixtures for PortfolioIndex tests.
  """

  @doc """
  Generate a random vector of specified dimensions.
  """
  def random_vector(dimensions \\ 768) do
    for _ <- 1..dimensions, do: :rand.uniform() - 0.5
  end

  @doc """
  Generate a normalized random vector.
  """
  def random_normalized_vector(dimensions \\ 768) do
    vector = random_vector(dimensions)
    magnitude = :math.sqrt(Enum.reduce(vector, 0, fn x, acc -> acc + x * x end))
    Enum.map(vector, fn x -> x / magnitude end)
  end

  @doc """
  Sample document content for testing.
  """
  def sample_document do
    """
    # Introduction to Elixir

    Elixir is a dynamic, functional language for building scalable and maintainable applications.

    ## Features

    - Functional programming paradigm
    - Runs on the Erlang VM (BEAM)
    - Excellent concurrency support
    - Pattern matching
    - Metaprogramming with macros

    ## Example

    ```elixir
    defmodule Hello do
      def world do
        IO.puts("Hello, World!")
      end
    end
    ```
    """
  end

  @doc """
  Sample Elixir code for testing.
  """
  def sample_code do
    """
    defmodule MyApp.Calculator do
      @moduledoc \"\"\"
      A simple calculator module.
      \"\"\"

      def add(a, b), do: a + b

      def subtract(a, b), do: a - b

      def multiply(a, b), do: a * b

      def divide(a, b) when b != 0, do: a / b
      def divide(_, 0), do: {:error, :division_by_zero}
    end
    """
  end

  @doc """
  Generate sample chunks from content.
  """
  def sample_chunks(content, count \\ 3) do
    chunk_size = div(String.length(content), count)

    for i <- 0..(count - 1) do
      start = i * chunk_size
      chunk_content = String.slice(content, start, chunk_size)

      %{
        content: chunk_content,
        index: i,
        start_offset: start,
        end_offset: start + String.length(chunk_content),
        metadata: %{format: :markdown}
      }
    end
  end

  @doc """
  Generate a sample embedding result.
  """
  def sample_embedding_result(dimensions \\ 768) do
    %{
      vector: random_normalized_vector(dimensions),
      model: Gemini.Config.default_embedding_model(),
      dimensions: dimensions,
      token_count: :rand.uniform(100) + 10
    }
  end

  @doc """
  Generate sample search results.
  """
  def sample_search_results(count \\ 5) do
    for i <- 1..count do
      %{
        id: "doc_#{i}",
        score: 1.0 - i * 0.1,
        metadata: %{
          source: "/path/to/doc_#{i}.md",
          content: "Sample content for document #{i}"
        },
        vector: nil
      }
    end
  end

  @doc """
  Generate a sample graph node.
  """
  def sample_node(id \\ "node_1") do
    %{
      id: id,
      labels: ["Function", "Public"],
      properties: %{
        name: "sample_function",
        arity: 2,
        module: "MyApp.Module"
      }
    }
  end

  @doc """
  Generate a sample graph edge.
  """
  def sample_edge(from_id \\ "node_1", to_id \\ "node_2") do
    %{
      id: "edge_#{from_id}_#{to_id}",
      type: "CALLS",
      from_id: from_id,
      to_id: to_id,
      properties: %{
        count: 5
      }
    }
  end

  @doc """
  Generate a complete sample graph with nodes and edges.
  """
  def sample_graph(node_count \\ 5) do
    nodes =
      for i <- 1..node_count do
        %{
          id: "node_#{i}",
          labels: ["Function"],
          properties: %{
            name: "func_#{i}",
            module: "MyApp.Module#{div(i, 2) + 1}"
          }
        }
      end

    # Create a chain of edges: 1->2->3->4->5
    edges =
      for i <- 1..(node_count - 1) do
        %{
          id: "edge_#{i}_#{i + 1}",
          type: "CALLS",
          from_id: "node_#{i}",
          to_id: "node_#{i + 1}",
          properties: %{weight: :rand.uniform()}
        }
      end

    %{nodes: nodes, edges: edges}
  end

  @doc """
  Generate a sample vector store search result.
  """
  def sample_vector_result(id, score \\ 0.95) do
    %{
      id: id,
      score: score,
      metadata: %{
        content: "Sample content for #{id}",
        source: "/path/to/#{id}.md"
      }
    }
  end

  @doc """
  Generate sample LLM messages.
  """
  def sample_messages do
    [
      %{role: :system, content: "You are a helpful assistant."},
      %{role: :user, content: "What is Elixir?"}
    ]
  end

  @doc """
  Generate a sample LLM completion result.
  """
  def sample_completion_result do
    %{
      content:
        "Elixir is a dynamic, functional programming language designed for building scalable and maintainable applications.",
      model: Gemini.Config.default_model(),
      usage: %{
        input_tokens: 15,
        output_tokens: 25
      },
      finish_reason: :stop
    }
  end
end
