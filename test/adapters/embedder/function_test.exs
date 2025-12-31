defmodule PortfolioIndex.Adapters.Embedder.FunctionTest do
  use ExUnit.Case, async: true

  alias PortfolioIndex.Adapters.Embedder.Function

  describe "new/2" do
    test "creates embedder with function and dimensions" do
      embed_fn = fn _text -> {:ok, List.duplicate(0.1, 768)} end
      embedder = Function.new(embed_fn, dimensions: 768)

      assert %Function{} = embedder
      assert embedder.dimensions == 768
      assert is_function(embedder.embed_fn, 1)
    end

    test "requires dimensions option" do
      embed_fn = fn _text -> {:ok, List.duplicate(0.1, 768)} end

      assert_raise ArgumentError, ~r/dimensions/, fn ->
        Function.new(embed_fn, [])
      end
    end
  end

  describe "embed/3" do
    test "calls the embed function with text" do
      embedding = List.duplicate(0.1, 384)

      embed_fn = fn text ->
        assert text == "test input"
        {:ok, embedding}
      end

      embedder = Function.new(embed_fn, dimensions: 384)
      {:ok, result} = Function.embed(embedder, "test input", [])

      assert result.vector == embedding
      assert result.model == "custom"
      assert result.dimensions == 384
      assert is_integer(result.token_count)
    end

    test "propagates error from function" do
      embed_fn = fn _text -> {:error, :custom_error} end
      embedder = Function.new(embed_fn, dimensions: 384)

      assert {:error, :custom_error} = Function.embed(embedder, "test", [])
    end

    test "handles function that raises" do
      embed_fn = fn _text -> raise "Boom!" end
      embedder = Function.new(embed_fn, dimensions: 384)

      assert {:error, {:embed_failed, _}} = Function.embed(embedder, "test", [])
    end
  end

  describe "embed_batch/3" do
    test "uses batch function when provided" do
      embeddings = [
        List.duplicate(0.1, 384),
        List.duplicate(0.2, 384)
      ]

      batch_fn = fn texts ->
        assert texts == ["hello", "world"]
        {:ok, embeddings}
      end

      embed_fn = fn _text -> {:ok, List.duplicate(0.0, 384)} end
      embedder = Function.new(embed_fn, dimensions: 384, batch_fn: batch_fn)

      {:ok, result} = Function.embed_batch(embedder, ["hello", "world"], [])

      assert length(result.embeddings) == 2
      assert is_integer(result.total_tokens)
    end

    test "falls back to sequential embed when no batch function" do
      embed_fn = fn text ->
        # Return different embeddings based on text
        embedding =
          case text do
            "hello" -> List.duplicate(0.1, 384)
            "world" -> List.duplicate(0.2, 384)
          end

        {:ok, embedding}
      end

      embedder = Function.new(embed_fn, dimensions: 384)

      {:ok, result} = Function.embed_batch(embedder, ["hello", "world"], [])

      assert length(result.embeddings) == 2
      [first, second] = result.embeddings
      assert hd(first.vector) == 0.1
      assert hd(second.vector) == 0.2
    end

    test "handles empty list" do
      embed_fn = fn _text -> {:ok, List.duplicate(0.1, 384)} end
      embedder = Function.new(embed_fn, dimensions: 384)

      {:ok, result} = Function.embed_batch(embedder, [], [])

      assert result.embeddings == []
      assert result.total_tokens == 0
    end

    test "propagates first error from batch" do
      call_count = :counters.new(1, [])

      embed_fn = fn _text ->
        count = :counters.get(call_count, 1)
        :counters.add(call_count, 1, 1)

        if count == 1 do
          {:error, :second_failed}
        else
          {:ok, List.duplicate(0.1, 384)}
        end
      end

      embedder = Function.new(embed_fn, dimensions: 384)

      assert {:error, :second_failed} =
               Function.embed_batch(embedder, ["a", "b", "c"], [])
    end
  end

  describe "dimensions/2" do
    test "returns configured dimensions" do
      embed_fn = fn _text -> {:ok, List.duplicate(0.1, 768)} end
      embedder = Function.new(embed_fn, dimensions: 768)

      assert Function.dimensions(embedder, []) == 768
    end
  end

  describe "supported_models/0" do
    test "returns [\"custom\"]" do
      assert Function.supported_models() == ["custom"]
    end
  end
end
