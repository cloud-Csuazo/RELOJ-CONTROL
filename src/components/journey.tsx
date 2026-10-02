'use client';
import {useCallback,useEffect,useRef,useState} from 'react';
import {useRouter} from 'next/navigation';
import {enqueue,initializeQueue,pending,removePending} from '@/modules/attendance/queue';
import {eventLabels,transition,workMilliseconds,type EventKind,type EventRow,type JourneyState,type Mark} from '@/modules/attendance/domain';
type Props={company:string;userId:string;name:string;timezone:string;state:JourneyState;sessionProject:string|null;projects:{id:string;name:string}[];events:EventRow[]};
const stateLabels={IDLE:'Sin jornada abierta',WORKING:'Trabajando',BREAK:'En colación',FINISHED:'Jornada finalizada'};
export function Journey(props:Props){
 const router=useRouter(),scope=`${props.userId}:${props.company}`,busy=useRef(false);
 const [marks,setMarks]=useState<Mark[]>([]),[message,setMessage]=useState(''),[working,setWorking]=useState(false),[ready,setReady]=useState(false),[project,setProject]=useState(props.sessionProject??''),[now,setNow]=useState(0);
 const load=useCallback(async()=>{const rows=await pending(scope);setMarks(rows.map(r=>r.mark));},[scope]);
 const sync=useCallback(async()=>{
  if(busy.current||!navigator.onLine)return;busy.current=true;setWorking(true);
  try{for(const item of await pending(scope)){
   let response:Response;try{response=await fetch('/api/attendance',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(item.mark)});}catch{setMessage('Marcación guardada. Pendiente de sincronización.');break;}
   const body=await response.json();if(!response.ok){setMessage(body.error??'No pudimos sincronizar. Conservamos la marcación pendiente.');break;}
   await removePending(item.id);setMessage('Marcación registrada con hora del servidor.');router.refresh();
  }await load();}catch{setMessage('No pudimos acceder a las marcaciones pendientes del dispositivo.');}finally{busy.current=false;setWorking(false);}
 },[scope,load,router]);
 useEffect(()=>{let cancelled=false;void initializeQueue(props.userId).then(async expired=>{await load();if(!cancelled){setReady(true);setNow(Date.now());if(expired)setMessage('Se retiraron marcaciones antiguas o de otra cuenta del dispositivo. Revisa tu historial si falta alguna.');void sync();}}).catch(()=>setMessage('El dispositivo no permite guardar marcaciones. Revisa los permisos del navegador.'));const online=()=>void sync();window.addEventListener('online',online);const timer=setInterval(()=>{setNow(Date.now());void sync();},30000);return()=>{cancelled=true;window.removeEventListener('online',online);clearInterval(timer);};},[props.userId,load,sync]);
 let state=props.state;for(const mark of marks)state=transition(state,mark.data.event_type)??state;
 const activeProject=marks.find(m=>m.data.event_type==='CLOCK_IN')?.data.project_id??props.sessionProject;
 async function mark(kind:EventKind){
  if(!ready||working||busy.current)return;setWorking(true);
  const timestamp=new Date().toISOString();let latitude:number|null=null,longitude:number|null=null,accuracy:number|null=null;
  try{if(navigator.geolocation){const geo=await new Promise<GeolocationPosition|null>(resolve=>navigator.geolocation.getCurrentPosition(resolve,()=>resolve(null),{enableHighAccuracy:true,timeout:8000,maximumAge:0}));if(geo){latitude=geo.coords.latitude;longitude=geo.coords.longitude;accuracy=geo.coords.accuracy;}}
   const data:Mark={company:props.company,client_id:crypto.randomUUID(),data:{event_type:kind,project_id:kind==='CLOCK_IN'?(project||null):(activeProject??null),timestamp_device:timestamp,latitude,longitude,gps_accuracy:accuracy,offline:!navigator.onLine,device_info:`${navigator.language}; ${window.innerWidth}x${window.innerHeight}`,user_agent:navigator.userAgent.slice(0,500)}};
   // Persist before sending. The identical payload is retried after a lost response.
   await enqueue(scope,data);await load();setMessage('Marcación guardada. Pendiente de sincronización.');
  }catch{setMessage('No pudimos guardar en el dispositivo. No se registró la marcación.');}finally{setWorking(false);}await sync();
 }
 const minutes=Math.floor(workMilliseconds(props.events,now)/60000);
 return <div className="journey"><h2>Hola, {props.name}</h2><p className="journey-state">{stateLabels[state]}</p><p>{Math.floor(minutes/60)} h {minutes%60} min registradas · {props.timezone}</p>{(state==='IDLE'||state==='FINISHED')&&<label>Proyecto<select value={project} onChange={e=>setProject(e.target.value)} disabled={working||marks.length>0}><option value="">Sin proyecto</option>{props.projects.map(p=><option key={p.id} value={p.id}>{p.name}</option>)}</select></label>}<div className="journey-actions">{(['CLOCK_IN','BREAK_START','BREAK_END','CLOCK_OUT'] as EventKind[]).filter(kind=>transition(state,kind)!==null).map(kind=><button key={kind} className={`button ${kind==='BREAK_START'?'secondary':''}`} disabled={!ready||working} onClick={()=>void mark(kind)}>{working?'Registrando…':eventLabels[kind]}</button>)}</div>{message&&<p role="status" className="notice">{message}</p>}{marks.length>0&&<><p>{marks.length} marcación(es) pendiente(s). La hora del dispositivo requiere revisión cuando se sincroniza sin conexión.</p><button className="button secondary" disabled={working} onClick={()=>void sync()}>Sincronizar pendientes</button></>}<p className="muted">La ubicación se solicita sólo al marcar. Estar fuera del proyecto no impide registrar.</p></div>;
}

