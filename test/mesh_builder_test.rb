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
end
