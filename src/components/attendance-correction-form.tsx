'use client';
import {useActionState,useState} from 'react';
import {requestCorrection,reviewCorrection} from '@/modules/attendance/actions';
export function CorrectionForm({companyId,eventId}:{companyId:string;eventId:string}){
 const [state,action,pending]=useActionState(requestCorrection,{}),[stamp,setStamp]=useState('');
 return <form action={action} className="record-form"><input type="hidden" name="company" value={companyId}/><input type="hidden" name="event" value={eventId}/><input type="hidden" name="timestamp" value={stamp?new Date(stamp).toISOString():''}/><label>Hora corregida (zona del dispositivo)<input type="datetime-local" value={stamp} onChange={e=>setStamp(e.target.value)} required/></label><label>Motivo<textarea name="reason" required minLength={5} maxLength={500}/></label>{state.error&&<p role="alert">{state.error}</p>}{state.success&&<p role="status">{state.success}</p>}<button className="button secondary" disabled={pending}>Solicitar corrección</button></form>;
}
export function ReviewCorrectionForm({companyId,id}:{companyId:string;id:string}){
 const [state,action,pending]=useActionState(reviewCorrection,{});
 return <form action={action} className="record-form"><input type="hidden" name="company" value={companyId}/><input type="hidden" name="id" value={id}/><label>Decisión<select name="decision"><option value="approve">Aprobar</option><option value="reject">Rechazar</option></select></label><label>Motivo de revisión<textarea name="reason" required minLength={5} maxLength={500}/></label>{state.error&&<p role="alert">{state.error}</p>}{state.success&&<p role="status">{state.success}</p>}<button className="button secondary" disabled={pending}>Guardar revisión</button></form>;
}
