# Staging-only HTTP bootstrap

`staging-bootstrap.mjs` wires the admission gate, signed-JWT verification,
live membership lookup, PostgreSQL publisher, distributed Redis rate limiting,
and dependency readiness into an isolated HTTP server.

It does **not** create database pools, load credentials, fetch JWKS, start a
process, bind a port, or deploy anything when imported or constructed. A
future reviewed deployment must inject separately permissioned identity and
workflow pools, a trusted fixed-issuer JWKS fetcher, Redis, and approved
configuration. It must call `start()` explicitly. Startup fails closed if
PostgreSQL or Redis readiness fails; `start()` binds only to
`127.0.0.1`. The server object is not exposed to callers.

`HALO_WORKFLOW_PORT` is required (0 is reserved for ephemeral test
listeners; use an explicit fixed port in staging). The network edge must
terminate TLS, authenticate and protect the proxy-to-loopback path, and
restrict access to health endpoints. Runtime identity and executor DB
roles, RLS migrations, issuer/JWKS trust, Redis ACLs, secret rotation,
outbound isolation and backup/recovery remain separate release gates.

No production HALO, Base44 endpoint, iOS runtime routing or deployment
configuration is modified by this module.
