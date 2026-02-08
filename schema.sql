-- ============================================================
-- Clearmail Gateway - Database Schema
-- Version: 1.0
-- Based on SRS v1
-- ============================================================

-- ============================================================
-- Agents: API access control
-- ============================================================
CREATE TABLE agents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE,
    api_key_hash TEXT NOT NULL,
    permissions JSONB DEFAULT '{"read": true, "outbox": true}'::jsonb,
    rate_limit_reads_per_min INT DEFAULT 100,
    rate_limit_outbox_per_hour INT DEFAULT 10,
    enabled BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- Folder state: IMAP sync tracking per folder
-- ============================================================
CREATE TABLE folder_state (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    folder_name TEXT NOT NULL UNIQUE,
    uid_validity BIGINT,
    last_seen_uid BIGINT DEFAULT 0,
    uid_next BIGINT,
    last_sync_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- Inbound messages: metadata + archive reference
-- ============================================================
CREATE TABLE inbound_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id TEXT UNIQUE NOT NULL,          -- RFC 822 Message-ID
    folder_name TEXT NOT NULL,
    uid BIGINT NOT NULL,
    sender TEXT NOT NULL,
    sender_name TEXT,
    subject TEXT,
    received_at TIMESTAMPTZ NOT NULL,
    date_header TIMESTAMPTZ,
    archive_path TEXT NOT NULL,               -- Path to .eml in archive
    size_bytes BIGINT,
    has_attachments BOOLEAN DEFAULT FALSE,
    body_text TEXT,                           -- Extracted plain text (for search)
    body_html TEXT,                           -- Extracted HTML (optional)
    ingested_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(folder_name, uid)
);

-- ============================================================
-- Inbound message headers: parsed headers for search/filter
-- ============================================================
CREATE TABLE inbound_message_headers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id UUID NOT NULL REFERENCES inbound_messages(id) ON DELETE CASCADE,
    header_name TEXT NOT NULL,
    header_value TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_headers_message_id ON inbound_message_headers(message_id);
CREATE INDEX idx_headers_name ON inbound_message_headers(header_name);

-- ============================================================
-- Message templates: predefined outbound structures
-- ============================================================
CREATE TABLE message_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    template_id TEXT NOT NULL UNIQUE,         -- e.g., "eodhd-academic-request"
    version INT DEFAULT 1,
    name TEXT NOT NULL,
    description TEXT,
    subject_template TEXT,
    body_template TEXT NOT NULL,
    variables JSONB DEFAULT '[]'::jsonb,      -- List of required variables
    enabled BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- Outbox requests: pending outbound emails
-- ============================================================
CREATE TABLE outbox_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    agent_id UUID REFERENCES agents(id),
    from_address TEXT NOT NULL,
    from_name TEXT,
    recipients_to JSONB NOT NULL DEFAULT '[]'::jsonb,
    recipients_cc JSONB DEFAULT '[]'::jsonb,
    recipients_bcc JSONB DEFAULT '[]'::jsonb,
    subject TEXT NOT NULL,
    body_text TEXT NOT NULL,
    body_html TEXT,
    attachments JSONB DEFAULT '[]'::jsonb,    -- [{filename, path, content_type, size_bytes, sha256}]
    reply_to_message_id UUID REFERENCES inbound_messages(id),
    template_id TEXT REFERENCES message_templates(template_id),
    template_version INT,
    canonical_hash TEXT,                      -- SHA-256 of canonical content
    status TEXT DEFAULT 'pending_approval',   -- pending_approval, approved, rejected, sending, sent, failed
    status_reason TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_outbox_status ON outbox_requests(status);

-- ============================================================
-- Approvals: HITL approval tokens
-- ============================================================
CREATE TABLE approvals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    outbox_id UUID NOT NULL REFERENCES outbox_requests(id) ON DELETE CASCADE,
    token TEXT NOT NULL UNIQUE,
    canonical_hash TEXT NOT NULL,             -- Must match outbox at approval time
    expires_at TIMESTAMPTZ NOT NULL,
    approved_at TIMESTAMPTZ,
    rejected_at TIMESTAMPTZ,
    approver_identity TEXT,                   -- e.g., telegram user id
    created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_approvals_token ON approvals(token);
CREATE INDEX idx_approvals_outbox ON approvals(outbox_id);

-- ============================================================
-- Outbox events: audit trail for outbox lifecycle
-- ============================================================
CREATE TABLE outbox_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    outbox_id UUID NOT NULL REFERENCES outbox_requests(id) ON DELETE CASCADE,
    event_type TEXT NOT NULL,                 -- created, approval_requested, approved, rejected, sending, sent, failed
    event_data JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_outbox_events_outbox ON outbox_events(outbox_id);
CREATE INDEX idx_outbox_events_type ON outbox_events(event_type);

-- ============================================================
-- Audit log: general audit trail
-- ============================================================
CREATE TABLE audit_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    agent_id UUID REFERENCES agents(id),
    action TEXT NOT NULL,                     -- api_request, imap_sync, smtp_send, etc.
    resource_type TEXT,                       -- message, outbox, folder, etc.
    resource_id UUID,
    request_metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_audit_created ON audit_log(created_at);
CREATE INDEX idx_audit_agent ON audit_log(agent_id);

-- ============================================================
-- Helper function: auto-update updated_at timestamp
-- ============================================================
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply trigger to relevant tables
CREATE TRIGGER tr_agents_updated BEFORE UPDATE ON agents
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER tr_folder_state_updated BEFORE UPDATE ON folder_state
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER tr_templates_updated BEFORE UPDATE ON message_templates
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER tr_outbox_updated BEFORE UPDATE ON outbox_requests
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
