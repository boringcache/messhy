require 'test_helper'
require 'tempfile'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'json'

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

  def test_reconcile_private_key_file_is_private_and_removed_after_success_or_rollback
    [false, true].each do |fail_sync|
      Dir.mktmpdir('mesh-permissions') do |directory|
        FileUtils.mkdir_p("#{directory}/wireguard")
        File.write("#{directory}/wireguard/wg0.conf", "previous configuration\n")
        source = "#{directory}/upload"
        File.write(source, "PrivateKey = test-fixture-only\n")
        stub_reconcile_commands(directory)
        config = Messhy::Configuration.new({ 'test' => { 'nodes' => {} } }, 'test')
        script = Messhy::SSHExecutor.new(config).send(:reconcile_script, source)
        script = script.gsub('/etc/wireguard', "#{directory}/wireguard")
                       .gsub('/tmp/messhy-wg0', "#{directory}/stripped")
        observations = "#{directory}/observations"
        output, status = Open3.capture2e({
                                           'PATH' => "#{directory}:#{ENV.fetch('PATH')}",
                                           'MESH_TEST_RUBY' => RbConfig.ruby, 'MESH_TEST_OBSERVATIONS' => observations,
                                           'MESH_TEST_FAIL' => fail_sync.to_s
                                         }, 'bash', '-c', "umask 022\n#{script}")
        assert_equal !fail_sync, status.success?, output
        rows = File.readlines(observations).map { |line| JSON.parse(line) }
        assert_equal(fail_sync ? 2 : 1, rows.size)
        rows.each do |row|
          assert_equal 0o600, row.fetch('mode')
          refute_path_exists row.fetch('path')
        end
        expected = fail_sync ? "previous configuration\n" : "PrivateKey = test-fixture-only\n"
        assert_equal expected, File.read("#{directory}/wireguard/wg0.conf")
      end
    end
  end

  def test_reconcile_upload_is_private_and_removed_when_remote_apply_fails
    backend = FailingReconcileBackend.new
    config = Messhy::Configuration.new({ 'test' => { 'nodes' => {} } }, 'test')
    executor = Messhy::SSHExecutor.new(config)
    executor.define_singleton_method(:execute_on_node) { |_node, &block| backend.instance_eval(&block) }

    error = assert_raises(RuntimeError) { executor.reconcile_config('fixture', 'private fixture') }
    assert_equal 'remote apply failed', error.message
    assert_equal 1, backend.uploaded.size
    assert_equal 0o700, backend.uploaded.first.fetch(:directory_mode)
    refute_path_exists backend.uploaded.first.fetch(:path)
    backend.directories.each { |path| refute_path_exists path }
  ensure
    backend&.directories&.each { |path| FileUtils.remove_entry(path) if File.directory?(path) }
  end

  private

  def stub_reconcile_commands(directory)
    programs = {
      'install' => "#!/bin/sh\nshift 4\nexec /usr/bin/install \"$@\"\n",
      'wg-quick' => "#!/bin/sh\ncat \"$2\"\n",
      'systemctl' => "#!/bin/sh\nexit 0\n",
      'wg' => <<~SH
        #!/bin/sh
        exec "$MESH_TEST_RUBY" -rjson -e '
          observations = ENV.fetch("MESH_TEST_OBSERVATIONS")
          first = !File.exist?(observations)
          File.open(observations, "a") do |file|
            file.puts JSON.generate(path: ARGV[2], mode: File.stat(ARGV[2]).mode & 0777)
          end
          exit(ENV["MESH_TEST_FAIL"] == "true" && first ? 1 : 0)
        ' "$@"
      SH
    }
    programs.each do |name, content|
      File.write("#{directory}/#{name}", content)
      File.chmod(0o755, "#{directory}/#{name}")
    end
  end

  class FailingReconcileBackend
    attr_reader :directories, :uploaded

    def initialize
      @directories = []
      @uploaded = []
    end

    def capture(*arguments)
      path, status = Open3.capture2(*arguments.map(&:to_s))
      raise 'mktemp failed' unless status.success?

      directories << path.strip
      path
    end

    def upload!(input, path)
      uploaded << { path: path, directory_mode: File.stat(File.dirname(path)).mode & 0o777 }
      File.write(path, input.read)
    end

    def execute(*arguments)
      raise 'remote apply failed' if arguments.first == :sudo

      _output, status = Open3.capture2e(*arguments.map(&:to_s))
      raise 'cleanup failed' unless status.success?
    end
  end
end
