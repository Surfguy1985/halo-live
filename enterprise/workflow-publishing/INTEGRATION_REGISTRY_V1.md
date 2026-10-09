# Integration registration authorization foundation

This draft adds a server-only proposal validator for trusted tenant administrators with integrations:manage, optimistic expectedRevision, action/event allowlists, and explicit disable operations. Migration 011 stores tenant-scoped subscription metadata with FORCE RLS and **no runtime grants**.

It does NOT grant access to live systems, manage secrets, register URLs, issue credentials, write to the registry table, or revoke previously leased messages. Future release requires audited CAS mutation API, tenant membership verification, per-consumer token secret vault, independent revocation checks on every dispatch, durable delivery receipts, signed transport and complete database/CI tests.

Existing HALO, Enforcer, Base44 and Swift remain unchanged.
