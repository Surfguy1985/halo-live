# HALO Financial Retry Approval Store — Draft

This PostgreSQL transaction adapter records a single two-person financial retry approval against a locked, still-uncertain delivery revision. The unique key prevents two successful approval records for the same delivery revision; the original queue remains quarantined. No resend or money movement is performed.

**Important security boundary:** the service currently accepts objects representing authenticated actors and verified receipts. These claims are not independently authenticated in this code. Production MUST construct them from trusted identity and external receipt verification services, not HTTP request bodies, and should re-check these authoritative identities and evidence within the transactional boundary. The read uses FOR SHARE to coordinate with reconciliation updates. The global role must be accessible only to a trusted internal backend. CI, migrations, database concurrency, financial audit, evidence freshness, approval expiry and consumption all require review before deployment.

No integration or production changes are made.
