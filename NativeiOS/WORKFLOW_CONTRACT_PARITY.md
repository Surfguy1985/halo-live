# Swift workflow layout contract parity v1

This draft-only implementation mirrors the server-owned block configuration allowances from the isolated backend proposal `feature/workflow-layout-contract-v1` (PR #6). Both support the same eight kinds, 100-block maximum, slug IDs, bounded visible roles and per-kind string-valued configurations.

The Swift parser uses Codable and does not currently reject unexpected JSON object properties, unlike the strict Node backend contract. This intentional difference must be closed before allowing downloads from untrusted servers to be treated as validated schema. Both remain non-authoritative preview code.

No publishing is wired into the editor. No Base44, Enforcer, production system or main branch is changed. Before promotion, run Xcode simulator XCTest, server contract tests, and shared fixture-based parity checks, then reconcile independent PR branches.
