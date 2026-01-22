# frozen_string_literal: true

require 'rails_shadow_traffic/config'

RSpec.describe RailsShadowTraffic::Config do
  # The Config class is a singleton. We get the instance and reset it before each test.
  let(:config) { described_class.instance }

  before do
    config.reset!
  end

  describe "defaults" do
    it "has correct default values" do
      expect(config.enabled).to be false
      expect(config.sample_rate).to eq(0.0)
      expect(config.sampler).to eq(:random)
      expect(config.only_methods).to eq(['GET'])
      expect(config.condition_timeout).to eq(0.01)
      expect(config.condition_failure_threshold).to eq(10)
      expect(config.condition_circuit_cooldown).to eq(60)
      expect(config.log_rate_limit_per_second).to eq(5)
    end
  end

  describe "#validate!" do
    it "raises an error for invalid sample_rate" do
      config.sample_rate = 1.1
      expect { config.validate! }.to raise_error(ArgumentError, /sample_rate/)
    end

    it "raises an error for invalid sampler" do
      config.sampler = :invalid_sampler
      expect { config.validate! }.to raise_error(ArgumentError, /sampler/)
    end

    it "raises an error for non-positive condition_timeout" do
      config.condition_timeout = 0
      expect { config.validate! }.to raise_error(ArgumentError, /condition_timeout/)
    end

    it "clamps the condition_timeout to a maximum of 0.1s" do
      config.condition_timeout = 5.0 # User sets a dangerously high value
      config.validate!
      expect(config.condition_timeout).to eq(0.1)
    end
  end

  describe "#finalize!" do
    it "freezes the config object" do
      config.finalize!
      expect(config).to be_frozen
    end

    it "upcases and freezes only_methods" do
      config.only_methods = ['get', 'post']
      config.finalize!
      expect(config.only_methods).to eq(['GET', 'POST'])
      expect(config.only_methods).to be_frozen
    end
  end

  describe "circuit breaker" do
    before do
      config.condition_failure_threshold = 3
      config.condition_circuit_cooldown = 10 # seconds
    end

    it "is initially closed" do
      expect(config.circuit_open?).to be false
    end

    it "opens the circuit after reaching the failure threshold" do
      2.times { config.record_condition_failure! }
      expect(config.circuit_open?).to be false
      
      config.record_condition_failure!
      expect(config.circuit_open?).to be true
    end

    it "remains open during the cooldown period" do
      3.times { config.record_condition_failure! }
      expect(config.circuit_open?).to be true
    end

    it "resets after the cooldown period" do
      3.times { config.record_condition_failure! }
      expect(config.circuit_open?).to be true

      # Simulate time passing
      allow(Time).to receive(:now).and_return(Time.now + config.condition_circuit_cooldown + 1)
      
      expect(config.circuit_open?).to be false
      expect(config.condition_failure_count).to eq(0)
    end
  end

  describe "logging rate limiter" do
    before do
      config.log_rate_limit_per_second = 2
    end

    it "allows logs within the rate limit" do
      expect(config.log_allowed?(:warn)).to be true
      expect(config.log_allowed?(:warn)).to be true
    end

    it "blocks logs that exceed the rate limit" do
      2.times { config.log_allowed?(:warn) }
      expect(config.log_allowed?(:warn)).to be false
    end

    it "resets the limit after one second" do
      2.times { config.log_allowed?(:warn) }
      expect(config.log_allowed?(:warn)).to be false

      # Simulate time passing
      allow(Time).to receive(:now).and_return(Time.now + 1.1)
      
      expect(config.log_allowed?(:warn)).to be true
    end

    it "handles different log levels independently" do
      2.times { config.log_allowed?(:warn) }
      expect(config.log_allowed?(:warn)).to be false
      expect(config.log_allowed?(:error)).to be true
    end
  end

  describe "thread safety" do
    it "handles concurrent access to circuit breaker and logger" do
      # This is a basic concurrency test. More advanced testing could use `fork`
      # or more sophisticated thread-stressing gems, but this is a good start.
      
      threads = 10.times.map do
        Thread.new do
          5.times do
            config.record_condition_failure!
            config.log_allowed?(:info)
          end
        end
      end

      threads.each(&:join)

      # We expect the final counts to be consistent
      expect(config.condition_failure_count).to eq(50)
    end
  end
end
