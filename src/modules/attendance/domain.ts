import {z} from 'zod';
export const eventKinds=['CLOCK_IN','BREAK_START','BREAK_END','CLOCK_OUT'] as const;
export type EventKind=typeof eventKinds[number];
export type JourneyState='IDLE'|'WORKING'|'BREAK'|'FINISHED';
export const eventLabels:Record<EventKind,string>={CLOCK_IN:'Inicio de jornada',BREAK_START:'Inicio de colación',BREAK_END:'Fin de colación',CLOCK_OUT:'Fin de jornada'};
export function transition(state:JourneyState,kind:EventKind):JourneyState|null{
 if(kind==='CLOCK_IN'&&(state==='IDLE'||state==='FINISHED'))return 'WORKING';
 if(kind==='BREAK_START'&&state==='WORKING')return 'BREAK';
 if(kind==='BREAK_END'&&state==='BREAK')return 'WORKING';
 if(kind==='CLOCK_OUT'&&state==='WORKING')return 'FINISHED';
 return null;
}
export const attendanceInput=z.object({company:z.uuid(),client_id:z.uuid(),data:z.object({event_type:z.enum(eventKinds),project_id:z.union([z.uuid(),z.null()]),timestamp_device:z.iso.datetime({offset:true}),latitude:z.number().min(-90).max(90).nullable(),longitude:z.number().min(-180).max(180).nullable(),gps_accuracy:z.number().min(0).max(100000).nullable(),offline:z.boolean(),device_info:z.string().max(500),user_agent:z.string().max(500)}).refine(v=>(v.latitude===null)===(v.longitude===null)&&(v.latitude===null)===(v.gps_accuracy===null))});
export type Mark= z.infer<typeof attendanceInput>;
export type EventRow={id:string;employee_id:string;session_id:string;event_type:EventKind;timestamp_server:string;timestamp_device:string;timezone:string;alerts:string[];sync_status:string;distance_meters:number|null};
export function workMilliseconds(events:Pick<EventRow,'event_type'|'timestamp_server'>[],now:number){
 let started:number|null=null,total=0;
 for(const event of events){const time=Date.parse(event.timestamp_server);if(!Number.isFinite(time))continue;
  if(event.event_type==='CLOCK_IN'||event.event_type==='BREAK_END')started=time;
  else if(started!==null){total+=Math.max(0,time-started);started=null;}
 }
 if(started!==null)total+=Math.max(0,now-started);
 return total;
}
