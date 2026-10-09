# Dispatch-time authorization and revocation gate

This is a narrow server-side policy gate for **every outbound delivery attempt**. It performs a fresh trusted registry lookup, requires exact tenant/consumer match, enabled registration and subscribed action/event. Disabled or missing registrations fail closed. No network transport is wired.

**Critical concurrency caveat:** a revocation that commits *between* the authorization lookup and the external send may still race with delivery. Strict immediate revocation needs a transaction/lease-fencing protocol or short-lived delivery authorization token validated by the receiving gateway at send time; this PR does **not** guarantee instantaneous cut-off for already-authorized in-flight sends.

Before production, wire to database-backed registry lookups, enforce tenant/session trust, re-check after worker lease, close revoke-vs-send races, propagate cancellations to queued deliveries, audit decisions and pass CI. No Base44, Enforcer, production, or app changes.
