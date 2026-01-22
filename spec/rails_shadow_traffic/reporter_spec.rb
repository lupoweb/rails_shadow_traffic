# frozen_string_literal: true

require 'rails_shadow_traffic/reporter'
require 'rails_shadow_traffic/config'
require 'active_support/notifications'
require 'net/http'

RSpec.describe RailsShadowTraffic::Reporter do
  let(:config) { RailsShadowTraffic::Config.instance }
  let(:request_payload) { { method: 'GET', path: '/test', query_string: '', headers: {}, body: '' } }
  let(:original_response_payload) { { status: 200, headers: {}, body: 'original' } }
  let(:shadow_response_mock) do
    instance_double(Net::HTTPResponse, code: '200', each_header: {}, body: 'shadow')
  end

  before do
    config.reset!
    config.log_rate_limit_per_second = 100 # Ensure logs are always allowed for tests
    config.finalize!
    # Clear any previous notifications for a clean test environment
    ActiveSupport::Notifications.unsubscribe(:all) if defined?(ActiveSupport::Notifications)
  end

  describe ".report" do
    context "when responses match" do
      let(:mismatches) { [] }

      it "instruments 'shadow_traffic.ok' event" do
        expect(ActiveSupport::Notifications).to receive(:instrument).with('shadow_traffic.ok', hash_including(request: request_payload))
        described_class.report(request_payload, original_response_payload, shadow_response_mock, mismatches, config)
      end

      it "logs a success message" do
        expect(Rails.logger).to receive(:info).with(/Comparison Result: OK/)
        described_class.report(request_payload, original_response_payload, shadow_response_mock, mismatches, config)
      end
    end

    context "when responses mismatch" do
      let(:mismatches) { [{ type: :status, original: 200, shadow: 500 }] }

      it "instruments 'shadow_traffic.mismatch' event" do
        expect(ActiveSupport::Notifications).to receive(:instrument).with('shadow_traffic.mismatch', hash_including(request: request_payload, mismatches: mismatches))
        described_class.report(request_payload, original_response_payload, shadow_response_mock, mismatches, config)
      end

      it "logs a mismatch message" do
        expect(Rails.logger).to receive(:info).with(/Comparison Result: MISMATCH - Mismatches: 1/)
        described_class.report(request_payload, original_response_payload, shadow_response_mock, mismatches, config)
      end
    end
  end

  describe ".report_error" do
    let(:error) { StandardError.new("Something went wrong") }

    it "instruments 'shadow_traffic.error' event" do
      expect(ActiveSupport::Notifications).to receive(:instrument).with('shadow_traffic.error', hash_including(request: request_payload, error: hash_including(class: 'StandardError')))
      described_class.report_error(request_payload, error, config)
    end

    it "logs an error message" do
      expect(Rails.logger).to receive(:error).with(/Shadow Request Error: StandardError: Something went wrong/)
      described_class.report_error(request_payload, error, config)
    end
  end
end
