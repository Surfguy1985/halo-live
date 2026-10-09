# Revocation fencing — draft protocol

A registry revision is attached to each proposed send permit. Before sending, the coordinator checks the permit adapter and fetches current registry authorization; mismatched revisions or disabled integration registrations are denied. A revoke hook invalidates outstanding permits.

**Security limitation:** this is not an atomic guarantee of immediate revocation. Permit issuance, reading the registry, and the external network send are separate operations. A revocation can race after the final check; the protocol needs a trusted gateway validating the permit at the true send boundary, with short expiries, durable generation checks and an explicit in-flight delivery policy. No durable permit adapter, credential, API endpoint or network sender is implemented.

The adapters are trusted internal interfaces. Never accept registry or permit implementations from untrusted clients. No live Enforcer/Base44/HALO integration.
