# frozen_string_literal: true

require 'rails_shadow_traffic/scrubber'
require 'rails_shadow_traffic/config'

RSpec.describe RailsShadowTraffic::Scrubber do
  let(:config) { RailsShadowTraffic::Config.instance }

  let(:payload) do
    {
      headers: {
        'Content-Type' => 'application/json',
        'Authorization' => 'Bearer some-token',
        'Cookie' => 'user_session_id=12345',
        'X-Custom-Header' => 'some-value'
      },
      body: ''
    }
  end

  before do
    config.reset!
    # Set default scrub rules
    config.scrub_headers = ['Authorization', 'Cookie']
    config.scrub_json_fields = ['password', 'token']
    config.scrub_mask = '[FILTERED]'
    config.finalize! # Normalize and freeze rules
  end

  describe ".scrub!" do # <-- ADDED THIS BLOCK
    context "with header scrubbing" do
      it "removes sensitive headers" do
        described_class.scrub!(payload, config)
        expect(payload[:headers]).to have_key('Content-Type')
        expect(payload[:headers]).to have_key('X-Custom-Header')
        expect(payload[:headers]).not_to have_key('Authorization')
        expect(payload[:headers]).not_to have_key('Cookie')
      end

      it "is case-insensitive when scrubbing headers" do
        payload[:headers] = { 'authorization' => 'Bearer some-token' }
        config.scrub_headers = ['Authorization']
        config.finalize!

        described_class.scrub!(payload, config)
        expect(payload[:headers]).to be_empty
      end
    end

    context "with JSON body scrubbing" do
      it "does not scrub if content-type is not application/json" do
        payload[:headers]['Content-Type'] = 'text/plain'
        payload[:body] = '{"password":"test"}'
        
        described_class.scrub!(payload, config)
        expect(payload[:body]).to eq('{"password":"test"}')
      end

      it "does not scrub if body is not valid JSON" do
        payload[:body] = 'not-json'
        described_class.scrub!(payload, config)
        expect(payload[:body]).to eq('not-json')
      end

      it "masks top-level sensitive fields" do
        payload[:body] = { password: 'my-secret-password', user: 'test' }.to_json
        described_class.scrub!(payload, config)
        
        scrubbed_body = JSON.parse(payload[:body])
        expect(scrubbed_body['password']).to eq('[FILTERED]')
        expect(scrubbed_body['user']).to eq('test')
      end

      it "masks nested sensitive fields" do
        payload[:body] = { data: { user: { token: 'abc-123' } }, other: 'value' }.to_json
        described_class.scrub!(payload, config)
        
        scrubbed_body = JSON.parse(payload[:body])
        expect(scrubbed_body['data']['user']['token']).to eq('[FILTERED]')
        expect(scrubbed_body['other']).to eq('value')
      end

      it "masks sensitive fields within an array of objects" do
        payload[:body] = {
          users: [
            { id: 1, token: 'token1' },
            { id: 2, token: 'token2' }
          ]
        }.to_json
        described_class.scrub!(payload, config)

        scrubbed_body = JSON.parse(payload[:body])
        expect(scrubbed_body['users'][0]['token']).to eq('[FILTERED]')
        expect(scrubbed_body['users'][1]['token']).to eq('[FILTERED]')
        expect(scrubbed_body['users'][0]['id']).to eq(1)
      end
    end
  end
