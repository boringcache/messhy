require 'test_helper'

class HealthCheckerTest < Minitest::Test
  def test_initialization
    config_hash = { 'test' => { 'nodes' => {} } }
    config = Messhy::Configuration.new(config_hash, 'test')
    health_checker = Messhy::HealthChecker.new(config)

    assert_equal config, health_checker.config
  end

  def test_handshake_staleness_limit_constant
    assert_equal 180, Messhy::HealthChecker::HANDSHAKE_STALENESS_LIMIT
  end
end
