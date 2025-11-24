require 'test_helper'

class ConfigurationTest < Minitest::Test
  def test_initialization_with_defaults
    config_hash = {
      'development' => {
        'nodes' => {
          'node1' => { 'host' => '1.2.3.4', 'private_ip' => '10.8.0.1' }
        }
      }
    }
    config = Messhy::Configuration.new(config_hash, 'development')

    assert_equal 'development', config.environment
    assert_equal '10.8.0.0/24', config.network
    assert_equal 'ubuntu', config.user
    assert_equal 1280, config.mtu
    assert_equal 51_820, config.listen_port
    assert_equal 25, config.keepalive
    assert_equal true, config.verify_host_key
  end

  def test_initialization_with_custom_values
    config_hash = {
      'production' => {
        'network' => '10.9.0.0/16',
        'user' => 'deploy',
        'mtu' => 1420,
        'listen_port' => 55_555,
        'keepalive' => 30,
        'verify_host_key' => false,
        'nodes' => {
          'server1' => { 'host' => '5.6.7.8', 'private_ip' => '10.9.0.1' }
        }
      }
    }
    config = Messhy::Configuration.new(config_hash, 'production')

    assert_equal 'production', config.environment
    assert_equal '10.9.0.0/16', config.network
    assert_equal 'deploy', config.user
    assert_equal 1420, config.mtu
    assert_equal 55_555, config.listen_port
    assert_equal 30, config.keepalive
    assert_equal false, config.verify_host_key
  end

  def test_node_names
    config_hash = {
      'test' => {
        'nodes' => {
          'alpha' => { 'host' => '1.1.1.1', 'private_ip' => '10.8.0.1' },
          'beta' => { 'host' => '2.2.2.2', 'private_ip' => '10.8.0.2' }
        }
      }
    }
    config = Messhy::Configuration.new(config_hash, 'test')

    assert_equal ['alpha', 'beta'], config.node_names
  end

  def test_node_config
    config_hash = {
      'test' => {
        'nodes' => {
          'alpha' => { 'host' => '1.1.1.1', 'private_ip' => '10.8.0.1' }
        }
      }
    }
    config = Messhy::Configuration.new(config_hash, 'test')

    node = config.node_config('alpha')
    assert_equal '1.1.1.1', node['host']
    assert_equal '10.8.0.1', node['private_ip']
  end

  def test_network_prefix_length
    config_hash = {
      'test' => {
        'network' => '10.10.0.0/16',
        'nodes' => {}
      }
    }
    config = Messhy::Configuration.new(config_hash, 'test')

    assert_equal 16, config.network_prefix_length
  end

  def test_network_prefix_length_defaults_to_24
    config_hash = {
      'test' => {
        'network' => '10.10.0.0',
        'nodes' => {}
      }
    }
    config = Messhy::Configuration.new(config_hash, 'test')

    assert_equal 24, config.network_prefix_length
  end

  def test_validate_raises_when_no_nodes
    config_hash = {
      'test' => {
        'nodes' => {}
      }
    }
    config = Messhy::Configuration.new(config_hash, 'test')

    error = assert_raises(Messhy::Error) { config.validate! }
    assert_match(/No nodes defined/, error.message)
  end

  def test_validate_raises_when_node_missing_host
    config_hash = {
      'test' => {
        'nodes' => {
          'bad_node' => { 'private_ip' => '10.8.0.1' }
        }
      }
    }
    config = Messhy::Configuration.new(config_hash, 'test')

    error = assert_raises(Messhy::Error) { config.validate! }
    assert_match(/missing 'host'/, error.message)
  end

  def test_validate_raises_when_node_missing_private_ip
    config_hash = {
      'test' => {
        'nodes' => {
          'bad_node' => { 'host' => '1.2.3.4' }
        }
      }
    }
    config = Messhy::Configuration.new(config_hash, 'test')

    error = assert_raises(Messhy::Error) { config.validate! }
    assert_match(/missing 'private_ip'/, error.message)
  end

  def test_validate_returns_true_when_valid
    config_hash = {
      'test' => {
        'nodes' => {
          'node1' => { 'host' => '1.2.3.4', 'private_ip' => '10.8.0.1' }
        }
      }
    }
    config = Messhy::Configuration.new(config_hash, 'test')

    assert config.validate!
  end

  def test_verify_host_key_mode_always
    config_hash = { 'test' => { 'verify_host_key' => true, 'nodes' => {} } }
    config = Messhy::Configuration.new(config_hash, 'test')
    assert_equal :always, config.verify_host_key_mode

    config_hash = { 'test' => { 'verify_host_key' => 'always', 'nodes' => {} } }
    config = Messhy::Configuration.new(config_hash, 'test')
    assert_equal :always, config.verify_host_key_mode
  end

  def test_verify_host_key_mode_accept_new
    config_hash = { 'test' => { 'verify_host_key' => 'accept_new', 'nodes' => {} } }
    config = Messhy::Configuration.new(config_hash, 'test')
    assert_equal :accept_new, config.verify_host_key_mode
  end

  def test_verify_host_key_mode_never
    config_hash = { 'test' => { 'verify_host_key' => false, 'nodes' => {} } }
    config = Messhy::Configuration.new(config_hash, 'test')
    assert_equal :never, config.verify_host_key_mode

    config_hash = { 'test' => { 'verify_host_key' => 'never', 'nodes' => {} } }
    config = Messhy::Configuration.new(config_hash, 'test')
    assert_equal :never, config.verify_host_key_mode
  end
end
