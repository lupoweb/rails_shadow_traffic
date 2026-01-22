# frozen_string_literal: true

require 'rails_shadow_traffic/sampler'
require 'rails_shadow_traffic/config'
require 'rack/request'
require 'stringio'

RSpec.describe RailsShadowTraffic::Sampler do
  let(:config) { RailsShadowTraffic::Config.instance }
  let(:env) do
    {
      'REQUEST_METHOD' => 'GET',
      'PATH_INFO' => '/api/v1/users',
      'rack.input' => StringIO.new,
      'HTTP_X_REQUEST_ID' => 'test-id'
    }
  end
  let(:request) { Rack::Request.new(env) }

  before do
    config.reset!
    config.enabled = true
    config.finalize!
  end

  describe ".sample?" do
    context "with cheap checks" do
      it "returns false if disabled" do
        config.enabled = false
        expect(described_class.sample?(request, config)).to be false
      end

      it "returns false if method is not allowed" do
        config.only_methods = ['POST']
        config.finalize!
        expect(described_class.sample?(request, config)).to be false
      end

      it "returns false if path is not allowed" do
        config.only_paths = ['/api/v2/users']
        config.finalize!
        expect(described_class.sample?(request, config)).to be false
      end

      it "returns false if sample_rate is 0" do
        config.sample_rate = 0.0
        expect(described_class.sample?(request, config)).to be false
      end
    end

    context "with order of operations" do
      it "does not perform rate check if path is disallowed" do
        config.only_paths = ['/other']
        config.finalize!
        # We expect it to return false without ever calling the expensive rate_allowed?
        expect(described_class).not_to receive(:rate_allowed?)
        described_class.sample?(request, config)
      end

      it "does not call condition if rate check fails" do
        config.sample_rate = 0.01
        # Mock rate_allowed? to fail
        allow(described_class).to receive(:rate_allowed?).and_return(false)
        # We expect it to return false without ever calling the most expensive check
        expect(described_class).not_to receive(:condition_met?)
        described_class.sample?(request, config)
      end

      it "calls condition if sample_rate is 1.0" do
        config.sample_rate = 1.0
        # Condition will be the deciding factor
        expect(described_class).to receive(:condition_met?).and_return(true)
        expect(described_class.sample?(request, config)).to be true
      end
    end

    context "with rate_allowed? logic" do
      context "with :random sampler" do
        before { config.sampler = :random }

        it "returns true if Kernel.rand is below rate" do
          config.sample_rate = 0.5
          allow(Kernel).to receive(:rand).and_return(0.49)
          expect(described_class.sample?(request, config)).to be true
        end

        it "returns false if Kernel.rand is above rate" do
          config.sample_rate = 0.5
          allow(Kernel).to receive(:rand).and_return(0.5)
          expect(described_class.sample?(request, config)).to be false
        end
      end

      context "with :stable_hash sampler" do
        before do
          config.sampler = :stable_hash
          config.sample_rate = 0.5
        end

        it "returns false if identifier cannot be extracted" do
          env.delete('HTTP_X_REQUEST_ID') # No default identifier
          expect(described_class.sample?(request, config)).to be false
        end

        it "uses identifier_extractor when provided" do
          env['HTTP_X_SESSION_ID'] = 'session-123'
          config.identifier_extractor = ->(req) { req.get_header('HTTP_X_SESSION_ID') }
          
          # MD5 hash of 'session-123' gives a value that should pass a 0.5 rate
          # This test is deterministic based on the hash32 implementation
          expect(described_class.sample?(request, config)).to be true
        end

        it "uses hash_scope to change the hashed value" do
          # The identifier is the same, but the scope (path) is different
          path1 = '/api/v1/users'
          path2 = '/api/v1/products'
          
          config.hash_scope = ->(req, id) { "#{id}:#{req.path_info}" }
          
          env['PATH_INFO'] = path1
          decision1 = described_class.sample?(request, config)
          
          env['PATH_INFO'] = path2
          decision2 = described_class.sample?(request, config)

          # With a good hash function, the decisions should be different
          expect(decision1).not_to eq(decision2)
        end

        it "uses HMAC when sampling_key is provided" do
          config.sampling_key = "a-secret-key"
          # Mock OpenSSL to confirm it's being called
          expect(OpenSSL::HMAC).to receive(:digest).and_call_original
          described_class.sample?(request, config)
        end
      end
    end

    context "with condition_met? logic" do
      before do
        config.sample_rate = 1.0 # Ensure condition is always called
      end

      it "returns true if condition passes" do
        config.condition = ->(req) { req.path_info == '/api/v1/users' }
        expect(described_class.sample?(request, config)).to be true
      end

      it "returns false if condition fails" do
        config.condition = ->(req) { false }
        expect(described_class.sample?(request, config)).to be false
      end

      it "returns false and records failure on timeout" do
        config.condition_timeout = 0.001
        config.condition = ->(_req) { sleep 0.002 }
        
        expect(config).to receive(:record_condition_failure!)
        expect(described_class.sample?(request, config)).to be false
      end

      it "returns false if circuit breaker is open" do
        # Manually open the circuit for testing
        allow(config).to receive(:circuit_open?).and_return(true)
        
        # The condition proc itself should not even be called
        expect(config.condition).not_to receive(:call)
        expect(described_class.sample?(request, config)).to be false
      end
    end
  end
end
