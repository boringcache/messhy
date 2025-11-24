# messhy

> WireGuard VPN mesh for secure private networking. Simple, fast, zero-config.

A Ruby gem that sets up a full WireGuard VPN mesh across any VMs. Every node connects directly to every other node, creating a secure private network.

## Why messhy?

### Problems It Solves

❌ **Without messhy:**
- Database replication over public IPs (insecure)
- Complex VPN configurations
- NAT traversal issues
- Manual key management
- Cloud-specific networking (VPC, subnet, security groups)

✅ **With messhy:**
- Secure encrypted connections (WireGuard)
- Automatic key generation and distribution
- Works across any cloud/datacenter
- Zero application changes (just use 10.8.0.x IPs)
- Simple configuration

## Installation

```bash
gem install messhy
```

Or add to your Gemfile:

```ruby
gem 'messhy'
```

## Quick Start

1. **Create config file**:

```yaml
# config/mesh.yml
production:
  network: 10.8.0.0/24
  user: ubuntu
  ssh_key: ~/.ssh/id_rsa
  verify_host_key: true
  
  nodes:
    db-primary:
      host: 34.12.234.81
      private_ip: 10.8.0.10

    db-standby:
      host: 52.23.45.67
      private_ip: 10.8.0.11

    app-1:
      host: 18.156.78.90
      private_ip: 10.8.0.20
```

2. **Setup mesh**:

```bash
messhy setup --environment=production
```

3. **Verify**:

```bash
messhy status
```

## Secret Management

`messhy setup` stores generated WireGuard key pairs inside `.secrets/wireguard/*.yml` with `0600` permissions. Each node gets its own YAML file (`.secrets/wireguard/<node>.yml`) and all peer pre‑shared keys live in `.secrets/wireguard/psks.yml`. The directory is gitignored by default, and the Rails generator ensures the ignore rules are present in your application. After provisioning, copy the YAML files into 1Password (or another vault) and remove them from disk if you do not want long‑lived local copies.

If you want to pre-generate keys before rolling out configs, run:

```bash
messhy keygen --environment=production
```

## Trusting SSH Host Keys

Before running `messhy setup`, fetch each server's SSH fingerprint and add it to your local `known_hosts` file:

```bash
# Adds Ed25519/ECDSA/RSA host keys for every node defined in config/mesh.yml
bundle exec messhy trust-hosts --environment=production
```

If a server rotated keys or you resized an instance, clear the old entry as part of the same command:

```bash
bundle exec messhy trust-hosts --environment=production --force
```

This command uses `ssh-keyscan` under the hood and skips entries that already exist. If a host cannot be scanned (firewall / DNS issue), it will be listed at the end so you can add it manually. You can also call the Rails task `rails messhy:trust_hosts`.

## Rails Integration

1. Add the gem to your Rails application and run `bundle install`.
2. Generate the config stub and gitignore entries:

   ```bash
   rails generate messhy:install
   ```

3. Use the provided rake tasks from your app (they automatically use `RAILS_ENV`/`MESSHY_ENVIRONMENT`):

   ```bash
   rails messhy:trust_hosts   # ssh-keyscan every node
   rails messhy:setup         # deploy WireGuard configs
   rails messhy:status        # show current mesh status
   rails messhy:keygen        # pre-generate keys only
   ```

This keeps Rails + SSHKit conventions intact: tasks shell out to the Thor CLI, SSH host key verification is enforced by default, and WireGuard secrets stay outside of Git.

## CLI Commands

### Setup

```bash
# Initial setup (all nodes)
messhy setup
messhy setup --environment=production

# Setup with options
messhy setup --dry-run                    # Show what would be done
messhy setup --skip-node=app-1            # Skip specific node
messhy setup --only-node=db-primary       # Setup single node
```

### Status & Monitoring

```bash
# Show all connections
messhy status

# Ping specific node
messhy ping app-1
messhy ping 10.8.0.20

# Test connectivity
messhy test-connectivity

# Show traffic statistics
messhy stats
messhy stats --node=db-primary
```

### Key & Access Management

```bash
# Generate WireGuard keys without touching configs
messhy keygen --environment=production
messhy keygen --skip-node=app-1

# Trust SSH host keys (uses ssh-keyscan)
messhy trust-hosts
messhy trust-hosts --force        # replace existing entries
messhy trust-hosts --known-hosts=/tmp/known_hosts
```

### Info

```bash
# List all nodes
messhy list

# Show node details
messhy show db-primary
```

## Configuration

See `config/mesh.example.yml` for a complete example.

### Basic Options

- `network`: CIDR network for VPN (default: `10.8.0.0/24`)
- `user`: SSH user (default: `ubuntu`)
- `ssh_key`: Path to SSH private key
- `mtu`: MTU size (default: `1280` for reliability)
- `listen_port`: WireGuard port (default: `51820`)
- `keepalive`: Keepalive interval in seconds (default: `25`)

### Node Configuration

Each node requires:
- `host`: Public IP or hostname
- `private_ip`: Private VPN IP (must be within network range)

Optional per-node overrides:
- `ssh_user` / `ssh_port`: Override SSH access details (defaults to top-level `user` and port 22)
- `ssh_key`: Override SSH key for a specific node
- `listen_port`: WireGuard UDP port (defaults to top-level `listen_port`)
- `region`: Documentation / metadata field

## Firewall Requirements

Only one port needs to be opened on each node:

```bash
# UFW
ufw allow 51820/udp

# iptables
iptables -A INPUT -p udp --dport 51820 -j ACCEPT
```

## Architecture

### Full Mesh Topology

```
         Node A
        /   |   \
       /    |    \
      /     |     \
   Node B - + - Node C
      \     |     /
       \    |    /
        \   |   /
         Node D
```

**Every node connects directly to every other node:**
- No central point of failure
- Optimal routing (direct connections)
- Scales to ~50 nodes

## Performance

### Benchmarks (compared to no VPN)

| Metric | No VPN | WireGuard | Overhead |
|--------|--------|-----------|----------|
| Throughput | 1000 Mbps | 950 Mbps | 5% |
| Latency | 10ms | 10.5ms | +0.5ms |
| CPU usage | 2% | 3% | +1% |

**WireGuard is FAST!** Negligible overhead for most workloads.

## Troubleshooting

### Node can't connect

```bash
# Check WireGuard is running
systemctl status wg-quick@wg0

# Check interface
wg show wg0

# Check firewall
ufw status | grep 51820

# Test connectivity
ping 10.8.0.x

# Check logs
journalctl -u wg-quick@wg0 -f
```

### High latency

```bash
# Try lower MTU (in mesh.yml)
mtu: 1280  # instead of 1420

# Redeploy
messhy setup
```

## Requirements

- Ruby 3.0+
- WireGuard tools (`wg` command)
- Target servers with Linux kernel 5.6+ (WireGuard built-in)
- SSH key-based authentication

## Contributing

Bug reports and pull requests are welcome on GitHub.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

---

Built with ❤️ for the Rails community by [Gaurav](https://github.com/yourusername)
