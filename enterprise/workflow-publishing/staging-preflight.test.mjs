import test from "node:test";
import assert from "node:assert/strict";
import {validateLocalStagingConfig} from "./staging-preflight.mjs";
const valid=()=>({enabled:true,databaseURL:"postgresql://localhost/halo_test_workflow",
 issuer:"https://id.example.test",audience:"halo-test-api",port:0});
test("local staging requires explicit opt-in",()=>{
 assert.throws(()=>validateLocalStagingConfig({...valid(),enabled:false}),/LOCAL_STAGING_DISABLED/);
 assert.throws(()=>validateLocalStagingConfig(),/LOCAL_STAGING_DISABLED/);
});
test("database must be disposable and loopback-only",()=>{
 for(const databaseURL of [
  "postgresql://database.example.test/halo_test_workflow",
  "postgresql://localhost/halo_production",
  "postgresql://localhost/postgres",
  "postgresql://localhost/halo_test_workflow?mode=unsafe",
  "https://localhost/halo_test_workflow",
  "not a url"
 ])assert.throws(()=>validateLocalStagingConfig({...valid(),databaseURL}),Error,databaseURL);
});
test("test issuer and audience are mandatory",()=>{
 for(const issuer of ["https://login.example.com","http://id.example.test","https://id.example.test?x=1"])
  assert.throws(()=>validateLocalStagingConfig({...valid(),issuer}),/TEST_ISSUER_REQUIRED/);
 for(const audience of ["halo-production","", "https://api.example.com"])
  assert.throws(()=>validateLocalStagingConfig({...valid(),audience}),/TEST_AUDIENCE_REQUIRED/);
});
test("port is bounded and config is immutable",()=>{
 for(const port of [-1,65536,1.5])
  assert.throws(()=>validateLocalStagingConfig({...valid(),port}),/INVALID_PORT/);
 const cfg=validateLocalStagingConfig(valid());
 assert.equal(cfg.host,"127.0.0.1");
 assert.equal(cfg.port,0);
 assert.equal(Object.isFrozen(cfg),true);
});
