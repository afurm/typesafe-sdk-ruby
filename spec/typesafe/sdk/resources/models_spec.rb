# frozen_string_literal: true

require "spec_helper"

RSpec.describe Typesafe::SDK::Resources::Models do
  let(:http) { instance_double(Typesafe::SDK::HTTP) }
  let(:client) do
    Typesafe::SDK::Client.new(api_key: "k", http: http, logger: NullLogger.new)
  end

  class NullLogger
    %i[debug info warn error].each { |m| define_method(m) { |*, **| } }
  end

  def response(status, body)
    Typesafe::SDK::Response.new(
      status: status,
      headers: Typesafe::SDK::Headers.new({}),
      body: body,
      request_id: nil
    )
  end

  describe "#list" do
    it "returns model cards" do
      allow(http).to receive(:request).and_return(response(200, {
                                                             "models" => [
                                                               {
                                                                 "name" => "jev-latest",
                                                                 "description" => "d",
                                                                 "release_date" => "2026-01-01"
                                                               }
                                                             ]
                                                           }))

      models = client.models.list
      expect(models.length).to eq(1)
      expect(models.first).to be_a(Typesafe::SDK::ModelCard)
      expect(models.first.name).to eq("jev-latest")
    end

    it "raises on an unexpected shape" do
      allow(http).to receive(:request).and_return(response(200, { "nope" => [] }))
      expect { client.models.list }.to raise_error(Typesafe::SDK::TypeSafeError, /Unexpected response shape/)
    end

    it "raises APIError on error statuses" do
      allow(http).to receive(:request).and_return(response(401, { "error" => "bad key" }))
      expect { client.models.list }.to raise_error(Typesafe::SDK::AuthenticationError)
    end
  end
end
