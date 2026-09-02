require 'test_helper'
require 'tmpdir'

class InstallerTest < Minitest::Test
  FakeExecutor = Struct.new(:configs, :public_keys) do
    def read_wireguard_config(node_name)
      configs.fetch(node_name)
    end

    def wireguard_public_key(node_name)
      public_keys.fetch(node_name)
    end
  end

  class ReconcileExecutor
    attr_reader :reconciled_configs

    def initialize(configs)
      @configs = configs
      @reconciled_configs = {}
    end

    def install_wireguard_on_all_nodes; end

    def generate_keypair_on_node(node_name)
      { private_key: "private-#{node_name}", public_key: "public-#{node_name}" }
    end

    def generate_psk_on_node(_node_name)
      'managed-shared-key'
    end

    def read_wireguard_config(node_name)
      @configs.fetch(node_name)
    end

    def reconcile_config(node_name, content)
      @reconciled_configs[node_name] = content
    end

    def get_wireguard_status(_node_name)
      "peer: public-peer\n  latest handshake: 1 second ago\n"
    end
  end

  class FastInstaller < Messhy::Installer
    private

    def sleep(*)
      nil
    end
  end

  def test_import_keys_recovers_node_and_peer_material_without_printing_secrets
    config = Messhy::Configuration.new({
                                         'test' => {
                                           'nodes' => {
                                             'one' => { 'host' => '1.2.3.4', 'mesh_ip' => '10.8.0.1' },
                                             'two' => { 'host' => '5.6.7.8', 'mesh_ip' => '10.8.0.2' }
                                           }
                                         }
                                       }, 'test')
    executor = FakeExecutor.new(
      {
        'one' => wireguard_config('one', '10.8.0.1', 'private-one', 'two', 'shared-key'),
        'two' => wireguard_config('two', '10.8.0.2', 'private-two', 'one', 'shared-key')
      },
      { 'one' => 'public-one', 'two' => 'public-two' }
    )

    Dir.mktmpdir do |directory|
      output = capture_io do
        Dir.chdir(directory) { Messhy::Installer.new(config, ssh_executor: executor).import_keys }
      end.first

      one = YAML.load_file(File.join(directory, '.secrets/wireguard/one.yml'))
      psks = YAML.load_file(File.join(directory, '.secrets/wireguard/psks.yml'))
      assert_equal 'private-one', one.fetch('private_key')
      assert_equal 'public-one', one.fetch('public_key')
      assert_equal 'shared-key', psks.fetch('pairs').fetch('one-two')
      refute_includes output, 'private-one'
      refute_includes output, 'shared-key'
    end
  end

  def test_reconcile_preserves_live_peers_outside_the_source_mesh
    config = Messhy::Configuration.new({
                                         'test' => {
                                           'nodes' => {
                                             'one' => { 'host' => '1.2.3.4', 'mesh_ip' => '10.8.0.1' },
                                             'two' => { 'host' => '5.6.7.8', 'mesh_ip' => '10.8.0.2' }
                                           }
                                         }
                                       }, 'test')
    executor = ReconcileExecutor.new(
      'one' => wireguard_config('one', '10.8.0.1', 'private-one', 'external-builder', 'external-one'),
      'two' => wireguard_config('two', '10.8.0.2', 'private-two', 'external-builder', 'external-two')
    )

    Dir.mktmpdir do |directory|
      installer = nil
      Dir.chdir(directory) { installer = FastInstaller.new(config, ssh_executor: executor) }
      capture_io { Dir.chdir(directory) { installer.reconcile } }
    end

    assert_includes executor.reconciled_configs.fetch('one'), '# Peer: external-builder'
    assert_includes executor.reconciled_configs.fetch('one'), 'PresharedKey = external-one'
    assert_includes executor.reconciled_configs.fetch('two'), 'PresharedKey = external-two'
  end

  private

  def wireguard_config(node, address, private_key, peer, psk)
    <<~CONFIG
      # WireGuard configuration for #{node}
      [Interface]
      Address = #{address}/24
      PrivateKey = #{private_key}

      # Peer: #{peer}
      [Peer]
      PublicKey = public-#{peer}
      PresharedKey = #{psk}
      AllowedIPs = 10.8.0.9/32
    CONFIG
  end
end
