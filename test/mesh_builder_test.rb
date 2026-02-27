require 'test_helper'

class MeshBuilderTest < Minitest::Test
  def test_initialization
    config_hash = { 'test' => { 'nodes' => {} } }
    config = Messhy::Configuration.new(config_hash, 'test')
    node_keys = { 'node1' => { private_key: 'key1', public_key: 'pub1' } }
    psk_map = { 'node1-node2' => 'psk123' }

    builder = Messhy::MeshBuilder.new(config, node_keys, psk_map)

    assert_equal config, builder.config
    assert_equal node_keys, builder.node_keys
    assert_equal psk_map, builder.psk_map
  end

  def test_build_all_configs_returns_hash
    config_hash = {
      'test' => {
        'nodes' => {
          'node1' => { 'host' => '1.1.1.1', 'private_ip' => '10.8.0.1' },
          'node2' => { 'host' => '2.2.2.2', 'private_ip' => '10.8.0.2' }
        }
      }
    }
    config = Messhy::Configuration.new(config_hash, 'test')
    node_keys = {
      'node1' => { private_key: 'key1', public_key: 'pub1' },
      'node2' => { private_key: 'key2', public_key: 'pub2' }
    }
    psk_map = { 'node1-node2' => 'psk123' }

    builder = Messhy::MeshBuilder.new(config, node_keys, psk_map)
    configs = builder.build_all_configs

    assert_kind_of Hash, configs
    assert configs.key?('node1')
    assert configs.key?('node2')
  end

  def test_build_config_for_node_raises_for_unknown_node
    config_hash = { 'test' => { 'nodes' => {} } }
    config = Messhy::Configuration.new(config_hash, 'test')
    builder = Messhy::MeshBuilder.new(config, {}, {})

    error = assert_raises(Messhy::Error) do
      builder.build_config_for_node('nonexistent')
    end
    assert_match(/Node not found/, error.message)
  end

  def test_build_config_includes_dns_postup_when_dns_enabled
    config_hash = {
      'test' => {
        'nodes' => {
          'node1' => { 'host' => '1.1.1.1', 'private_ip' => '10.8.0.1' },
          'node2' => { 'host' => '2.2.2.2', 'private_ip' => '10.8.0.2' },
          'dns-server' => { 'host' => '3.3.3.3', 'private_ip' => '10.8.0.3' }
        },
        'dns' => {
          'enabled' => true,
          'provider' => 'dnsmasq',
          'domain' => 'mesh.internal',
          'interface' => 'wg0',
          'servers' => ['dns-server']
        }
      }
    }
    config = Messhy::Configuration.new(config_hash, 'test')
    node_keys = {
      'node1' => { private_key: 'key1', public_key: 'pub1' },
      'node2' => { private_key: 'key2', public_key: 'pub2' },
      'dns-server' => { private_key: 'key3', public_key: 'pub3' }
    }
    psk_map = {
      'dns-server-node1' => 'psk1',
      'dns-server-node2' => 'psk2',
      'node1-node2' => 'psk3'
    }

    builder = Messhy::MeshBuilder.new(config, node_keys, psk_map)
    wg_config = builder.build_config_for_node('node1')

    assert_includes wg_config, 'PostUp = resolvectl dns wg0 10.8.0.3'
    assert_includes wg_config, 'PostUp = resolvectl domain wg0 ~mesh.internal'
  end

  def test_build_config_omits_dns_postup_when_dns_disabled
    config_hash = {
      'test' => {
        'nodes' => {
          'node1' => { 'host' => '1.1.1.1', 'private_ip' => '10.8.0.1' },
          'node2' => { 'host' => '2.2.2.2', 'private_ip' => '10.8.0.2' }
        }
      }
    }
    config = Messhy::Configuration.new(config_hash, 'test')
    node_keys = {
      'node1' => { private_key: 'key1', public_key: 'pub1' },
      'node2' => { private_key: 'key2', public_key: 'pub2' }
    }
    psk_map = { 'node1-node2' => 'psk123' }

    builder = Messhy::MeshBuilder.new(config, node_keys, psk_map)
    wg_config = builder.build_config_for_node('node1')

    refute_includes wg_config, 'resolvectl'
  end

  def test_build_config_for_node_raises_for_missing_keys
    config_hash = {
      'test' => {
        'nodes' => {
          'node1' => { 'host' => '1.1.1.1', 'private_ip' => '10.8.0.1' }
        }
      }
    }
    config = Messhy::Configuration.new(config_hash, 'test')
    builder = Messhy::MeshBuilder.new(config, {}, {})

    error = assert_raises(Messhy::Error) do
      builder.build_config_for_node('node1')
    end
    assert_match(/Keys not found/, error.message)
  end

  def test_build_config_includes_dnsmasq_restart_for_dns_server_node
    config_hash = {
      'test' => {
        'nodes' => {
          'node1' => { 'host' => '1.1.1.1', 'private_ip' => '10.8.0.1' },
          'dns-server' => { 'host' => '3.3.3.3', 'private_ip' => '10.8.0.3' }
        },
        'dns' => {
          'enabled' => true,
          'provider' => 'dnsmasq',
          'domain' => 'mesh.internal',
          'interface' => 'wg0',
          'servers' => ['dns-server']
        }
      }
    }
    config = Messhy::Configuration.new(config_hash, 'test')
    node_keys = {
      'node1' => { private_key: 'key1', public_key: 'pub1' },
      'dns-server' => { private_key: 'key3', public_key: 'pub3' }
    }
    psk_map = { 'dns-server-node1' => 'psk1' }

    builder = Messhy::MeshBuilder.new(config, node_keys, psk_map)
    wg_config = builder.build_config_for_node('dns-server')

    assert_includes wg_config, 'PostUp = sleep 1 && systemctl restart dnsmasq || true'
  end

  def test_build_config_omits_dnsmasq_restart_for_non_dns_node
    config_hash = {
      'test' => {
        'nodes' => {
          'node1' => { 'host' => '1.1.1.1', 'private_ip' => '10.8.0.1' },
          'dns-server' => { 'host' => '3.3.3.3', 'private_ip' => '10.8.0.3' }
        },
        'dns' => {
          'enabled' => true,
          'provider' => 'dnsmasq',
          'domain' => 'mesh.internal',
          'interface' => 'wg0',
          'servers' => ['dns-server']
        }
      }
    }
    config = Messhy::Configuration.new(config_hash, 'test')
    node_keys = {
      'node1' => { private_key: 'key1', public_key: 'pub1' },
      'dns-server' => { private_key: 'key3', public_key: 'pub3' }
    }
    psk_map = { 'dns-server-node1' => 'psk1' }

    builder = Messhy::MeshBuilder.new(config, node_keys, psk_map)
    wg_config = builder.build_config_for_node('node1')

    refute_includes wg_config, 'systemctl restart dnsmasq'
  end
end
