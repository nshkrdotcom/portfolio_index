defmodule PortfolioIndex.Adapters.Chunker.RecursiveTest do
  use ExUnit.Case, async: true

  alias PortfolioIndex.Adapters.Chunker.Recursive

  describe "chunk/3 basic" do
    test "chunks plain text" do
      text = String.duplicate("Hello world. ", 100)
      config = %{chunk_size: 100, chunk_overlap: 20}

      assert {:ok, chunks} = Recursive.chunk(text, :plain, config)
      assert length(chunks) > 1

      Enum.each(chunks, fn chunk ->
        assert is_binary(chunk.content)
        assert is_integer(chunk.index)
        assert is_integer(chunk.start_offset)
        assert is_integer(chunk.end_offset)
        assert is_map(chunk.metadata)
      end)
    end

    test "chunks markdown with header awareness" do
      text = """
      # Main Title

      Introduction paragraph here.

      ## Section One

      Content for section one.

      ## Section Two

      Content for section two.
      """

      config = %{chunk_size: 50, chunk_overlap: 10}

      assert {:ok, chunks} = Recursive.chunk(text, :markdown, config)
      assert chunks != []

      # Check that chunks have markdown format in metadata
      Enum.each(chunks, fn chunk ->
        assert chunk.metadata.format == :markdown
      end)
    end

    test "chunks code with function awareness" do
      text = """
      defmodule MyApp do
        def hello do
          :world
        end

        defp private_fn do
          :secret
        end
      end
      """

      config = %{chunk_size: 100, chunk_overlap: 20}

      assert {:ok, chunks} = Recursive.chunk(text, :code, config)
      assert chunks != []
    end

    test "returns single chunk for small text" do
      text = "Small text"
      config = %{chunk_size: 1000, chunk_overlap: 100}

      assert {:ok, chunks} = Recursive.chunk(text, :plain, config)
      assert length(chunks) == 1
      assert hd(chunks).content == text
    end

    test "handles empty text" do
      config = %{chunk_size: 100, chunk_overlap: 20}

      assert {:ok, chunks} = Recursive.chunk("", :plain, config)
      assert chunks == [] or (length(chunks) == 1 and hd(chunks).content == "")
    end
  end

  describe "estimate_chunks/2" do
    test "estimates chunk count for text" do
      text = String.duplicate("a", 1000)
      config = %{chunk_size: 100, chunk_overlap: 20}

      estimate = Recursive.estimate_chunks(text, config)
      assert estimate > 1
      assert is_integer(estimate)
    end

    test "returns 1 for small text" do
      text = "Small text"
      config = %{chunk_size: 1000, chunk_overlap: 100}

      assert Recursive.estimate_chunks(text, config) == 1
    end
  end

  describe "language format support" do
    test "chunks elixir code" do
      text = """
      defmodule MyApp.User do
        @moduledoc "User module"

        def new(attrs) do
          %User{name: attrs[:name]}
        end

        defp validate(user) do
          if user.name, do: :ok, else: :error
        end
      end

      defmodule MyApp.Admin do
        def promote(user), do: {:ok, user}
      end
      """

      config = %{chunk_size: 150, chunk_overlap: 20}

      assert {:ok, chunks} = Recursive.chunk(text, :elixir, config)
      refute Enum.empty?(chunks)
      assert Enum.all?(chunks, &(&1.metadata.format == :elixir))
    end

    test "chunks ruby code" do
      # Using sigil to avoid @ being interpreted as module attribute
      text = ~S"""
      class User
        def initialize(name)
          @name = name
        end

        def greet
          "Hello, #{@name}"
        end

        private

        def validate
          raise "Invalid" unless @name
        end
      end

      class Admin < User
        def promote
          true
        end
      end
      """

      config = %{chunk_size: 150, chunk_overlap: 20}

      assert {:ok, chunks} = Recursive.chunk(text, :ruby, config)
      refute Enum.empty?(chunks)
      assert Enum.all?(chunks, &(&1.metadata.format == :ruby))
    end

    test "chunks php code" do
      text = """
      <?php
      class User {
          private $name;

          public function __construct($name) {
              $this->name = $name;
          }

          public function greet() {
              return "Hello, " . $this->name;
          }

          protected function validate() {
              if (!$this->name) {
                  throw new Exception("Invalid");
              }
          }
      }
      ?>
      """

      config = %{chunk_size: 150, chunk_overlap: 20}

      assert {:ok, chunks} = Recursive.chunk(text, :php, config)
      refute Enum.empty?(chunks)
      assert Enum.all?(chunks, &(&1.metadata.format == :php))
    end

    test "chunks python code" do
      text = """
      class User:
          def __init__(self, name):
              self.name = name

          def greet(self):
              return f"Hello, {self.name}"

      def create_user(name):
          return User(name)

      class Admin(User):
          def promote(self):
              return True
      """

      config = %{chunk_size: 150, chunk_overlap: 20}

      assert {:ok, chunks} = Recursive.chunk(text, :python, config)
      refute Enum.empty?(chunks)
      assert Enum.all?(chunks, &(&1.metadata.format == :python))
    end

    test "chunks javascript code" do
      text = """
      export const API_URL = "https://api.example.com";

      export default function fetchUser(id) {
        return fetch(`${API_URL}/users/${id}`);
      }

      class UserService {
        constructor() {
          this.cache = new Map();
        }

        async getUser(id) {
          if (this.cache.has(id)) {
            return this.cache.get(id);
          }
          const user = await fetchUser(id);
          this.cache.set(id, user);
          return user;
        }
      }
      """

      config = %{chunk_size: 200, chunk_overlap: 30}

      assert {:ok, chunks} = Recursive.chunk(text, :javascript, config)
      refute Enum.empty?(chunks)
      assert Enum.all?(chunks, &(&1.metadata.format == :javascript))
    end

    test "chunks typescript code (same as javascript)" do
      text = """
      interface User {
        id: number;
        name: string;
      }

      export const API_URL: string = "https://api.example.com";

      export function fetchUser(id: number): Promise<User> {
        return fetch(`${API_URL}/users/${id}`).then(r => r.json());
      }

      class UserService {
        private cache: Map<number, User> = new Map();

        async getUser(id: number): Promise<User> {
          return this.cache.get(id) || fetchUser(id);
        }
      }
      """

      config = %{chunk_size: 200, chunk_overlap: 30}

      assert {:ok, chunks} = Recursive.chunk(text, :typescript, config)
      refute Enum.empty?(chunks)
      assert Enum.all?(chunks, &(&1.metadata.format == :typescript))
    end

    test "chunks vue SFC" do
      text = """
      <template>
        <div class="user">
          <h1>{{ user.name }}</h1>
          <p>{{ user.email }}</p>
        </div>
      </template>

      <script>
      export default {
        name: 'UserCard',
        props: {
          user: Object
        },
        methods: {
          greet() {
            return `Hello, ${this.user.name}`;
          }
        }
      }
      </script>

      <style scoped>
      .user { padding: 1rem; }
      </style>
      """

      config = %{chunk_size: 200, chunk_overlap: 30}

      assert {:ok, chunks} = Recursive.chunk(text, :vue, config)
      refute Enum.empty?(chunks)
      assert Enum.all?(chunks, &(&1.metadata.format == :vue))
    end

    test "chunks html" do
      text = """
      <!DOCTYPE html>
      <html>
      <head>
        <title>Test Page</title>
      </head>
      <body>
        <article>
          <h1>Main Title</h1>
          <p>Introduction paragraph with some content.</p>

          <section>
            <h2>Section One</h2>
            <p>Content for section one.</p>
            <ul>
              <li>Item 1</li>
              <li>Item 2</li>
            </ul>
          </section>

          <section>
            <h2>Section Two</h2>
            <p>Content for section two.</p>
          </section>
        </article>
      </body>
      </html>
      """

      config = %{chunk_size: 200, chunk_overlap: 30}

      assert {:ok, chunks} = Recursive.chunk(text, :html, config)
      refute Enum.empty?(chunks)
      assert Enum.all?(chunks, &(&1.metadata.format == :html))
    end

    test "document formats use plaintext separators" do
      text = String.duplicate("This is a paragraph of text. ", 50)
      config = %{chunk_size: 200, chunk_overlap: 30}

      for format <- [:doc, :docx, :epub, :latex, :odt, :pdf, :rtf] do
        assert {:ok, chunks} = Recursive.chunk(text, format, config)
        refute Enum.empty?(chunks), "Failed for format: #{format}"
      end
    end
  end

  describe "get_chunk_size option" do
    test "uses default String.length when not specified" do
      text = "Hello World"
      config = %{chunk_size: 5, chunk_overlap: 0}

      assert {:ok, chunks} = Recursive.chunk(text, :plain, config)
      # "Hello World" is 11 chars, should be split with size 5
      assert length(chunks) > 1
    end

    test "uses custom get_chunk_size function" do
      text = "Hello World Test"
      # Custom function: count words instead of characters
      word_counter = fn text ->
        text |> String.split(~r/\s+/, trim: true) |> length()
      end

      config = %{chunk_size: 2, chunk_overlap: 0, get_chunk_size: word_counter}

      assert {:ok, chunks} = Recursive.chunk(text, :plain, config)
      # Should split based on word count, not character count
      refute Enum.empty?(chunks)
    end

    test "uses byte_size function for byte-based chunking" do
      # Multi-byte UTF-8 characters
      text = "日本語テスト文字列です。これは長いテキストです。"
      config = %{chunk_size: 30, chunk_overlap: 0, get_chunk_size: &byte_size/1}

      assert {:ok, chunks} = Recursive.chunk(text, :plain, config)
      # Each Japanese character is 3 bytes, so byte_size will be much larger than String.length
      refute Enum.empty?(chunks)
    end

    test "get_chunk_size affects chunk boundaries" do
      text = String.duplicate("word ", 100)

      # Character-based: 500 chars
      char_config = %{chunk_size: 50, chunk_overlap: 0}
      {:ok, char_chunks} = Recursive.chunk(text, :plain, char_config)

      # Word-based: treat each "word " as size 1
      word_counter = fn text ->
        text |> String.split(~r/\s+/, trim: true) |> length()
      end

      word_config = %{chunk_size: 10, chunk_overlap: 0, get_chunk_size: word_counter}
      {:ok, word_chunks} = Recursive.chunk(text, :plain, word_config)

      # Different chunking strategies should produce different results
      assert length(char_chunks) != length(word_chunks) or
               Enum.any?(Enum.zip(char_chunks, word_chunks), fn {c, w} ->
                 c.content != w.content
               end)
    end
  end

  describe "custom separators" do
    test "uses custom separators when provided" do
      text = "Part1|||Part2|||Part3"
      config = %{chunk_size: 100, chunk_overlap: 0, separators: ["|||", " "]}

      assert {:ok, chunks} = Recursive.chunk(text, :plain, config)
      # With custom separator, should split on |||
      refute Enum.empty?(chunks)
    end

    test "custom separators override format-based separators" do
      markdown = """
      ## Header One

      Content under header one.

      ## Header Two

      Content under header two.
      """

      # Custom separators that don't include markdown headers
      config = %{chunk_size: 50, chunk_overlap: 0, separators: ["\n\n", "\n", " "]}

      assert {:ok, chunks} = Recursive.chunk(markdown, :markdown, config)
      # Should use custom separators, not markdown-aware ones
      refute Enum.empty?(chunks)
    end
  end

  describe "token_count in metadata" do
    test "includes token_count in chunk metadata" do
      {:ok, chunks} =
        Recursive.chunk("This is a test sentence for chunking.", :plain, %{chunk_size: 1000})

      assert chunks != []
      chunk = hd(chunks)
      assert Map.has_key?(chunk.metadata, :token_count)
      assert is_integer(chunk.metadata.token_count)
      assert chunk.metadata.token_count > 0
    end

    test "token_count is approximately char_count / 4" do
      # 100 chars
      text = String.duplicate("abcd", 25)
      {:ok, [chunk]} = Recursive.chunk(text, :plain, %{chunk_size: 1000})

      assert chunk.metadata.char_count == 100
      assert chunk.metadata.token_count == 25
    end

    test "token_count is included in all chunks" do
      # 1000 chars
      text = String.duplicate("word ", 200)
      {:ok, chunks} = Recursive.chunk(text, :plain, %{chunk_size: 100, chunk_overlap: 20})

      assert length(chunks) > 1

      assert Enum.all?(chunks, fn c ->
               is_integer(c.metadata.token_count) and c.metadata.token_count > 0
             end)
    end
  end
end
