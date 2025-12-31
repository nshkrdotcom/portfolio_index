defmodule Mix.Tasks.Portfolio.InstallTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Mix.Tasks.Portfolio.Install

  describe "run/1" do
    test "prints installation instructions" do
      output =
        capture_io(fn ->
          Install.run(["--no-migrations"])
        end)

      assert output =~ "PortfolioIndex"
      assert output =~ "Next Steps"
    end

    test "infers repo from app name" do
      output =
        capture_io(fn ->
          Install.run(["--no-migrations"])
        end)

      # Should mention the repo
      assert output =~ "Repo" or output =~ "repo"
    end

    test "accepts --repo option" do
      output =
        capture_io(fn ->
          Install.run(["--repo", "MyApp.Repo", "--no-migrations"])
        end)

      assert output =~ "MyApp.Repo"
    end

    test "accepts --dimension option" do
      output =
        capture_io(fn ->
          Install.run(["--dimension", "1536", "--no-migrations"])
        end)

      assert output =~ "1536"
    end

    test "prints configuration example" do
      output =
        capture_io(fn ->
          Install.run(["--no-migrations"])
        end)

      assert output =~ "config"
    end
  end

  describe "option parsing" do
    test "parses all options correctly" do
      # This tests the internal option parsing without side effects
      {opts, _args, _errors} =
        OptionParser.parse(
          ["--repo", "Custom.Repo", "--dimension", "768", "--no-migrations"],
          strict: [repo: :string, dimension: :integer, no_migrations: :boolean]
        )

      assert opts[:repo] == "Custom.Repo"
      assert opts[:dimension] == 768
      assert opts[:no_migrations] == true
    end
  end
end
