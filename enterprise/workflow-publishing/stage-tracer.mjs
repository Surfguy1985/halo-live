// Lightweight stage timings, isolated reference implementation.
// No tokens, SQL values or customer payloads appear in emitted events.
export function createStageTracer({emit=()=>{},clock=()=>performance.now()}={}) {
 return async function stage(name,correlationID,operation) {
  if(!/^(auth.verify|membership.load|workflow.publish|database.transaction)$/.test(name))
   throw new TypeError("Unknown trace stage");
  if(typeof operation!=="function")throw new TypeError("operation required");
  const start=clock();
  let outcome="ok";
  try {return await operation();}
  catch(error){outcome="error";throw error;}
  finally {
   try {emit({event:"halo.workflow.stage",name,correlationID:correlationID??null,
    outcome,durationMs:Math.max(0,clock()-start)});}catch{/* never fail business work from telemetry */}
  }
 };
}
