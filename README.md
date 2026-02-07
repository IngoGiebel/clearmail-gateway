# Clearmail Gateway

A local, self-hosted mail gateway that enables automation agents to read emails and draft outgoing messages **without** granting them direct IMAP/SMTP access. Outbound email is sent **only after explicit human approval** (e.g., via smartphone), and the gateway can be configured to prevent deletion of messages.

This project targets automation scenarios where security and auditability matter: agents should never hold mailbox credentials, should not be able to delete mail, and should not be able to send email without user confirmation.

## Requirements

- OpenJDK 25+
- Kotlin 2.3.10+
- PostgreSQL 15+
- Gradle 8.x (wrapper included)

## Key features

- Read-only access for agents via a local HTTP API (agents never get IMAP credentials)
- Draft/outbox workflow with explicit approval required before sending
- Approval workflow designed for smartphone use (Telegram/Pushover/Web UI plugin)
- Immutable mail archive option (store raw `.eml` + metadata, never delete)
- Audit log of all inbound syncing, draft creation, approvals, and sends
- Supports generic IMAP + SMTP servers (university mail, Gmail/Workspace, Microsoft 365, etc.)

## Architecture

- **Mail fetcher**: connects to IMAP, ingests new messages, stores immutable copies locally
- **Gateway API**: exposes read-only endpoints for messages and a write-only outbox queue
- **Approval service**: notifies the user and collects approve/reject decisions
- **Sender**: sends approved items via SMTP and records results

Agents interact only with the **Gateway API**.

## Security model

- Mailbox credentials exist only on the gateway host (never in agents)
- Agent requests are authenticated (API key or HMAC signature)
- IMAP delete/expunge is never executed by design
- Sending requires a separate approval token produced by the approval service

## Quick start (development)

1. Install the requirements listed above.
2. Copy `application.yml.example` to `~/.clearmail-gateway/config/application.yml` and configure your IMAP/SMTP credentials.
3. Run:
   ```bash
   ./gradlew run
   ```

## Configuration

Configuration is provided via `application.yml` and environment variables.

- IMAP: host, port, TLS, username, secret
- SMTP: host, port, TLS, username, secret
- Storage: archive path, database URL
- Approval: provider config (Telegram/Pushover/Web UI)
- Auth: agent API keys / HMAC secrets
- Policies: retention, immutability, allowed sender identities, recipient allowlists (optional)

## HTTP API (high level)

- `GET /v1/messages` — list ingested messages (read-only)
- `GET /v1/messages/{id}` — message metadata + raw content reference
- `GET /v1/messages/{id}/eml` — raw RFC822 message (optional)
- `POST /v1/outbox` — create a draft send request
- `GET /v1/outbox/{id}` — view status
- `POST /v1/outbox/{id}/approve` — approval callback (used by approval provider)
- `POST /v1/outbox/{id}/reject` — reject callback

## Limitations

- IMAP read-only cannot be reliably enforced by protocol if credentials are shared. This project avoids that by never sharing mailbox credentials with agents.
- “Realtime” approval depends on the chosen approval provider.

## Roadmap

- Optional recipient allowlists and per-agent permissions
- Per-message PGP signing/encryption (outgoing)
- Pluggable classifiers for routing/priority
- Multi-mailbox support

## License

MIT. See `LICENSE`.