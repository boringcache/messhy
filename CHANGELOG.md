# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2025-01-21

### Added
- Initial release of Messhy
- Full WireGuard VPN mesh network setup across any VMs
- Every node connects directly to every other node (full mesh topology)
- Automated WireGuard installation and configuration
- Dynamic key generation and distribution
- Automatic peer configuration across all nodes
- Rails integration with generators and rake tasks
- Standalone Ruby support (no Rails dependency required)
- SSH-based deployment (no Python, Ansible, or Kubernetes)
- Health checking and status monitoring
- WireGuard status parsing and connection verification
- Host trust management for SSH connections
- Support for both public and private IP addresses
- YAML-based configuration with ERB support
- Secret management via environment variables or command execution

### Technical Details
- Uses SSHKit for SSH operations
- Thor-based CLI interface with `messhy` command
- Automatic IP allocation for VPN network (10.8.0.0/24 by default)
- UDP port configuration (default: 51820)
- Compatible with Ubuntu 20.04+ servers (Debian-based distributions)
- Ruby >= 3.4.0 required

### Commands
- `messhy setup` - Deploy WireGuard mesh network
- `messhy status` - Check mesh network health and connectivity
- `messhy add_node` - Add new node to existing mesh
- `messhy remove_node` - Remove node from mesh

## [Unreleased]

### Planned
- Support for custom IP ranges and subnets
- Multi-region mesh optimization
- Traffic routing policies
- Network performance monitoring
- Automatic failover for unreachable nodes
- Integration with cloud provider APIs
