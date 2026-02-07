# Contributing to Clearmail Gateway

Thank you for considering contributing to Clearmail Gateway! This document outlines how to contribute effectively.

## Getting Started

1. Fork the repository
2. Clone your fork locally
3. Set up the development environment (see README.md)
4. Create a feature branch: `git checkout -b feature/your-feature-name`

## Development Setup

```bash
# Clone and enter project
git clone https://github.com/IngoGiebel/clearmail-gateway.git
cd clearmail-gateway

# Copy example config
cp application.yml.example ~/.clearmail-gateway/config/application.yml

# Run tests
./gradlew test

# Run locally
./gradlew run
```

## Code Style

- Follow [Kotlin coding conventions](https://kotlinlang.org/docs/coding-conventions.html)
- Use 4 spaces for indentation (no tabs)
- Maximum line length: 120 characters
- Use meaningful variable and function names
- Prefer immutability (`val` over `var`)
- Use `data class` for DTOs and value objects

### Commit Messages

Use imperative mood in commit messages:

```
# Good
Add approval expiry validation
Fix IMAP connection retry logic
Update README with new API endpoints

# Bad
Added approval expiry validation
Fixing IMAP connection retry logic
Updated README
```

Keep commits atomic and focused on a single change.

## Pull Request Process

1. Ensure all tests pass: `./gradlew test`
2. Run the linter: `./gradlew detekt` (once configured)
3. Update documentation if your change affects public APIs
4. Add tests for new functionality
5. Submit PR against `main` branch
6. Fill out the PR template completely
7. Wait for review — we aim to respond within 48 hours

### PR Checklist

- [ ] Tests pass locally
- [ ] New code has test coverage
- [ ] Documentation updated (if applicable)
- [ ] Commit messages follow conventions
- [ ] No secrets or credentials in code

## Reporting Issues

Use GitHub Issues for bug reports and feature requests.

### Bug Reports

Please include:
- Kotlin version (`kotlin -version`)
- JDK version (`java -version`)
- Operating system
- Steps to reproduce
- Expected vs actual behavior
- Relevant log output (sanitized of credentials)

### Feature Requests

Describe:
- The problem you're trying to solve
- Your proposed solution
- Alternative approaches you've considered

## Security Issues

**Do not report security vulnerabilities through public GitHub issues.**

See [SECURITY.md](SECURITY.md) for responsible disclosure instructions.

## Questions?

- Open a [GitHub Discussion](https://github.com/IngoGiebel/clearmail-gateway/discussions) for general questions
- Check existing issues before opening a new one

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
