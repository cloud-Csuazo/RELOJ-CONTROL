import type {Mark} from './domain';
type Pending={id:string;scope:string;created:number;mark:Mark};
const databaseName='nexo-attendance-pending-v1';
const lifespan=48*60*60*1000;
function open(){return new Promise<IDBDatabase>((resolve,reject)=>{const r=indexedDB.open(databaseName,1);r.onupgradeneeded=()=>r.result.createObjectStore('marks',{keyPath:'id'});r.onsuccess=()=>resolve(r.result);r.onerror=()=>reject(new Error('LOCAL_STORAGE_UNAVAILABLE'));});}
async function transaction<T>(mode:IDBTransactionMode,run:(store:IDBObjectStore)=>IDBRequest<T>){const db=await open();try{return await new Promise<T>((resolve,reject)=>{const tx=db.transaction('marks',mode);const r=run(tx.objectStore('marks'));tx.oncomplete=()=>resolve(r.result);tx.onerror=()=>reject(new Error('LOCAL_STORAGE_UNAVAILABLE'));tx.onabort=()=>reject(new Error('LOCAL_STORAGE_UNAVAILABLE'));});}finally{db.close();}}
export async function pending(scope:string){const items=await transaction('readonly',s=>s.getAll()) as Pending[];return items.filter(i=>i.scope===scope).sort((a,b)=>a.created-b.created);}
export async function initializeQueue(userId:string){const items=await transaction('readonly',s=>s.getAll()) as Pending[];let expired=0;for(const item of items){if(!item.scope.startsWith(`${userId}:`)||item.created<Date.now()-lifespan){await removePending(item.id);expired++;}}return expired;}
export async function enqueue(scope:string,mark:Mark){if((await pending(scope)).length>=50)throw new Error('QUEUE_FULL');await transaction('readwrite',s=>s.add({id:mark.client_id,scope,created:Date.now(),mark} satisfies Pending));}
export async function removePending(id:string){await transaction('readwrite',s=>s.delete(id));}
export async function clearAttendanceQueue(){await transaction('readwrite',s=>s.clear());}
