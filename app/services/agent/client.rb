module Agent
  # Thin wrapper over the Anthropic Ruby SDK.
  # - json(...)     : one call, response constrained to a JSON schema
  # - research(...) : web-search-enabled call (Claude's server-side web search tool)
  # Uses server-side refusal fallbacks and caches the (stable) system prompt.
  class Client
    class NotConfigured < StandardError; end
    class Refused < StandardError; end

    BETAS = ["server-side-fallback-2026-07-01"].freeze

    def self.configured? = ENV["ANTHROPIC_API_KEY"].present?

    def initialize(model: ENV["CLAUDE_MODEL"].presence || "claude-opus-5-5")
      raise NotConfigured, "Set ANTHROPIC_API_KEY in .env to use the agent." unless self.class.configured?
      @model = model
      @client = Anthropic::Client.new
    end

    def json(system:, prompt:, schema:, effort: :medium, max_tokens: 16_000)
      msg = create(system:, effort:, max_tokens:,
                   messages: [{ role: "user", content: prompt }],
                   format_: { type: :json_schema, schema: })
      JSON.parse(text_of(msg))
    end

    # Returns the final text. Handles pause_turn (long server-tool turns).
    def research(system:, prompt:, max_searches: 5, effort: :medium)
      messages = [{ role: "user", content: prompt }]
      tools = [{ type: "web_search_20260209", name: "web_search", max_uses: max_searches }]
      msg = nil
      4.times do
        msg = create(system:, effort:, max_tokens: 16_000, messages:, tools:)
        break unless msg.stop_reason == :pause_turn
        messages = messages + [{ role: "assistant", content: msg.content.map(&:to_h) }]
      end
      text_of(msg)
    end

    # Pulls the last JSON object out of free text (used after web research).
    def self.extract_json(text)
      fenced = text.to_s.scan(/```(?:json)?\s*(\{.*?\})\s*```/m).last&.first
      candidate = fenced || text.to_s[/\{.*\}/m]
      candidate ? JSON.parse(candidate) : {}
    rescue JSON::ParserError
      {}
    end

    private

    def create(system:, effort:, max_tokens:, messages:, format_: nil, tools: nil)
      output_config = { effort: }
      output_config[:format_] = format_ if format_
      params = {
        model: @model, max_tokens:, messages:, betas: BETAS, fallbacks: :default,
        system_: [{ type: "text", text: system, cache_control: { type: "ephemeral" } }],
        output_config:
      }
      params[:tools] = tools if tools
      msg = @client.beta.messages.create(**params)
      raise Refused, "Claude declined this request (#{msg.stop_details&.category})." if msg.stop_reason == :refusal
      msg
    end

    def text_of(msg) = msg.content.select { |b| b.type == :text }.map(&:text).join
  end
end
