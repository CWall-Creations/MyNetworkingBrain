module Agent
  # Saves your Anthropic API key to the local, gitignored .env file after
  # checking that it works. Takes effect immediately (no restart needed).
  module Setup
    class InvalidKey < StandardError; end

    class << self
      attr_writer :env_path
      def env_path = @env_path || Rails.root.join(".env")
    end

    module_function

    def save_key!(key)
      key = key.to_s.strip
      raise InvalidKey, "That doesn't look like an Anthropic API key (they start with sk-ant-)." unless key.start_with?("sk-ant-")
      verify!(key)
      write_env!("ANTHROPIC_API_KEY", key)
      ENV["ANTHROPIC_API_KEY"] = key
    end

    def verify!(key)
      model = ENV["CLAUDE_MODEL"].presence || "claude-opus-5-5"
      Anthropic::Client.new(api_key: key).models.retrieve(model) # free metadata call
    rescue Anthropic::Errors::AuthenticationError, Anthropic::Errors::PermissionDeniedError
      raise InvalidKey, "Anthropic rejected that key. Check it at console.anthropic.com → API keys."
    rescue Anthropic::Errors::APIConnectionError
      raise InvalidKey, "Couldn't reach the Anthropic API. Check your internet connection."
    end

    def remove_key!
      write_env!("ANTHROPIC_API_KEY", "")
      ENV.delete("ANTHROPIC_API_KEY")
    end

    def masked
      key = ENV["ANTHROPIC_API_KEY"].to_s
      key.length > 12 ? "#{key[0, 10]}…#{key[-4..]}" : nil
    end

    def write_env!(name, value)
      lines = File.exist?(Setup.env_path) ? File.readlines(Setup.env_path, chomp: true) : []
      line = "#{name}=#{value}"
      idx = lines.index { |l| l.start_with?("#{name}=") }
      idx ? lines[idx] = line : lines << line
      File.write(Setup.env_path, lines.join("\n") + "\n")
      File.chmod(0o600, Setup.env_path)
    end
  end
end
