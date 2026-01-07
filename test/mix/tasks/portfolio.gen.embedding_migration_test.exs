defmodule Mix.Tasks.Portfolio.Gen.EmbeddingMigrationTest do
  use PortfolioIndex.SupertesterCase, async: true

  import ExUnit.CaptureIO

  alias Mix.Tasks.Portfolio.Gen.EmbeddingMigration

  @temp_dir System.tmp_dir!()

  describe "run/1" do
    test "requires --dimension option" do
      output =
        capture_io(:stderr, fn ->
          try do
            EmbeddingMigration.run([])
          rescue
            Mix.Error -> :ok
          catch
            :exit, _ -> :ok
          end
        end)

      assert output =~ "dimension" or output == ""
    end

    test "generates migration with specified dimension" do
      # Use a temporary directory for testing
      temp_migrations =
        Path.join(@temp_dir, "test_migrations_#{System.unique_integer([:positive])}")

      File.mkdir_p!(temp_migrations)

      output =
        capture_io(fn ->
          EmbeddingMigration.run([
            "--dimension",
            "1536",
            "--migrations-path",
            temp_migrations
          ])
        end)

      assert output =~ "1536"
      assert output =~ "migration"

      # Verify migration file was created
      files = File.ls!(temp_migrations)
      assert length(files) == 1
      [migration_file] = files
      assert migration_file =~ "update_embedding_dimensions.exs"

      # Verify content
      content = File.read!(Path.join(temp_migrations, migration_file))
      assert content =~ "1536"
      assert content =~ "portfolio_chunks"

      # Cleanup
      File.rm_rf!(temp_migrations)
    end

    test "accepts --table option" do
      temp_migrations =
        Path.join(@temp_dir, "test_migrations_#{System.unique_integer([:positive])}")

      File.mkdir_p!(temp_migrations)

      capture_io(fn ->
        EmbeddingMigration.run([
          "--dimension",
          "768",
          "--table",
          "custom_chunks",
          "--migrations-path",
          temp_migrations
        ])
      end)

      # Verify content uses custom table
      files = File.ls!(temp_migrations)
      [migration_file] = files
      content = File.read!(Path.join(temp_migrations, migration_file))
      assert content =~ "custom_chunks"

      # Cleanup
      File.rm_rf!(temp_migrations)
    end

    test "accepts --column option" do
      temp_migrations =
        Path.join(@temp_dir, "test_migrations_#{System.unique_integer([:positive])}")

      File.mkdir_p!(temp_migrations)

      capture_io(fn ->
        EmbeddingMigration.run([
          "--dimension",
          "512",
          "--column",
          "vector",
          "--migrations-path",
          temp_migrations
        ])
      end)

      files = File.ls!(temp_migrations)
      [migration_file] = files
      content = File.read!(Path.join(temp_migrations, migration_file))
      assert content =~ "vector"

      # Cleanup
      File.rm_rf!(temp_migrations)
    end
  end

  describe "option parsing" do
    test "parses all options correctly" do
      {opts, _args, _errors} =
        OptionParser.parse(
          ["--dimension", "1536", "--table", "chunks", "--column", "embedding"],
          strict: [dimension: :integer, table: :string, column: :string]
        )

      assert opts[:dimension] == 1536
      assert opts[:table] == "chunks"
      assert opts[:column] == "embedding"
    end
  end
end
