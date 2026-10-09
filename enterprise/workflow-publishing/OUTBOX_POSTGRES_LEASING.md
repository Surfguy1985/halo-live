# HALO Outbox PostgreSQL leasing (isolated)

Migration 007 provisions a NOLOGIN, NOBYPASSRLS dedicated worker role and grants access **only** to outbox delivery records; migration 008 introduces lease tokens. Store claims due events with `FOR UPDATE SKIP LOCKED` and atomically increments attempts, writes owner/token/expiry. Completion, retry and dead-letter use token + owner + unexpired lease fencing.

**Security caveat:** a single global outbox role is permitted to read all tenant outbox entries by design. It must be held solely by the trusted integration dispatcher. No end-user/customer access. Consumer-specific routing and durable consumer receipts are not connected yet.

Never run on a production database before restricted credentials, end-to-end authorization, outbox consumer idempotency, tests, and security review. No app, Base44 or Enforcer mutation.
