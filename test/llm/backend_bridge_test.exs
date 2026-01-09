defmodule PortfolioIndex.LLM.BackendBridgeTest do
  use PortfolioIndex.SupertesterCase, async: true

  alias PortfolioIndex.LLM.BackendBridge

  describe "prompt_to_messages/1" do
    test "converts backend prompt to messages and opts" do
      prompt = %{
        __struct__: CrucibleIR.Backend.Prompt,
        system: "You are helpful.",
        messages: [
          %{role: :user, content: "Hi"},
          %{role: :assistant, content: "Hello"}
        ],
        tools: [%{type: "function", function: %{name: "tool"}}],
        tool_choice: :auto,
        options: %{
          __struct__: CrucibleIR.Backend.Options,
          model: "llama3",
          temperature: 0.2,
          max_tokens: 128,
          top_p: 0.9,
          stop: ["END"],
          timeout_ms: 5_000,
          extra: %{"presence_penalty" => 0.3}
        },
        trace_id: "trace-1",
        request_id: "req-1",
        metadata: %{work_id: "work-1", plan_id: "plan-1", step_id: "step-1"}
      }

      assert {:ok, {messages, opts}} = BackendBridge.prompt_to_messages(prompt)

      assert messages == [
               %{role: :system, content: "You are helpful."},
               %{role: :user, content: "Hi"},
               %{role: :assistant, content: "Hello"}
             ]

      assert opts[:model] == "llama3"
      assert opts[:temperature] == 0.2
      assert opts[:max_tokens] == 128
      assert opts[:top_p] == 0.9
      assert opts[:stop] == ["END"]
      assert opts[:receive_timeout] == 5_000
      assert opts[:trace_id] == "trace-1"
      assert opts[:request_id] == "req-1"
      assert opts[:tools] == [%{type: "function", function: %{name: "tool"}}]
      assert opts[:tool_choice] == :auto

      assert opts[:telemetry_metadata] == %{
               work_id: "work-1",
               plan_id: "plan-1",
               step_id: "step-1"
             }

      assert opts[:extra] == %{"presence_penalty" => 0.3}
    end
  end

  describe "completion_from_result/2" do
    test "builds backend completion map from adapter result" do
      result = %{
        content: "Hello",
        model: "llama3",
        usage: %{input_tokens: 2, output_tokens: 3},
        finish_reason: :stop
      }

      prompt = %{
        __struct__: CrucibleIR.Backend.Prompt,
        trace_id: "trace-2",
        request_id: "req-2"
      }

      completion = BackendBridge.completion_from_result(result, prompt, raw_response: %{ok: true})

      assert completion.model == "llama3"
      assert completion.trace_id == "trace-2"
      assert completion.request_id == "req-2"
      assert completion.raw_response == %{ok: true}

      assert completion.usage == %{
               prompt_tokens: 2,
               completion_tokens: 3,
               total_tokens: 5
             }

      assert completion.choices == [
               %{
                 index: 0,
                 message: %{role: :assistant, content: "Hello"},
                 finish_reason: :stop
               }
             ]
    end
  end
end
