require 'test_helper'
require 'tempfile'

class SSHExecutorTest < Minitest::Test
  def test_target_can_connect_through_a_declared_jump_host
    ssh_key = File::NULL
    config_hash = {
      'test' => {
        'user' => 'ubuntu',
        'ssh_key' => ssh_key,
        'verify_host_key' => 'accept_new',
        'nodes' => {
          'jump' => { 'host' => '1.2.3.4', 'mesh_ip' => '10.8.0.1' },
          'target' => { 'host' => '5.6.7.8', 'mesh_ip' => '10.8.0.2', 'jump_host' => 'jump' }
        }
      }
    }
    config = Messhy::Configuration.new(config_hash, 'test')
    executor = Messhy::SSHExecutor.new(config)

    host = executor.send(:host_for, 'target', config.node_config('target'))
    proxy = host.ssh_options.fetch(:proxy)

    assert_instance_of Net::SSH::Proxy::Command, proxy
    assert_includes proxy.command_line_template, 'ssh -F /dev/null'
    assert_includes proxy.command_line_template, '-o BatchMode\\=yes'
    assert_includes proxy.command_line_template, '-o ForwardAgent\\=no'
    assert_includes proxy.command_line_template, '-o StrictHostKeyChecking\\=accept-new'
    assert_includes proxy.command_line_template, "-i #{ssh_key}"
    assert_includes proxy.command_line_template, '-o IdentitiesOnly\\=yes'
    assert_includes proxy.command_line_template, '-W %h:%p ubuntu@1.2.3.4'
  end

  def test_direct_node_does_not_receive_a_proxy
    config_hash = {
      'test' => {
        'nodes' => {
          'direct' => { 'host' => '1.2.3.4', 'mesh_ip' => '10.8.0.1' }
        }
      }
    }
    config = Messhy::Configuration.new(config_hash, 'test')
    executor = Messhy::SSHExecutor.new(config)

    host = executor.send(:host_for, 'direct', config.node_config('direct'))

    refute host.ssh_options&.key?(:proxy)
  end

  def test_known_hosts_file_is_used_by_direct_and_jump_connections
    Tempfile.create('known-hosts') do |known_hosts|
      config_hash = {
        'test' => {
          'ssh_known_hosts_file' => known_hosts.path,
          'nodes' => {
            'jump' => { 'host' => '1.2.3.4', 'mesh_ip' => '10.8.0.1' },
            'target' => { 'host' => '5.6.7.8', 'mesh_ip' => '10.8.0.2', 'jump_host' => 'jump' }
          }
        }
      }
      config = Messhy::Configuration.new(config_hash, 'test')
      executor = Messhy::SSHExecutor.new(config)

      options = executor.send(:build_ssh_options)
      host = executor.send(:host_for, 'target', config.node_config('target'))

      assert_equal [known_hosts.path], options.fetch(:user_known_hosts_file)
      assert_equal [known_hosts.path], host.ssh_options.fetch(:user_known_hosts_file)
      assert_equal :always, host.ssh_options.fetch(:verify_host_key)
      assert_includes host.ssh_options.fetch(:proxy).command_line_template,
                      "UserKnownHostsFile\\=#{known_hosts.path}"
    end
  end

  def test_reconcile_script_syncs_active_interfaces_and_rolls_back_on_failure
    config = Messhy::Configuration.new({ 'test' => { 'nodes' => {} } }, 'test')
    script = Messhy::SSHExecutor.new(config).send(:reconcile_script, '/tmp/candidate')

    assert_includes script, 'wg syncconf wg0 "$stripped"'
    assert_includes script, 'candidate=/etc/wireguard/wg0.next.conf'
    assert_includes script, 'cp -p "$previous" "$target"'
    assert_includes script, 'systemctl start wg-quick@wg0'
    refute_includes script, 'systemctl restart wg-quick@wg0'
  end
end
