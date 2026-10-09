// Safe, opt-in configuration guard for future LOCAL staging composition.
// No sockets, migrations or external services are started by this module.
export function validateLocalStagingConfig({enabled=false,databaseURL,issuer,audience,port=0}={}) {
 if(enabled!==true)throw Error("LOCAL_STAGING_DISABLED");
 let db;
 try {db=new URL(databaseURL);} catch {throw Error("INVALID_DATABASE_URL");}
 if(!["postgres:","postgresql:"].includes(db.protocol) ||
    !["localhost","127.0.0.1"].includes(db.hostname) ||
    !/^halo_test_[a-z0-9_]+$/i.test(db.pathname.slice(1)) ||
    db.search || db.hash)
  throw Error("DISPOSABLE_LOOPBACK_DATABASE_REQUIRED");
 let id;
 try {id=new URL(issuer);} catch {throw Error("TEST_ISSUER_REQUIRED");}
 if(id.protocol!=="https:" || !id.hostname.endsWith(".test") ||
    id.username || id.password || id.search || id.hash)
  throw Error("TEST_ISSUER_REQUIRED");
 if(typeof audience!=="string" || !/^halo-test-[a-z0-9_-]+$/.test(audience))
  throw Error("TEST_AUDIENCE_REQUIRED");
 if(!Number.isInteger(port) || port<0 || port>65535)
  throw Error("INVALID_PORT");
 return Object.freeze({databaseURL,issuer,audience,host:"127.0.0.1",port});
}
