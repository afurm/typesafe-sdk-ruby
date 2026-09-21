# frozen_string_literal: true

require "spec_helper"
require "open3"
require "tempfile"

RSpec.describe "Release validation" do
  let(:script) { File.expand_path("../../../script/check_release.rb", __dir__) }

  it "accepts the current upstream package version" do
    Tempfile.create(["upstream", ".json"]) do |file|
      file.write(JSON.generate(version: Typesafe::SDK::UPSTREAM_VERSION))
      file.flush
      output, status = Open3.capture2e({ "RELEASE_TAG" => nil }, RbConfig.ruby, script, file.path)
      expect(status.success?).to be(true), output
    end
  end

  it "rejects a mismatched upstream package version" do
    Tempfile.create(["upstream", ".json"]) do |file|
      file.write(JSON.generate(version: "0.0.0"))
      file.flush
      output, status = Open3.capture2e({ "RELEASE_TAG" => nil }, RbConfig.ruby, script, file.path)
      expect(status.success?).to be(false)
      expect(output).to include("Official JS package version mismatch")
    end
  end

  it "rejects a tag different from the packaged version" do
    output, status = Open3.capture2e({ "RELEASE_TAG" => "v0.0.0" }, RbConfig.ruby, script)
    expect(status.success?).to be(false)
    expect(output).to include("does not match")
  end
end
