require 'rails/generators'

module Messhy
  module Generators
    class InstallGenerator < ::Rails::Generators::Base
      source_root File.expand_path('templates', __dir__)

      def create_config_file
        template 'mesh.yml.erb', 'config/mesh.yml'
        ensure_secrets_gitignored
      end

      def show_instructions
        puts "\n✅ Messhy installed!"
        puts "\n📝 Next steps:"
        puts '  1. Either:'
        puts '     a) Edit config/mesh.yml with your server IPs, OR'
        puts '     b) Use Terraform to auto-generate config/mesh.yml'
        puts '  2. Deploy VPN mesh: rails messhy:setup'
        puts '  3. Check health: rails messhy:health'
        puts "\n📦 WireGuard private keys will be stored in .secrets/wireguard (gitignored)."
        puts '   Copy those YAML files into 1Password or your preferred vault after setup.'
        puts "\n📚 See config/mesh.example.yml in gem for examples"
      end

      private

      def ensure_secrets_gitignored
        gitignore_path = '.gitignore'
        entries = [".secrets/\n", "**/.secrets/\n"]
        header = "\n# Added by messhy - keep WireGuard secrets out of git\n"

        if File.exist?(gitignore_path)
          existing_lines = File.read(gitignore_path).lines.map(&:strip)
          missing_entries = entries.reject { |line| existing_lines.include?(line.strip) }
          return if missing_entries.empty?

          append_to_file gitignore_path do
            header + missing_entries.join
          end
        else
          create_file gitignore_path, header + entries.join
        end
      end
    end
  end
end
