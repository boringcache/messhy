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
