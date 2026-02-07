# Clearmail Gateway software requirements specification

## Project goal

Provide a local gateway service that:

1. Ingests inbound email from a mailbox via IMAP.
2. Exposes a **read-only** interface to automation agents.
3. Accepts outbound drafts from agents into an outbox.
4. Sends outbound email **only after explicit user approval** performed on a smartphone.
5. Prevents agents from deleting or modifying mailbox content.

## Deployment concept

- Development root: `~/dev/clearmail-gateway` (project source code, public).
- Instance root: `~/.clearmail-gateway` (private instance data, not in git).
  - `/config`: Active `application.yml` and secrets.
  - `/archive`: Local file storage for immutable `.eml` files and optional extracted attachments.
  - `/logs`: Exportable logs (optional; may also be shipped to stdout/journald).

## Threat model and assumptions

### Threats addressed

- An agent exfiltrates or misuses mailbox credentials.
- An agent sends emails without user consent.
- An agent deletes or alters messages (covering tracks or causing loss).
- An agent spams recipients or sends to unintended addresses.

### Assumptions

- The gateway host is controlled by the user (Ubuntu machine or server).
- The user can receive approval prompts on a smartphone.
- The mailbox provider supports standard IMAP/SMTP (or OAuth-based variants where needed).

## Non-goals

- Providing a general-purpose webmail client.
- Enterprise-grade MTA replacement.
- Enforcing read-only semantics through IMAP alone (the protocol cannot guarantee this if credentials are shared).

## Core requirements

### Inbound ingestion

- Connect to IMAP with TLS.
- Poll every 60–300 seconds; optionally use IMAP IDLE where supported.
- Use a hybrid storage strategy:
  - Store parsed metadata, indexing fields, and ingestion state in PostgreSQL.
  - Store immutable raw `.eml` (RFC 822) in the instance archive directory.
  - Optionally store extracted attachments as files in the instance archive directory.
- Do not delete, expunge, or move messages on the server.
- The IMAP fetcher must use PEEK variants to avoid setting `\Seen` and must not issue IMAP `STORE`, `COPY`, `MOVE`, or `EXPUNGE` commands.
- Track ingestion state per folder using IMAP `UIDVALIDITY` and UID ranges (and/or `UIDNEXT`).

### Read-only agent access

- Expose a local HTTP API for agents.
- Agents can list messages and fetch message details, raw `.eml`, and derived representations.
- Provide a content transformation endpoint that serves a stripped representation of an email (HTML-to-plain-text and/or Markdown conversion) to minimize token usage for AI agents.
  - The stripped representation must remove scripts, tracking pixels, and remote resources.
  - The output should be deterministic for the same input message.
  - Inline content and attachments must be represented using stable placeholders and references.
- Agents cannot mutate inbound content, flags, folders, or server state.
- Folder scope is configurable; by default, all folders are ingested. Each folder maintains its own UID state.

### Outbox and approval

- Agents submit an outbox request containing:
  - From identity (must match configured allowed identities).
  - Recipients (`to`/`cc`/`bcc`).
  - Subject and body (plain text required; HTML optional).
  - Attachments (optional).
  - Optional references to inbound message IDs for reply/forward.
  - Optional template ID. Templates provide predefined structures to ensure message compliance (for example, official EODHD requests).
- Outbox items start in `pending_approval`.
- The approval provider notifies the user and collects an explicit approval decision:
  - Approve → status becomes `approved` and sending begins.
  - Reject → status becomes `rejected` and nothing is sent.
- Approval must be bound to:
  - An expiry time window (default: 15 minutes).
  - A canonical content hash of the outgoing message, including headers, recipients, body, and attachment digests.
- Canonicalization rules must ensure that approval is invalidated if any field changes (including template expansion results).
- After approval, the sender sends via SMTP and records the delivery result:
  - `sent` or `failed` with a reason and a retry policy.

### Audit logging

- Record all actions with timestamps and correlation IDs, including:
  - Ingestion events.
  - Agent API requests (agent identity, endpoint, and request metadata).
  - Outbox creation and updates.
  - Approvals and rejections (including approver identity where available).
  - Send attempts and results.
- Logs must be exportable.

## Policies and controls

- Recipient allowlist/denylist (optional, recommended).
- Maximum recipients per send request.
- Rate limiting for reads and outbox creation per agent (defaults: 100 requests/minute for reads, 10 outbox requests/hour).
- Attachment size limits (default: 25 MB per attachment, 50 MB total per request).
- Domain restrictions (optional).
- Agents must not be able to delete emails. The gateway must never remove server mail and must only append to the local archive.

## Components

### Service layout

A single Kotlin monorepo with two runnable applications:

1. `gateway-api`
   - Ktor-based HTTP server (preferred for lightweight deployment).
   - Authentication, message browsing endpoints, and outbox endpoints.
   - Reads and writes PostgreSQL and the filesystem archive.

2. `mail-worker`
   - IMAP ingestion loop.
   - SMTP send loop for approved outbox items.
   - Approval provider integration.

## Storage

- Database: PostgreSQL (metadata, ingestion state, audit logs, extracted text bodies, templates).
- Blob storage: local filesystem (`~/.clearmail-gateway/archive/`) for immutable raw RFC 822 `.eml` files and optional extracted attachments.
- The `.eml` file is the source of truth. PostgreSQL stores normalized and searchable representations and references to archive paths.
- Minimum database tables:
  - `inbound_messages` (links metadata to local archive paths).
  - `inbound_message_headers`.
  - `folder_state` (per-folder `UIDVALIDITY`, UID tracking, and ingestion checkpoints).
  - `outbox_requests`.
  - `outbox_events` (audit trail).
  - `agents` (keys and permissions).
  - `approvals` (token, expiry, canonical hash, and approver identity where available).
  - `message_templates` (predefined outbound structures).

## API authentication

- Agent authentication via:
  - An API key per agent (simplest), or
  - An HMAC signature per request (stronger against replay and tampering).
- All endpoints are served over localhost or a private network. TLS is optional but recommended if remote access is enabled.

## Approval provider interface

A pluggable interface:

- `notify(outboxId, summary, approveUrl, rejectUrl)`
- `verifyCallback(request)` returning `approved` or `rejected` with user identity

Initial implementation options:

- Telegram bot buttons (fast UX).
- Pushover (simple push plus approve link).
- A minimal web UI protected by passkeys or TOTP.

## Configuration

- Public repository: contains `application.yml.example` with dummy values.
- Private instance: the real `application.yml` resides in `~/.clearmail-gateway/config/`.
- `application.yml` includes:
  - IMAP/SMTP connection info.
  - Credential sources (environment variables, system keyring, or local secret files).
  - Polling intervals and folder scope.
  - Storage paths.
  - Agent authentication keys and secrets.
  - Approval provider settings.
  - Policy knobs (limits, allowlists, restrictions).

## Canonicalization and content hash

This project binds approvals to a canonical representation of an outbox request. The canonical form must be deterministic and stable across runs, hosts, and library versions.

### Canonical content object

For every outbox request, the gateway must build a `CanonicalOutboxContent` object with the following JSON shape:

```json
{
  "version": 1,
  "from": {
    "address": "sender@example.edu",
    "display_name": "Sender Name"
  },
  "recipients": {
    "to":  [{"address": "a@example.com", "display_name": "A"}],
    "cc":  [{"address": "c@example.com", "display_name": "C"}],
    "bcc": [{"address": "b@example.com", "display_name": "B"}]
  },
  "subject": "Subject line",
  "body": {
    "content_type": "text/plain",
    "charset": "utf-8",
    "content": "Plain text body with normalized line endings\n"
  },
  "html_body": {
    "content_type": "text/html",
    "charset": "utf-8",
    "content": "<p>Optional HTML body</p>"
  },
  "attachments": [
    {
      "filename": "file.pdf",
      "content_type": "application/pdf",
      "content_disposition": "attachment",
      "size_bytes": 12345,
      "sha256": "hex-encoded-sha256-of-raw-bytes"
    }
  ],
  "reply_to": [{"address": "replyto@example.com", "display_name": ""}],
  "in_reply_to_message_id": "<original@example.com>",
  "references": ["<msg1@example.com>", "<msg2@example.com>"],
  "source_message_refs": ["inbound:uuid-1", "inbound:uuid-2"],
  "policy": {
    "allowed_sender_id": "primary-student-account",
    "recipient_restrictions_applied": true
  },
  "template": {
    "template_id": "eodhd-academic-request",
    "template_version": 3,
    "expanded": true
  }
}
```

Notes:

- `html_body` is omitted if not present.
- `attachments` is an empty array if none are present.
- `reply_to`, `references`, and `source_message_refs` are omitted if empty.
- `template` is omitted if no template was used.

### Normalization rules

1. **JSON serialization**
   - Serialize the canonical object using **RFC 8785 JSON Canonicalization Scheme (JCS)**.
   - Required properties:
     - UTF-8 encoding.
     - Object keys sorted lexicographically by Unicode code point.
     - No insignificant whitespace.
     - Use JSON numbers only where defined above (avoid floats; `size_bytes` must be an integer).
2. **Email addresses**
   - Normalize `address` to lowercase.
   - Strip surrounding whitespace.
   - Reject invalid addresses prior to canonicalization.
3. **Display names**
   - Trim leading/trailing whitespace.
   - Collapse internal runs of whitespace to a single space.
   - Preserve case.
4. **Recipients ordering**
   - Sort each recipient list (`to`, `cc`, `bcc`, `reply_to`) by:
     1. normalized `address` ascending,
     2. normalized `display_name` ascending.
   - Remove exact duplicates after normalization.
5. **Subject**
   - Trim leading/trailing whitespace.
   - Collapse internal runs of whitespace to a single space.
   - Preserve case.
6. **Body normalization**
   - Convert all line endings to `\n`.
   - Ensure the `content` ends with a single trailing newline (`\n`).
   - If the user supplied `\r\n`, normalize to `\n`.
   - `charset` must be `utf-8`.
7. **HTML body normalization (if present)**
   - Preserve the exact user-supplied HTML string except for line-ending normalization to `\n`.
   - Do not minify, reformat, or sanitize for the purpose of hashing.
   - Any sanitization performed for sending must happen **before** canonicalization, and the sanitized HTML must be hashed.
8. **Attachments**
   - `sha256` is computed over the raw attachment bytes exactly as they will be transmitted.
   - `filename` must be normalized by:
     - trimming outer whitespace,
     - replacing path separators (`/` and `\`) with `_`.
   - `size_bytes` must match the byte length used for `sha256`.
   - Sort attachments by:
     1. normalized `filename` ascending,
     2. `sha256` ascending.
9. **Message-ID fields**
   - `in_reply_to_message_id` and `references` must preserve angle brackets if present.
   - Trim surrounding whitespace.
   - `references` list must be de-duplicated and sorted lexicographically.
10. **Template expansion**
    - Template expansion must complete **before** canonicalization.
    - The canonical object must set `"expanded": true` when a template was used.
    - If templates are versioned, include `template_version`.
    - Any template variables must not be stored in canonical form; only the expanded output is hashed.
11. **Policy binding**
    - Include the effective sender identity and whether recipient restrictions were applied.
    - If recipient allowlists/denylists affect the final recipients, the canonical object must reflect the post-policy recipient lists.

### Content hash definition

- Let `C` be the JCS-canonical UTF-8 JSON bytes of `CanonicalOutboxContent`.
- Define `content_hash = SHA-256(C)` as a 64-character lowercase hex string.

### Approval binding and verification

- Approvals must store:
  - `content_hash`,
  - an expiry timestamp,
  - an approval token (opaque),
  - and approver identity where available.
- When processing an approval callback, the gateway must:
  1. rebuild `CanonicalOutboxContent` from the stored outbox request,
  2. compute `content_hash`,
  3. verify it matches the stored `content_hash`,
  4. verify the approval token and expiry,
  5. only then transition the outbox item to `approved`.

If any verification step fails, the outbox item must remain unsent.

## Practical implementation note (Kotlin)

- Use a JCS implementation (or implement minimal JCS: key sorting + deterministic JSON serialization) and lock it down with tests.
- Add golden test vectors: a few outbox requests with expected canonical JSON and expected SHA-256.

## License and publishing

- The repository includes:
  - `LICENSE`
  - `CODE_OF_CONDUCT.md`
  - `SECURITY.md`
  - `CONTRIBUTING.md`