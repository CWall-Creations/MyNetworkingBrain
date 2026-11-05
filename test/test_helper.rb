ENV["RAILS_ENV"] ||= "test"
ENV["ANTHROPIC_API_KEY"] = nil
require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"

WebMock.disable_net_connect!(allow_localhost: true)

module ActiveSupport
  class TestCase
    parallelize(workers: 1)
    fixtures :all

    def person!(name, company: nil, **attrs)
      p = Person.create!({ name:, closeness: 3 }.merge(attrs))
      p.assign_companies!([company]) if company
      p
    end
  end
end
