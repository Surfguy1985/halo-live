import {assertCIStagingWorkflowConfiguration} from "./staging-ci-admission.mjs";

const deny=()=>{throw new Error("HALO CI recovery rehearsal admission denied");};

export function assertCIRecoveryRehearsalConfiguration(config=process.env){
 const admission=assertCIStagingWorkflowConfiguration(config);
 if(config.HALO_REHEARSAL_APPROVED!=="ephemeral-ci-backup-restore-rollback")deny();
 return Object.freeze({...admission,rehearsal:"backup-restore-rollback"});
}
