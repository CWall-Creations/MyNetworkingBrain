require "test_helper"

class CareersFinderTest < ActiveSupport::TestCase
  def html(body, title: "Acme") = "<html><head><title>#{title}</title></head><body>#{body}</body></html>"

  test "detects the job system a careers page links to" do
    f = Jobs::CareersFinder.new("acme.com")
    assert_equal ["greenhouse", "acme"], f.detect_ats(html('<a href="https://job-boards.greenhouse.io/acme">Jobs</a>'))
    assert_equal ["lever", "acme"], f.detect_ats(html('<iframe src="https://jobs.lever.co/acme"></iframe>'))
    assert_equal ["workable", "acme-co"], f.detect_ats(html('<a href="https://apply.workable.com/acme-co/">Open roles</a>'))
    assert_equal ["workday", "https://acme.wd5.myworkdayjobs.com/External"],
                 f.detect_ats(html('<a href="https://acme.wd5.myworkdayjobs.com/External">Search jobs</a>'))
    assert_nil f.detect_ats(html("<p>No jobs here</p>"))
  end

  test "follows the homepage Careers link to the job system" do
    stub_request(:get, "https://acme.com/").to_return(body: html('<a href="/company/careers">Careers</a>'))
    stub_request(:get, "https://acme.com/company/careers").to_return(
      body: html('<a href="https://jobs.ashbyhq.com/acme">See open roles</a>', title: "Careers at Acme"))
    r = Jobs::CareersFinder.call("acme.com")
    assert_equal "https://acme.com/company/careers", r.careers_url
    assert_equal "ashby", r.provider
    assert_equal "acme", r.slug
  end

  test "careers page with embedded JobPosting data" do
    page = html(<<~H, title: "Join us")
      <script type="application/ld+json">{"@context":"https://schema.org","@type":"JobPosting","title":"Software Engineer, New Grad",
        "url":"/jobs/42","datePosted":"2026-10-30","jobLocation":{"address":{"addressLocality":"Denver"}}}</script>
    H
    jobs = Jobs::Boards::CareersPage.parse(page, "https://acme.com/careers")
    assert_equal 1, jobs.size
    assert_equal "https://acme.com/jobs/42", jobs.first.url
    assert_equal "Denver", jobs.first.location
  end

  test "workable, smartrecruiters and rippling" do
    stub_request(:post, "https://apply.workable.com/api/v3/accounts/acme/jobs").to_return(
      body: { results: [{ shortcode: "AB1", title: "Junior Developer", location: { city: "Austin", country: "US" }, published: "2026-10-01" }] }.to_json)
    stub_request(:get, "https://api.smartrecruiters.com/v1/companies/acme/postings?limit=100").to_return(
      body: { totalFound: 1, content: [{ id: "9", name: "Associate Software Engineer", location: { city: "NYC" }, releasedDate: "2026-10-02T00:00:00Z" }] }.to_json)
    stub_request(:get, "https://ats.rippling.com/api/v2/board/acme/jobs").to_return(
      body: { items: [{ id: "x", name: "ML Engineer I", url: "https://ats.rippling.com/acme/jobs/x", locations: [{ name: "Remote" }] }] }.to_json)
    assert_equal "https://apply.workable.com/acme/j/AB1/", Jobs::Boards::Workable.fetch("acme").first.url
    assert_equal "https://jobs.smartrecruiters.com/acme/9", Jobs::Boards::SmartRecruiters.fetch("acme").first.url
    assert_equal "Remote", Jobs::Boards::Rippling.fetch("acme").first.location
  end

  test "ingest trusts a job system found on the company's own site" do
    stub_request(:any, /.*/).to_return(status: 404)
    stub_request(:get, "https://acme.com/").to_return(body: html('<a href="https://boards.greenhouse.io/acmeinc">Careers</a>'))
    stub_request(:get, "https://boards-api.greenhouse.io/v1/boards/acmeinc/jobs").to_return(
      body: { jobs: [{ id: 7, title: "Software Engineer, New Grad", absolute_url: "https://x/7" }] }.to_json)
    stub_request(:get, %r{raw\.githubusercontent\.com}).to_return(body: "[]")
    person!("Pat Lee", company: "Acme")
    Company.find_by(name: "Acme").update!(website: "https://acme.com")
    Jobs::Ingest.new.run
    c = Company.find_by(name: "Acme")
    assert_equal "greenhouse", c.ats_provider
    assert c.ats_verified
    assert_equal 1, c.job_postings.new_grad.count
  end

  test "ADP Workforce Now embed" do
    page = html(%(<script src="https://workforcenow.adp.com/mascsr/default/x.js"></script><div cid='11111111-2222-3333-4444-555555555555' ccid='1234567890123_1'></div>))
    assert_equal ["adp", "11111111-2222-3333-4444-555555555555|1234567890123_1"], Jobs::CareersFinder.new("x.com").detect_ats(page)
    stub_request(:get, %r{workforcenow\.adp\.com/.*/job-requisitions}).to_return(
      body: { jobRequisitions: [{ itemID: "1_1", requisitionTitle: "Associate Software Engineer", postDate: "2026-10-27T09:05Z",
                                  requisitionLocations: [{ nameCode: { shortName: " Malvern, PA, US" } }] }] }.to_json)
    job = Jobs::Boards::Adp.fetch("11111111-2222-3333-4444-555555555555|1234567890123_1").first
    assert_equal "Malvern, PA, US", job.location
    assert_includes job.url, "jobId=1_1"
  end
end
