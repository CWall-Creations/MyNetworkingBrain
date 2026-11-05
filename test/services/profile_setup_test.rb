require "test_helper"

class ProfileSetupTest < ActiveSupport::TestCase
  setup do
    @dir = Dir.mktmpdir
    File.write(File.join(@dir, "profile.yml"), { "name" => "", "school" => "My School", "locations" => [] }.to_yaml)
    ENV["NB_DATA_DIR"] = @dir
    Profile.instance_variable_set(:@current, nil)
    Agent::Setup.env_path = File.join(@dir, ".env")
    File.write(Agent::Setup.env_path, "CLAUDE_MODEL=\nANTHROPIC_API_KEY=\n")
  end

  teardown do
    ENV["NB_DATA_DIR"] = nil
    ENV["ANTHROPIC_API_KEY"] = nil
    Agent::Setup.env_path = nil
    Profile.instance_variable_set(:@current, nil)
    FileUtils.rm_rf(@dir)
  end

  def upload(name, content)
    Rack::Test::UploadedFile.new(StringIO.new(content), "application/octet-stream", original_filename: name)
  end

  test "resume upload saves into the private data dir" do
    Profile.current.attach_resume!(upload("CV.md", "# Pat Doe\nB.S. CS, May 2027"))
    assert File.exist?(File.join(@dir, "resume.md"))
    assert_includes Profile.current.resume_text, "May 2027"
    assert_raises(ArgumentError) { Profile.current.attach_resume!(upload("cv.docx", "x")) }
  end

  test "fills only blank fields from the resume" do
    Profile.current.attach_resume!(upload("cv.md", "Pat Doe, B.S. Computer Science, Example U, May 2027"))
    ENV["ANTHROPIC_API_KEY"] = "sk-ant-test"
    stub_request(:post, %r{api\.anthropic\.com/v1/messages}).to_return(
      headers: { "Content-Type" => "application/json" },
      body: { id: "m", type: "message", role: "assistant", model: "claude-opus-5-5", stop_reason: "end_turn",
              usage: { input_tokens: 1, output_tokens: 1 },
              content: [{ type: "text", text: {
                name: "Pat Doe", graduation_date: "2027-05", degree: "B.S. Computer Science", school: "Example U",
                work_authorization: "", locations: ["Denver"], target_roles: ["Software Engineer"],
                target_industries: ["AI/ML"], curious_industries: ["Fintech"] }.to_json }] }.to_json)
    changed = Agent::Tasks.profile_from_resume!
    p = Profile.current
    assert_equal "Pat Doe", p.name
    assert_equal "My School", p["school"] # kept: you already filled it
    assert_equal ["Denver"], p.locations
    refute_includes changed, "school"
    refute_includes changed, "work_authorization"
  end

  test "API key is verified, then saved to .env" do
    stub_request(:get, %r{api\.anthropic\.com/v1/models/}).to_return(
      headers: { "Content-Type" => "application/json" },
      body: { id: "claude-opus-5-5", type: "model", display_name: "Claude Opus 5.5", created_at: "2026-01-01T00:00:00Z" }.to_json)
    Agent::Setup.save_key!("sk-ant-good-key-123456")
    assert_includes File.read(Agent::Setup.env_path), "ANTHROPIC_API_KEY=sk-ant-good-key-123456"
    assert_includes File.read(Agent::Setup.env_path), "CLAUDE_MODEL=" # other lines kept
    assert Agent::Client.configured?
  end

  test "bad API key is rejected and not saved" do
    stub_request(:get, %r{api\.anthropic\.com/v1/models/}).to_return(
      status: 401, headers: { "Content-Type" => "application/json" },
      body: { type: "error", error: { type: "authentication_error", message: "invalid x-api-key" } }.to_json)
    assert_raises(Agent::Setup::InvalidKey) { Agent::Setup.save_key!("sk-ant-bad") }
    assert_raises(Agent::Setup::InvalidKey) { Agent::Setup.save_key!("not-a-key") }
    assert_includes File.read(Agent::Setup.env_path), "ANTHROPIC_API_KEY=\n"
  end
end
