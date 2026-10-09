import {spawnSync} from "node:child_process";
const tests = ["publisher.test.mjs","postgres-store.test.mjs","api-handler.test.mjs","trusted-auth.test.mjs","membership-store.test.mjs","jwt-verifier.test.mjs","rotating-jwks.test.mjs","enterprise-pipeline.test.mjs","http-server.test.mjs","request-guard.test.mjs","distributed-guard.test.mjs","readiness.test.mjs","observability.test.mjs","stage-tracer.test.mjs","layout-contract.test.mjs","transition-decision.test.mjs","transition-service.test.mjs","outbox-worker.test.mjs","integration-router.test.mjs","consumer-fanout.test.mjs","integration-registry.test.mjs","integration-management.test.mjs","dispatch-authorization.test.mjs","dispatch-fencing.test.mjs","dispatch-permit-gateway.test.mjs","signed-dispatch-envelope.test.mjs","hardened-transport.test.mjs","secure-egress.test.mjs","dispatch-pipeline.test.mjs","delivery-reliability.test.mjs","delivery-reconciliation.test.mjs","financial-dual-control.test.mjs","postgres-fixture-guard.test.mjs","swift-contract-drift.test.mjs"];
for (const file of tests) {
 console.log("\n=== HALO domain test: " + file + " ===");
 const result = spawnSync(process.execPath, ["--test", file], {
  stdio: "inherit", timeout: 45000, killSignal: "SIGTERM", env: {...process.env, NODE_ENV: "test"}
 });
 if (result.error || result.status !== 0) {
  console.error("HALO domain failure:",file,result.error?.message || result.signal || result.status);
  process.exit(1);
 }
}
console.log("HALO domain suite passed:", tests.length, "files");
