require 'test_helper'
require 'tempfile'

class HostTrustManagerTest < Minitest::Test
  def test_initialization_with_defaults
    config_hash = { 'test' => { 'nodes' => {} } }
    config = Messhy::Configuration.new(config_hash, 'test')
    manager = Messhy::HostTrustManager.new(config)

    refute_nil manager
  end

  def test_initialization_with_custom_options
    config_hash = { 'test' => { 'nodes' => {} } }
    config = Messhy::Configuration.new(config_hash, 'test')

    Tempfile.create('known_hosts') do |f|
      manager = Messhy::HostTrustManager.new(
        config,
        known_hosts_path: f.path,
        timeout: 10,
        hash_hosts: true
      )

      refute_nil manager
    end
  end

  def test_default_timeout_constant
    assert_equal 5, Messhy::HostTrustManager::DEFAULT_TIMEOUT
  end

  def test_default_key_types_constant
    assert_equal %w[ed25519 ecdsa rsa], Messhy::HostTrustManager::DEFAULT_KEY_TYPES
  end
end
