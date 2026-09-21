# frozen_string_literal: true

# Run outside RSpec to detect uncaught worker failures and abnormal process exits (#2).
require "typesafe-sdk-ruby"
require "timeout"
require_relative "http_server"
server = Object.new.extend(HTTPServer)

Thread.abort_on_exception = true
Thread.report_on_exception = true
method, status = ARGV
signal = Typesafe::SDK::Signal.new
attempts = 0
handler = lambda do |socket, *|
  attempts += 1
  socket.write("HTTP/1.1 #{status} Test\r\nContent-Length: 100\r\n\r\n{")
  signal.cancel
  socket.read
end

Timeout.timeout(3) do
  server.with_http_server(handler) do |url|
    client = Typesafe::SDK::Client.new(api_key: "synthetic", base_url: url)
    begin
      if method == "system_one"
        client.system_one(state: "synthetic", questions: { q: Typesafe::SDK.noul("Question?") }, signal: signal)
      else
        client.models.list(signal: signal)
      end
      abort "Expected cancellation"
    rescue Typesafe::SDK::APIUserAbortError
      abort "Unexpected retry" unless attempts == 1
      puts "Caught APIUserAbortError"
    end
  end
end
puts "Normal process exit"
