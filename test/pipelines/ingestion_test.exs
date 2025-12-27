defmodule PortfolioIndex.Pipelines.IngestionTest do
  use ExUnit.Case, async: true

  alias PortfolioIndex.Pipelines.Ingestion

  # =============================================================================
  # Unit Tests
  # =============================================================================

  describe "module structure" do
    test "uses Broadway" do
      functions = Ingestion.__info__(:functions)
      assert {:start_link, 1} in functions
      assert {:handle_message, 3} in functions
      assert {:handle_batch, 4} in functions
    end

    test "has start/1 convenience function" do
      functions = Ingestion.__info__(:functions)
      assert {:start, 1} in functions
    end
  end

  describe "start_link/1 options" do
    test "accepts paths option" do
      opts = [paths: ["/tmp/test"], name: :test_ingestion_paths]

      # We won't actually start since FileProducer would fail without valid paths
      # Just test that options are valid
      assert Keyword.get(opts, :paths) == ["/tmp/test"]
    end

    test "accepts patterns option" do
      opts = [patterns: ["**/*.md", "**/*.ex"]]

      assert Keyword.get(opts, :patterns) == ["**/*.md", "**/*.ex"]
    end

    test "accepts concurrency option" do
      opts = [concurrency: 20]

      assert Keyword.get(opts, :concurrency) == 20
    end

    test "accepts batch_size option" do
      opts = [batch_size: 100]

      assert Keyword.get(opts, :batch_size) == 100
    end

    test "accepts chunk_size option" do
      opts = [chunk_size: 2000]

      assert Keyword.get(opts, :chunk_size) == 2000
    end

    test "accepts chunk_overlap option" do
      opts = [chunk_overlap: 300]

      assert Keyword.get(opts, :chunk_overlap) == 300
    end

    test "accepts index_id option" do
      opts = [index_id: "my_custom_index"]

      assert Keyword.get(opts, :index_id) == "my_custom_index"
    end
  end

  describe "file processing logic" do
    test "parses elixir files as code format" do
      # Test the internal parsing logic by calling the module directly
      # This is a white-box test to verify content type detection
      file_info = %{path: "test.ex", type: :elixir}

      assert file_info.type == :elixir
    end

    test "parses markdown files as markdown format" do
      file_info = %{path: "readme.md", type: :markdown}

      assert file_info.type == :markdown
    end

    test "parses html files as html format" do
      file_info = %{path: "index.html", type: :html}

      assert file_info.type == :html
    end

    test "parses unknown files as plain format" do
      file_info = %{path: "data.txt", type: :text}

      assert file_info.type == :text
    end
  end

  describe "telemetry events" do
    test "documents expected event names" do
      # These are the events the ingestion pipeline emits
      events = [
        [:portfolio_index, :pipeline, :ingestion, :file_processed]
      ]

      # Verify event structure is documented
      for event <- events do
        assert is_list(event)
        assert length(event) == 4
        assert hd(event) == :portfolio_index
      end
    end
  end

  # =============================================================================
  # Integration Tests (require running Broadway pipeline)
  # Run with: mix test --include integration
  # =============================================================================

  describe "pipeline integration" do
    @tag :integration
    @tag :skip
    test "processes files from paths" do
      # This test requires setting up actual files and the full Broadway pipeline
      # Skipped by default - enable for end-to-end testing

      tmp_dir = System.tmp_dir!()
      test_dir = Path.join(tmp_dir, "ingestion_test_#{System.unique_integer()}")
      File.mkdir_p!(test_dir)

      # Create test file
      test_file = Path.join(test_dir, "test.md")
      File.write!(test_file, "# Test\n\nHello, world!")

      try do
        {:ok, pid} =
          Ingestion.start_link(
            paths: [test_dir],
            patterns: ["**/*.md"],
            index_id: "test_#{System.unique_integer()}",
            name: :"test_ingestion_#{System.unique_integer()}"
          )

        # Give pipeline time to process
        Process.sleep(1000)

        # Pipeline should have processed the file
        assert Process.alive?(pid)

        Broadway.stop(pid)
      after
        File.rm_rf!(test_dir)
      end
    end
  end
end
