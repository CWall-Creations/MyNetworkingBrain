require "net/http"
require "json"

module Jobs
  # Tiny JSON HTTP helper (stdlib only) with sane timeouts.
  module Http
    UA = "MyNetworkingBrain/1.0 (personal job tracker)".freeze

    module_function

    def get_json(url, timeout: 15)
      request(URI(url), Net::HTTP::Get, nil, timeout)
    end

    def post_json(url, body, timeout: 15)
      request(URI(url), Net::HTTP::Post, body, timeout)
    end

    BROWSER_UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128 Safari/537.36".freeze

    # Fetches a web page (follows redirects). Returns [html, final_url] or nil.
    def get_html(url, timeout: 12, redirects: 4)
      uri = URI(url)
      redirects.times do
        res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                                  open_timeout: timeout, read_timeout: timeout) do |http|
          req = Net::HTTP::Get.new(uri)
          req["User-Agent"] = BROWSER_UA
          req["Accept"] = "text/html,application/xhtml+xml"
          http.request(req)
        end
        case res
        when Net::HTTPRedirection
          uri = URI.join(uri.to_s, res["location"])
        when Net::HTTPSuccess
          body = res.body.to_s.dup.force_encoding("UTF-8").scrub
          return [body, uri.to_s]
        else
          return nil
        end
      end
      nil
    rescue SocketError, Timeout::Error, Errno::ECONNREFUSED, Errno::ECONNRESET, OpenSSL::SSL::SSLError,
           Net::HTTPError, URI::InvalidURIError, ArgumentError, EOFError, Zlib::Error
      nil
    end

    def request(uri, klass, body, timeout)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                          open_timeout: timeout, read_timeout: timeout * 2) do |http|
        req = klass.new(uri)
        req["User-Agent"] = UA
        req["Accept"] = "application/json"
        if body
          req["Content-Type"] = "application/json"
          req.body = JSON.generate(body)
        end
        res = http.request(req)
        return nil unless res.is_a?(Net::HTTPSuccess)
        JSON.parse(res.body)
      end
    rescue JSON::ParserError, SocketError, Timeout::Error, Errno::ECONNREFUSED, OpenSSL::SSL::SSLError, Net::HTTPError
      nil
    end
  end
end
