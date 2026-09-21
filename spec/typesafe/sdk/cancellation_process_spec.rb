# frozen_string_literal: true

require "spec_helper"
require "open3"

RSpec.describe "Upstream #2 process-level cancellation" do
  %w[system_one models].each do |method|
    [200, 503].each do |status|
      it "handles #{method} cancellation after #{status} headers without terminating the process" do
        root = File.expand_path("../../..", __dir__)
        output, errors, result = Open3.capture3(RbConfig.ruby, "-I", "#{root}/lib",
                                                "#{root}/spec/support/cancellation_process.rb", method, status.to_s)
        expect(result.success?).to be(true), "#{output}\n#{errors}"
        expect(output).to include("Caught APIUserAbortError", "Normal process exit")
        expect(errors).to be_empty
      end
    end
  end
end
