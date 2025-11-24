# Contributing to Messhy

Thank you for your interest in contributing to Messhy! We welcome contributions from the community.

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/YOUR_USERNAME/messhy.git`
3. Create a feature branch: `git checkout -b my-new-feature`
4. Make your changes
5. Run tests: `bundle exec rake test`
6. Commit your changes: `git commit -am 'Add new feature'`
7. Push to the branch: `git push origin my-new-feature`
8. Create a Pull Request

## Development Setup

```bash
# Install dependencies
bundle install

# Run tests
bundle exec rake test

# Run rubocop
bundle exec rubocop

# Test CLI locally
bundle exec exe/messhy version
```

## Testing with WireGuard

Messhy requires WireGuard for testing. Set up a local test environment:

```bash
# Ensure WireGuard is installed
wg version

# Run tests
bundle exec rake test
```

## Code Style

- Follow the Ruby Style Guide
- Run `rubocop` before committing
- Write tests for new features
- Keep commits atomic and well-described

## Testing

- All new features should include tests
- Test WireGuard connectivity when possible
- Run the full test suite before submitting PR
- Ensure all tests pass

## Pull Request Guidelines

- Keep PRs focused on a single feature or fix
- Include tests for new functionality
- Update CHANGELOG.md with your changes
- Update documentation as needed
- Ensure CI passes

## Reporting Issues

- Use GitHub Issues to report bugs
- Include WireGuard version
- Include network topology details
- Include steps to reproduce
- Include your Ruby version and OS
- Include relevant error messages and logs

## Code of Conduct

- Be respectful and inclusive
- Welcome newcomers
- Focus on constructive feedback
- Help others learn and grow

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
