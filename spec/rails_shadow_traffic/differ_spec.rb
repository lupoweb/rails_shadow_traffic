# frozen_string_literal: true

require 'rails_shadow_traffic/differ'
require 'rails_shadow_traffic/config'
require 'net/http'

RSpec.describe RailsShadowTraffic::Differ do
  let(:config) { RailsShadowTraffic::Config.new }
  let(:original_response_payload) do
    {
      status: 200,
      headers: { 'Content-Type' => 'application/json', 'X-Request-Id' => 'orig-123' },
      body: { message: 'hello original', timestamp: 12345 }.to_json
    }
  end
  let(:shadow_response_mock) do
    instance_double(Net::HTTPResponse,
                    code: '200',
                    content_type: 'application/json',
                    body: { message: 'hello shadow', timestamp: 12345 }.to_json,
                    each_header: { 'content-type' => ['application/json'], 'x-request-id' => ['shadow-456'] })
  end

  before do
    config.diff_enabled = true
    config.finalize!
  end

  subject { described_class.new(original_response_payload, shadow_response_mock, config).diff }

  context "when diffing is disabled" do
    before { config.diff_enabled = false }
    it { is_expected.to be_empty }
  end

  context "when responses are identical" do
    let(:shadow_response_mock) do
      instance_double(Net::HTTPResponse,
                      code: '200',
                      content_type: 'application/json',
                      body: { message: 'hello original', timestamp: 12345 }.to_json,
                      each_header: { 'content-type' => ['application/json'], 'x-request-id' => ['orig-123'] })
    end
    it { is_expected.to be_empty }
  end

  describe "status code comparison" do
    context "when status codes differ" do
      let(:shadow_response_mock) { instance_double(Net::HTTPResponse, code: '500', content_type: 'application/json', body: '{}', each_header: {}) }
      it "reports a status mismatch" do
        expect(subject).to include(
          type: :status,
          original: 200,
          shadow: 500
        )
      end
    end
  end

  describe "header comparison" do
    context "when headers differ" do
      let(:shadow_response_mock) do
        instance_double(Net::HTTPResponse,
                        code: '200',
                        content_type: 'application/json',
                        body: original_response_payload[:body],
                        each_header: { 'content-type' => ['application/json'], 'X-New-Header' => ['value'] })
      end
      it "reports header mismatches" do
        expect(subject).to include(
          type: :header,
          key: 'x-request-id',
          original: { 'x-request-id' => 'orig-123' }.with_indifferent_access['x-request-id'], # Access the normalized value
          shadow: nil
        )
        expect(subject).to include(
          type: :header,
          key: 'x-new-header',
          original: nil,
          shadow: { 'x-new-header' => ['value'] }.with_indifferent_access['x-new-header']
        )
      end
    end
  end

  describe "body comparison" do
    context "when text bodies differ" do
      let(:original_response_payload) do
        { status: 200, headers: { 'Content-Type' => 'text/plain' }, body: 'Original text' }
      end
      let(:shadow_response_mock) do
        instance_double(Net::HTTPResponse,
                        code: '200',
                        content_type: 'text/plain',
                        body: 'Shadow text',
                        each_header: { 'content-type' => ['text/plain'] })
      end
      it "reports a text body mismatch" do
        expect(subject).to include(
          type: :body,
          format: :text,
          original: 'Original text',
          shadow: 'Shadow text'
        )
      end
    end

    context "when JSON bodies differ" do
      let(:shadow_response_mock) do
        instance_double(Net::HTTPResponse,
                        code: '200',
                        content_type: 'application/json',
                        body: { message: 'hello changed', new_field: 123 }.to_json,
                        each_header: { 'content-type' => ['application/json'] })
      end
      it "reports a JSON body mismatch" do
        expect(subject).to include(
          type: :body,
          format: :json,
          original: { message: 'hello original', timestamp: 12345 }.with_indifferent_access,
          shadow: { message: 'hello changed', new_field: 123 }.with_indifferent_access
        )
      end
    end

    context "when JSON bodies contain ignored paths" do
      before { config.diff_ignore_json_paths = ['timestamp', 'meta.request_id'] }

      let(:original_body_data) { { message: 'hello original', timestamp: 12345, meta: { request_id: 'orig-req-id' } } }
      let(:shadow_body_data) { { message: 'hello original', timestamp: 54321, meta: { request_id: 'shadow-req-id', other: 'val' } } }

      let(:original_response_payload) do
        { status: 200, headers: { 'Content-Type' => 'application/json' }, body: original_body_data.to_json }
      end
      let(:shadow_response_mock) do
        instance_double(Net::HTTPResponse,
                        code: '200',
                        content_type: 'application/json',
                        body: shadow_body_data.to_json,
                        each_header: { 'content-type' => ['application/json'] })
      end

      it "ignores specified JSON paths during comparison" do
        expect(subject).to be_empty # Mismatches only in ignored fields
      end

      it "still reports differences outside ignored paths" do
        shadow_body_data[:message] = 'different message'
        expect(subject).to include(
          type: :body,
          format: :json,
          original: { message: 'hello original', meta: {} }.with_indifferent_access, # Normalized original
          shadow: { message: 'different message', meta: {other: 'val'}}.with_indifferent_access # Normalized shadow
        )
      end

      context "with nested ignored paths" do
        before { config.diff_ignore_json_paths = ['user.address.street', 'items.id'] } # items.id will ignore id in any item

        let(:original_body_data) { { user: { name: 'A', address: { street: 'Main St', city: 'City' } }, items: [{ id: 1, name: 'ItemA' }] } }
        let(:shadow_body_data) { { user: { name: 'A', address: { street: 'Other St', city: 'City' } }, items: [{ id: 2, name: 'ItemA' }] } }

        it "ignores nested paths correctly" do
          expect(subject).to be_empty
        end

        it "handles non-existent paths gracefully" do
          config.diff_ignore_json_paths = ['non.existent.path']
          expect(subject).to be_empty # Should still be empty if only ignored fields differ
        end
      end
    end

    context "with invalid JSON bodies" do
      let(:original_response_payload) do
        { status: 200, headers: { 'Content-Type' => 'application/json' }, body: '{"broken":' }
      end
      let(:shadow_response_mock) do
        instance_double(Net::HTTPResponse,
                        code: '200',
                        content_type: 'application/json',
                        body: '{}',
                        each_header: { 'content-type' => ['application/json'] })
      end

      it "reports a JSON parse error" do
        expect(subject).to include(
          type: :body,
          format: :json_parse_error,
          error: /unexpected token at '\{"broken":'/,
          original_raw: '{"broken":',
          shadow_raw: '{}'
        )
      end
    end

    context "when content types mismatch" do
      let(:original_response_payload) do
        { status: 200, headers: { 'Content-Type' => 'application/json' }, body: '{"key":"value"}' }
      end
      let(:shadow_response_mock) do
        instance_double(Net::HTTPResponse,
                        code: '200',
                        content_type: 'text/html',
                        body: '<html></html>',
                        each_header: { 'content-type' => ['text/html'] })
      end
      it "falls back to text comparison if content-types are different (even if one is JSON)" do
        expect(subject).to include(
          type: :body,
          format: :text,
          original: '{"key":"value"}',
          shadow: '<html></html>'
        )
      end
    end
  end
end
