# Hardened transport boundary (draft)

This adapter **does not perform network operations by itself**. It requires an injected hardened egress connector that must independently verify DNS results/public IP range, pin DNS through connection, validate TLS, disallow redirects and proxy bypass, respect body/read/connection timeouts, and enforce a streamed response-byte maximum. A boolean connector marker is NOT a security attestation: production must inject only reviewed, trusted adapter instances.

The transport wrapper rejects malformed envelopes, caps message and response size, requires no redirects, classifies HTTP failures and has no default network fallback.

Still needed: genuine hardened egress implementation, rate limiting, credential vault, signing-key lifecycle, auth+permit synchronization, receiver dedupe, response drain control, observability and independent red-team review. No outbound requests, Enforcer or Base44 changes are activated.
