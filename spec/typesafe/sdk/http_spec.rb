# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/http_server"

RSpec.describe "Native HTTP reliability" do
  include HTTPServer

  def client_for(url, **options)
    Typesafe::SDK::Client.new(api_key: "test", base_url: url, timeout: 1,
                              retry_policy: { max_retries: 0 }, **options)
  end

  [200, 503].each do |status|
    it "cancels a stalled #{status} body without retrying or leaking a worker" do
      attempts = 0
      closed = Queue.new
      signal = Typesafe::SDK::Signal.new
      handler = lambda do |socket, *|
        attempts += 1
        socket.write("HTTP/1.1 #{status} Test\r\nContent-Length: 100\r\n\r\n{")
        signal.cancel
        closed << socket.read
      end
      threads = Thread.list
      with_http_server(handler) do |url|
        expect { client_for(url, retry_policy: { max_retries: 2 }).models.list(signal: signal) }
          .to raise_error(Typesafe::SDK::APIUserAbortError)
        expect(attempts).to eq(1)
        expect(Timeout.timeout(1) { closed.pop }).to eq("")
      end
      # Ruby 3.2+ lazily starts one process-wide Timeout service thread.
      leaked = (Thread.list - threads).reject { |thread| thread.name == "Timeout stdlib thread" }
      expect(leaked).to be_empty
    end

    it "bounds the entire slowly arriving #{status} body by the attempt timeout" do
      handler = lambda do |socket, *|
        socket.write("HTTP/1.1 #{status} Test\r\nContent-Length: 100\r\n\r\n")
        20.times do
          socket.write(" ")
          sleep 0.03
        end
      end
      with_http_server(handler) do |url|
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        expect { client_for(url, timeout: 0.15).models.list }
          .to raise_error(Typesafe::SDK::APITimeoutError)
        expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 0.5
      end
    end

    it "retries a truncated #{status} body through the SDK and preserves retry headers" do
      requests = []
      handler = lambda do |socket, _, headers, _body|
        requests << headers
        if requests.length == 1
          socket.write("HTTP/1.1 #{status} Test\r\nContent-Length: 100\r\n\r\n{")
        else
          send_json(socket, { models: [] })
        end
      end
      with_http_server(handler) do |url|
        client = client_for(url, retry_policy: { max_retries: 1, backoff_initial_ms: 0 })
        expect(client.models.list).to eq([])
        expect(requests.length).to eq(2)
        expect(requests[0]).not_to have_key("x-typesafe-retry-count")
        expect(requests[1]["x-typesafe-retry-count"]).to eq("1")
      end
    end
  end

  it "gives a retry a fresh timeout after the first attempt stalls" do
    attempts = 0
    handler = lambda do |socket, *|
      attempts += 1
      if attempts == 1
        socket.write("HTTP/1.1 200 Test\r\nContent-Length: 100\r\n\r\n{")
        socket.read
      else
        send_json(socket, { models: [] })
      end
    end
    with_http_server(handler) do |url|
      client = client_for(url, timeout: 0.1, retry_policy: { max_retries: 1, backoff_initial_ms: 0 })
      expect(client.models.list).to eq([])
      expect(attempts).to eq(2)
    end
  end

  [(2**31) - 1, 2**31].each do |milliseconds|
    [false, true].each do |per_call|
      it "#8 handles #{milliseconds}ms timeouts without a 1ms clamp (per_call=#{per_call})" do
        handler = lambda do |socket, *|
          sleep 0.03
          send_json(socket, { models: [] })
        end
        with_http_server(handler) do |url|
          seconds = milliseconds / 1000.0
          client = client_for(url, timeout: per_call ? 1 : seconds)
          expect(client.models.list(**(per_call ? { timeout: seconds } : {}))).to eq([])
        end
      end
    end
  end

  it "does not silently retry a GET when retries are disabled" do
    attempts = 0
    handler = ->(*) { attempts += 1 }
    with_http_server(handler) do |url|
      expect { client_for(url).models.list }.to raise_error(Typesafe::SDK::APIConnectionError)
      expect(attempts).to eq(1)
    end
  end

  it "never opens a connection for a canceled signal" do
    signal = Typesafe::SDK::Signal.new
    signal.cancel
    with_http_server(->(*) { raise "Unexpected connection" }) do |url|
      expect { client_for(url).models.list(signal: signal) }.to raise_error(Typesafe::SDK::APIUserAbortError)
    end
  end

  it "sends protected headers and a JSON body through the real adapter" do
    observed = Queue.new
    handler = lambda do |socket, line, headers, body|
      observed << [line, headers, JSON.parse(body)]
      send_json(socket, { model: "jev-latest", answers: {}, usage: {} })
    end
    with_http_server(handler) do |url|
      client_for(url, default_headers: { "AUTHORIZATION" => "bad", "X-Team" => "default" }).system_one(
        state: { doc: "hello" }, questions: { q: Typesafe::SDK.noul("Question?") },
        headers: { "Content-Type" => "bad", "x-team" => "call", "X-TypeSafe-Retry-Count" => "99" }
      )
      line, headers, body = observed.pop
      expect(line).to start_with("POST /v1/systemone ")
      expect(headers).to include("authorization" => "Bearer test", "content-type" => "application/json",
                                 "x-team" => "call")
      expect(headers).not_to have_key("x-typesafe-retry-count")
      expect(body).to include("state" => { "doc" => "hello" }, "model" => "jev-latest")
    end
  end
end
