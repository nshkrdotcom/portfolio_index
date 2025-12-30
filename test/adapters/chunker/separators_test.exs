defmodule PortfolioIndex.Adapters.Chunker.SeparatorsTest do
  use ExUnit.Case, async: true

  alias PortfolioIndex.Adapters.Chunker.Separators

  describe "get_separators/1" do
    test "returns separators for :plain format" do
      separators = Separators.get_separators(:plain)

      assert is_list(separators)
      assert "\n\n" in separators
      assert "\n" in separators
      assert " " in separators
    end

    test "returns separators for :markdown format" do
      separators = Separators.get_separators(:markdown)

      assert is_list(separators)
      assert "\n## " in separators
      assert "\n### " in separators
      assert "\n#### " in separators
      assert "```\n\n" in separators
      # Should include fallbacks
      assert "\n\n" in separators
      assert "\n" in separators
      assert " " in separators
    end

    test "returns separators for :elixir format" do
      separators = Separators.get_separators(:elixir)

      assert is_list(separators)
      assert "\ndefmodule " in separators
      assert "\ndefprotocol " in separators
      assert "\ndefimpl " in separators
      assert "  def " in separators
      assert "  defp " in separators
      assert "  case " in separators
      assert "  cond " in separators
      # Should include fallbacks
      assert "\n\n" in separators
      assert " " in separators
    end

    test "returns separators for :ruby format" do
      separators = Separators.get_separators(:ruby)

      assert is_list(separators)
      assert "\nclass " in separators
      assert "  class " in separators
      assert "\ndef " in separators
      assert "  def " in separators
      assert "  private\n" in separators
      assert "  if " in separators
      assert "  unless " in separators
      assert "  rescue " in separators
      # Should include fallbacks
      assert "\n\n" in separators
      assert " " in separators
    end

    test "returns separators for :php format" do
      separators = Separators.get_separators(:php)

      assert is_list(separators)
      assert "\nclass " in separators
      assert "\nfunction " in separators
      assert "public function " in separators
      assert "protected function " in separators
      assert "private function " in separators
      assert "  foreach " in separators
      assert "  switch " in separators
      # Should include fallbacks
      assert "\n\n" in separators
      assert " " in separators
    end

    test "returns separators for :python format" do
      separators = Separators.get_separators(:python)

      assert is_list(separators)
      assert "\nclass " in separators
      assert "\ndef " in separators
      assert "\n\tdef " in separators
      # Should include fallbacks
      assert "\n\n" in separators
      assert " " in separators
    end

    test "returns separators for :javascript format" do
      separators = Separators.get_separators(:javascript)

      assert is_list(separators)
      assert "\nclass " in separators
      assert "\nfunction " in separators
      assert "\nexport const " in separators
      assert "\nexport default " in separators
      assert "  const " in separators
      assert "  let " in separators
      assert "  var " in separators
      assert "  switch " in separators
      # Should include fallbacks
      assert "\n\n" in separators
      assert " " in separators
    end

    test "returns separators for :typescript format (delegates to javascript)" do
      js_separators = Separators.get_separators(:javascript)
      ts_separators = Separators.get_separators(:typescript)

      assert js_separators == ts_separators
    end

    test "returns separators for :vue format" do
      separators = Separators.get_separators(:vue)

      assert is_list(separators)
      # Vue-specific
      assert "<script" in separators
      assert "<template" in separators
      assert "<section" in separators
      # Should include JavaScript separators
      assert "\nfunction " in separators
      assert "\nclass " in separators
      # Should include fallbacks
      assert "\n\n" in separators
      assert " " in separators
    end

    test "returns separators for :html format" do
      separators = Separators.get_separators(:html)

      assert is_list(separators)
      assert "<h1" in separators
      assert "<h2" in separators
      assert "<h3" in separators
      assert "<p" in separators
      assert "<ul" in separators
      assert "<article" in separators
      assert "<section" in separators
      # Should include fallbacks
      assert "\n\n" in separators
      assert " " in separators
    end

    test "returns separators for :code format (elixir alias)" do
      code_separators = Separators.get_separators(:code)
      elixir_separators = Separators.get_separators(:elixir)

      assert code_separators == elixir_separators
    end

    test "document formats use plaintext separators" do
      plain_separators = Separators.get_separators(:plain)

      for format <- [:doc, :docx, :epub, :latex, :odt, :pdf, :rtf] do
        assert Separators.get_separators(format) == plain_separators,
               "Expected #{format} to use plaintext separators"
      end
    end

    test "unknown format falls back to plaintext" do
      plain_separators = Separators.get_separators(:plain)
      unknown_separators = Separators.get_separators(:unknown_format)

      assert unknown_separators == plain_separators
    end
  end

  describe "supported_formats/0" do
    test "returns list of all supported formats" do
      formats = Separators.supported_formats()

      assert is_list(formats)
      assert :plain in formats
      assert :markdown in formats
      assert :elixir in formats
      assert :ruby in formats
      assert :php in formats
      assert :python in formats
      assert :javascript in formats
      assert :typescript in formats
      assert :vue in formats
      assert :html in formats
      assert :code in formats
      # Document formats
      assert :doc in formats
      assert :docx in formats
      assert :epub in formats
      assert :latex in formats
      assert :odt in formats
      assert :pdf in formats
      assert :rtf in formats
    end
  end

  describe "fallback_separators/0" do
    test "returns basic fallback separators" do
      fallbacks = Separators.fallback_separators()

      assert fallbacks == ["\n\n", "\n", " "]
    end
  end

  describe "separator ordering" do
    test "separators are ordered from most to least significant" do
      markdown_seps = Separators.get_separators(:markdown)

      # Headers should come before paragraphs
      h2_index = Enum.find_index(markdown_seps, &(&1 == "\n## "))
      para_index = Enum.find_index(markdown_seps, &(&1 == "\n\n"))

      assert h2_index < para_index,
             "Header separators should have higher priority than paragraph separators"
    end

    test "fallback separators are at the end" do
      for format <- [:markdown, :elixir, :ruby, :php, :python, :javascript, :html] do
        separators = Separators.get_separators(format)

        assert List.last(separators) == " ",
               "Space should be the last separator for #{format}"
      end
    end
  end

  describe "real-world splitting scenarios" do
    test "elixir separators can split module definitions" do
      code = """
      defmodule MyApp.User do
        def new(attrs) do
          %User{name: attrs[:name]}
        end

        defp validate(user) do
          # validation logic
        end
      end

      defmodule MyApp.Admin do
        def promote(user) do
          # promotion logic
        end
      end
      """

      separators = Separators.get_separators(:elixir)
      # Find first matching separator
      matching_sep = Enum.find(separators, &String.contains?(code, &1))

      assert matching_sep == "\ndefmodule ",
             "Should match on module boundary first"
    end

    test "markdown separators can split on headers" do
      markdown = """
      # Title

      Introduction paragraph.

      ## Section One

      Content for section one.

      ## Section Two

      Content for section two.
      """

      separators = Separators.get_separators(:markdown)
      matching_sep = Enum.find(separators, &String.contains?(markdown, &1))

      assert matching_sep == "\n## ",
             "Should match on H2 header first"
    end

    test "python separators can split on class and function definitions" do
      # Note: Python code without heredoc indentation
      code =
        "class User:\n    def __init__(self, name):\n        self.name = name\n\n    def greet(self):\n        return f\"Hello, {self.name}\"\n\ndef create_user(name):\n    return User(name)"

      separators = Separators.get_separators(:python)

      # Since code starts with "class", first check is for "\nclass " which won't match at position 0
      # But "\ndef " will match the create_user function
      matching_sep = Enum.find(separators, &String.contains?(code, &1))

      assert matching_sep == "\ndef ",
             "Should match on function definition"
    end

    test "javascript separators can split on exports and functions" do
      code = """
      export const API_URL = "https://api.example.com";

      export default function fetchUser(id) {
        return fetch(`${API_URL}/users/${id}`);
      }

      class UserService {
        constructor() {
          this.cache = new Map();
        }
      }
      """

      separators = Separators.get_separators(:javascript)
      # Classes have higher priority than exports
      matching_sep = Enum.find(separators, &String.contains?(code, &1))

      assert matching_sep in ["\nclass ", "\nexport const ", "\nexport default "]
    end
  end
end
