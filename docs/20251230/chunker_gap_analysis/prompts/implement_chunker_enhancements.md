# Implementation Prompt: Chunker Token Enhancements

## Task Overview

Implement the missing chunker features identified in the gap analysis between `text_chunker_ex + Arcana` and `PortfolioIndex`. This adds token utilities and convenience features while maintaining backwards compatibility.

---

## Prerequisites Completed

> **Port Updated**: The `PortfolioCore.Ports.Chunker` port has been updated (v0.3.1) with:
> ```elixir
> @type size_unit :: :characters | :tokens
>
> @type chunk_config :: %{
>   chunk_size: pos_integer(),
>   chunk_overlap: non_neg_integer(),
>   size_unit: size_unit() | nil,  # NEW
>   separators: [String.t()] | nil
> }
> ```
> See: `../portfolio_core/lib/portfolio_core/ports/chunker.ex`
>
> This implementation adds adapter-level support for the port's `size_unit` option.

---

## Required Reading

### Gap Analysis Documents (Read First)
1. `docs/20251230/chunker_gap_analysis/gap_analysis.md` - Executive summary and feature matrix
2. `docs/20251230/chunker_gap_analysis/feature_token_utilities.md` - Tokens module spec
3. `docs/20251230/chunker_gap_analysis/feature_size_unit_option.md` - Config enhancement spec
4. `docs/20251230/chunker_gap_analysis/feature_token_count_output.md` - Output enhancement spec

### Port Specification (Already Updated)
1. `../portfolio_core/lib/portfolio_core/ports/chunker.ex` - Chunker port with `size_unit` type

### Source Files to Understand
1. `lib/portfolio_index/adapters/chunker/config.ex` - Current config implementation
2. `lib/portfolio_index/adapters/chunker/recursive.ex` - Primary chunker
3. `lib/portfolio_index/adapters/chunker/character.ex` - Character chunker
4. `lib/portfolio_index/adapters/chunker/paragraph.ex` - Paragraph chunker
5. `lib/portfolio_index/adapters/chunker/sentence.ex` - Sentence chunker
6. `lib/portfolio_index/adapters/chunker/semantic.ex` - Semantic chunker
7. `lib/portfolio_index/adapters/chunker/separators.ex` - Separator definitions

### Reference Implementations
1. `arcana/lib/arcana/chunker.ex` - Arcana's token handling approach
2. `text_chunker_ex/lib/text_chunker.ex` - text_chunker's API

### Existing Tests
1. `test/adapters/chunker/config_test.exs`
2. `test/adapters/chunker/recursive_test.exs`
3. `test/adapters/chunker/character_test.exs`
4. `test/adapters/chunker/paragraph_test.exs`
5. `test/adapters/chunker/sentence_test.exs`
6. `test/adapters/chunker/semantic_test.exs`
7. `test/adapters/chunker/separators_test.exs`

---

## Implementation Steps (TDD Approach)

### Phase 1: Create Tokens Module

#### Step 1.1: Write Tests First
Create `test/adapters/chunker/tokens_test.exs`:

```elixir
defmodule PortfolioIndex.Adapters.Chunker.TokensTest do
  use ExUnit.Case, async: true

  alias PortfolioIndex.Adapters.Chunker.Tokens

  describe "estimate/2" do
    test "returns 0 for empty string" do
      assert Tokens.estimate("") == 0
    end

    test "returns at least 1 for non-empty text" do
      assert Tokens.estimate("Hi") == 1
      assert Tokens.estimate("a") == 1
    end

    test "estimates ~4 chars per token by default" do
      assert Tokens.estimate("12345678") == 2
      assert Tokens.estimate("123456789012") == 3
    end

    test "accepts custom chars_per_token ratio" do
      assert Tokens.estimate("12345678", chars_per_token: 2) == 4
      assert Tokens.estimate("12345678", chars_per_token: 8) == 1
    end

    test "handles unicode correctly" do
      # String.length counts graphemes, not bytes
      assert Tokens.estimate("hello") == 1  # 5 chars / 4 = 1
    end
  end

  describe "sizer/1" do
    test "returns a function" do
      sizer = Tokens.sizer()
      assert is_function(sizer, 1)
    end

    test "returned function estimates tokens" do
      sizer = Tokens.sizer()
      assert sizer.("12345678") == 2
    end

    test "accepts custom ratio" do
      sizer = Tokens.sizer(chars_per_token: 2)
      assert sizer.("12345678") == 4
    end
  end

  describe "to_chars/2" do
    test "converts tokens to characters" do
      assert Tokens.to_chars(100) == 400
      assert Tokens.to_chars(100, chars_per_token: 3) == 300
    end
  end

  describe "from_chars/2" do
    test "converts characters to tokens" do
      assert Tokens.from_chars(400) == 100
      assert Tokens.from_chars(300, chars_per_token: 3) == 100
    end

    test "returns at least 1 for small char counts" do
      assert Tokens.from_chars(1) == 1
    end
  end

  describe "default_ratio/0" do
    test "returns 4" do
      assert Tokens.default_ratio() == 4
    end
  end
end
```

#### Step 1.2: Run Tests (Should Fail)
```bash
mix test test/adapters/chunker/tokens_test.exs
```

#### Step 1.3: Implement Module
Create `lib/portfolio_index/adapters/chunker/tokens.ex` per the spec in `feature_token_utilities.md`.

#### Step 1.4: Run Tests (Should Pass)
```bash
mix test test/adapters/chunker/tokens_test.exs
```

---

### Phase 2: Extend Config with `size_unit`

#### Step 2.1: Add Tests to `config_test.exs`

```elixir
describe "size_unit option" do
  test "defaults to :characters" do
    {:ok, config} = Config.validate(%{})
    assert config.size_unit == :characters
  end

  test ":characters uses String.length/1 by default" do
    {:ok, config} = Config.validate(%{size_unit: :characters})
    assert config.get_chunk_size.("test") == 4
  end

  test ":tokens auto-sets Tokens.sizer()" do
    {:ok, config} = Config.validate(%{size_unit: :tokens})
    # 8 chars / 4 = 2 tokens
    assert config.get_chunk_size.("12345678") == 2
  end

  test "explicit get_chunk_size overrides size_unit default" do
    custom_fn = fn _ -> 42 end
    {:ok, config} = Config.validate(%{size_unit: :tokens, get_chunk_size: custom_fn})
    assert config.get_chunk_size.("anything") == 42
  end

  test "rejects invalid size_unit" do
    {:error, message} = Config.validate(%{size_unit: :words})
    assert message =~ "invalid value"
  end
end
```

#### Step 2.2: Run Tests (Should Fail)
```bash
mix test test/adapters/chunker/config_test.exs
```

#### Step 2.3: Modify Config Module
Update `lib/portfolio_index/adapters/chunker/config.ex` per the spec in `feature_size_unit_option.md`.

#### Step 2.4: Run Tests (Should Pass)
```bash
mix test test/adapters/chunker/config_test.exs
```

---

### Phase 3: Add `token_count` to All Chunker Outputs

#### Step 3.1: Add Tests to Each Chunker Test File

Add to each of:
- `test/adapters/chunker/recursive_test.exs`
- `test/adapters/chunker/character_test.exs`
- `test/adapters/chunker/paragraph_test.exs`
- `test/adapters/chunker/sentence_test.exs`
- `test/adapters/chunker/semantic_test.exs`

```elixir
describe "token_count in metadata" do
  test "includes token_count in chunk metadata" do
    {:ok, chunks} = Chunker.chunk("This is a test sentence for chunking.", :plain, %{chunk_size: 1000})

    assert length(chunks) > 0
    chunk = hd(chunks)
    assert Map.has_key?(chunk.metadata, :token_count)
    assert is_integer(chunk.metadata.token_count)
    assert chunk.metadata.token_count > 0
  end

  test "token_count is approximately char_count / 4" do
    text = String.duplicate("abcd", 25)  # 100 chars
    {:ok, [chunk]} = Chunker.chunk(text, :plain, %{chunk_size: 1000})

    assert chunk.metadata.char_count == 100
    assert chunk.metadata.token_count == 25
  end
end
```

#### Step 3.2: Run Tests (Should Fail)
```bash
mix test test/adapters/chunker/
```

#### Step 3.3: Modify Each Chunker
Update each chunker per the spec in `feature_token_count_output.md`:
- Add `alias PortfolioIndex.Adapters.Chunker.Tokens`
- Add `token_count: Tokens.estimate(content)` to metadata map

#### Step 3.4: Run Tests (Should Pass)
```bash
mix test test/adapters/chunker/
```

---

### Phase 4: Integration Testing

#### Step 4.1: Run Full Test Suite
```bash
mix test
```

#### Step 4.2: Run Dialyzer
```bash
mix dialyzer
```

#### Step 4.3: Run Credo
```bash
mix credo --strict
```

#### Step 4.4: Fix Any Issues
- Address all warnings
- Address all Dialyzer errors
- Address all Credo issues

---

### Phase 5: Documentation Updates

#### Step 5.1: Update CHANGELOG.md

Add to the `[0.3.1]` section under `### Added`:

```markdown
#### Token Utilities
- **Tokens module** - Centralized token estimation utilities
  - `Tokens.estimate/2` - Estimate token count from text (~4 chars/token heuristic)
  - `Tokens.sizer/1` - Get sizing function for token-based chunking
  - `Tokens.to_chars/2` - Convert token count to character count
  - `Tokens.from_chars/2` - Convert character count to token count

#### Chunker Config Enhancement
- **`size_unit` option** - Specify `:characters` or `:tokens` for chunk sizing
  - `:tokens` auto-configures `get_chunk_size` with token estimation
  - `:characters` (default) uses `String.length/1`

#### Chunker Output Enhancement
- **`token_count` in metadata** - All chunkers now include estimated token count
  - Useful for LLM context window budgeting
  - Approximately `char_count / 4`
```

#### Step 5.2: Update Module Documentation
Ensure all new public functions have:
- `@moduledoc` with examples
- `@doc` with examples
- `@spec` typespecs

#### Step 5.3: Update README.md if Needed
Add a brief mention of token-based chunking in the chunker section.

---

## Validation Checklist

Before marking complete, verify:

- [ ] All new tests pass: `mix test`
- [ ] No warnings: `mix compile --warnings-as-errors`
- [ ] Dialyzer passes: `mix dialyzer`
- [ ] Credo passes: `mix credo --strict`
- [ ] CHANGELOG.md updated with all changes
- [ ] All public functions have @doc and @spec

---

## Files to Create

| File | Description |
|------|-------------|
| `lib/portfolio_index/adapters/chunker/tokens.ex` | Token estimation utilities |
| `test/adapters/chunker/tokens_test.exs` | Token utility tests |

## Files to Modify

| File | Change |
|------|--------|
| `lib/portfolio_index/adapters/chunker/config.ex` | Add `:size_unit` option |
| `lib/portfolio_index/adapters/chunker/recursive.ex` | Add `token_count` to metadata |
| `lib/portfolio_index/adapters/chunker/character.ex` | Add `token_count` to metadata |
| `lib/portfolio_index/adapters/chunker/paragraph.ex` | Add `token_count` to metadata |
| `lib/portfolio_index/adapters/chunker/sentence.ex` | Add `token_count` to metadata |
| `lib/portfolio_index/adapters/chunker/semantic.ex` | Add `token_count` to metadata |
| `test/adapters/chunker/config_test.exs` | Add `size_unit` tests |
| `test/adapters/chunker/recursive_test.exs` | Add `token_count` tests |
| `test/adapters/chunker/character_test.exs` | Add `token_count` tests |
| `test/adapters/chunker/paragraph_test.exs` | Add `token_count` tests |
| `test/adapters/chunker/sentence_test.exs` | Add `token_count` tests |
| `test/adapters/chunker/semantic_test.exs` | Add `token_count` tests |
| `CHANGELOG.md` | Document changes under 0.3.1 |

---

## Context Summary

### What's Already Done (portfolio_core)
- `PortfolioCore.Ports.Chunker` updated with `size_unit :: :characters | :tokens` type
- `chunk_config` type now includes optional `size_unit` field
- CHANGELOG.md updated for v0.3.1

### What We're Adding (portfolio_index)
1. **Tokens module** - Token estimation utilities (`estimate/2`, `sizer/1`, `to_chars/2`, `from_chars/2`)
2. **`size_unit` config option** - `:characters` or `:tokens` for chunk sizing (implements port spec)
3. **`token_count` in output** - All chunkers include token estimate in metadata

### Why
- Closes gap with Arcana's convenience features
- Makes token-based LLM context budgeting easier
- Implements the new port specification from portfolio_core
- No breaking changes - purely additive

### Design Principles
- Backwards compatible (default behavior unchanged)
- TDD approach (tests first)
- Use existing patterns (follow Config module style)
- Comprehensive documentation
- Align with port specification in portfolio_core
