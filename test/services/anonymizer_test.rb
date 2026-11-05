require "test_helper"

class AnonymizerTest < ActiveSupport::TestCase
  setup do
    @a = person!("Jordan Smith", company: "Acme")
    @b = person!("Jordan Lee", company: "Beta")
    @anon = Agent::Anonymizer.new(people: [@a, @b], me: "Alex Example")
  end

  test "replaces full names, leftover name parts and your own name" do
    out = @anon.scrub("Alex Example met Jordan Smith; Jordan Lee said hi. Ask Jordan.")
    refute_match(/Smith|Lee|Jordan|Alex|Example/, out)
    assert_includes out, @anon.token(@a)
    assert_includes out, "[ME]"
  end

  test "restores tokens" do
    assert_equal "Hi Jordan Lee", @anon.restore("Hi #{@anon.token(@b)}")
  end

  test "no contact name reaches the Claude API" do
    ENV["ANTHROPIC_API_KEY"] = "test-key"
    captured = nil
    stub_request(:post, %r{api\.anthropic\.com/v1/messages}).to_return do |req|
      captured = req.body
      { status: 200, headers: { "Content-Type" => "application/json" }, body: {
        id: "msg_1", type: "message", role: "assistant", model: "claude-opus-5-5", stop_reason: "end_turn",
        content: [{ type: "text", text: { message: "Hi #{@anon.token(@a)}!" }.to_json }],
        usage: { input_tokens: 1, output_tokens: 1 }
      }.to_json }
    end
    @a.update!(notes: "Jordan Lee introduced us", how_met: "Coworker of Aunt")
    draft = Agent::Tasks.draft_message(@a)
    refute_nil captured
    refute_match(/Jordan|Smith|\bLee\b/, captured)
    assert_includes draft, "Jordan Smith" # restored locally
    body = JSON.parse(captured)
    assert_equal "default", body["fallbacks"]
    assert_equal "json_schema", body.dig("output_config", "format", "type")
  ensure
    ENV["ANTHROPIC_API_KEY"] = nil
  end
end
