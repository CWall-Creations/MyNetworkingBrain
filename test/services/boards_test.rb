require "test_helper"

class BoardsTest < ActiveSupport::TestCase
  test "greenhouse" do
    stub_request(:get, "https://boards-api.greenhouse.io/v1/boards/acme/jobs").to_return(
      body: { jobs: [{ id: 1, title: "Software Engineer, New Grad", absolute_url: "https://x/1",
                       location: { name: "SF" }, first_published: "2026-10-01T00:00:00Z" }] }.to_json)
    jobs = Jobs::Boards::Greenhouse.fetch("acme")
    assert_equal "gh-1", jobs.first.external_id
    assert_equal "SF", jobs.first.location
  end

  test "lever and ashby" do
    stub_request(:get, "https://api.lever.co/v0/postings/acme?mode=json").to_return(
      body: [{ id: "a", text: "Junior Dev", hostedUrl: "https://l/a", categories: { location: "NYC" }, createdAt: 1_760_000_000_000 }].to_json)
    stub_request(:get, "https://api.ashbyhq.com/posting-api/job-board/acme").to_return(
      body: { jobs: [{ id: "b", title: "ML Engineer", jobUrl: "https://a/b", location: "Remote", publishedAt: "2026-10-02T00:00:00Z" }] }.to_json)
    assert_equal "Junior Dev", Jobs::Boards::Lever.fetch("acme").first.title
    assert_equal "ab-b", Jobs::Boards::Ashby.fetch("acme").first.external_id
  end

  test "missing board returns nil" do
    stub_request(:get, "https://boards-api.greenhouse.io/v1/boards/nope/jobs").to_return(status: 404)
    assert_nil Jobs::Boards::Greenhouse.fetch("nope")
  end

  test "workday careers URL" do
    stub_request(:post, "https://acme.wd5.myworkdayjobs.com/wday/cxs/acme/External/jobs").to_return(
      body: { jobPostings: [{ title: "Associate Software Engineer", externalPath: "/job/X/1", locationsText: "Denver", postedOn: "Posted 3 Days Ago" }] }.to_json)
    jobs = Jobs::Boards::Workday.fetch("https://acme.wd5.myworkdayjobs.com/en-US/External")
    assert_equal 1, jobs.size
    assert_equal "https://acme.wd5.myworkdayjobs.com/External/job/X/1", jobs.first.url
    assert jobs.first.posted_at < 2.days.ago
  end

  test "slug candidates never fall back to a lone first word" do
    assert_equal %w[openroadlabs open-road-labs], Jobs::AtsDetector.slug_candidates("Open Road Labs")
    assert_equal ["blueharbor", "blue-harbor"], Jobs::AtsDetector.slug_candidates("Blue Harbor Corporation")
  end
end
