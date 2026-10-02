'use client';
import {useState} from 'react';
import {RecordForm,type Field} from './record-form';
import {saveNovelty} from '@/modules/novelties/actions';
import {noveltyKinds} from '@/modules/novelties/domain';
export function NoveltyCreateForm({companyId,employees,projects,categories,canManage}:{companyId:string;employees:{id:string;display_name:string}[];projects:{id:string;name:string}[];categories:{id:string;name:string}[];canManage:boolean}){
 const [kind,setKind]=useState<keyof typeof noveltyKinds>('OVERTIME');
 const fields:Field[]=[...(canManage?[{name:'employee_id',label:'Trabajador',required:true,options:employees.map(e=>({value:e.id,label:e.display_name}))}]:[]),{name:'occurs_on',label:'Fecha',type:'date',required:true},{name:'project_id',label:'Proyecto',options:[{value:'',label:'Sin proyecto'},...projects.map(p=>({value:p.id,label:p.name}))]},{name:'description',label:'Motivo y descripción',type:'textarea',required:true,maxLength:2000}];
 if(kind==='OVERTIME')fields.push({name:'starts_at',label:'Inicio (hora del dispositivo)',type:'datetime-local',required:true},{name:'ends_at',label:'Término (hora del dispositivo)',type:'datetime-local',required:true},{name:'requested_minutes',label:'Minutos solicitados',type:'number',required:true});
 if(['EXPENSE','REIMBURSEMENT','ADVANCE','ALLOWANCE'].includes(kind))fields.push({name:'requested_amount',label:'Monto solicitado (pesos enteros)',required:true,type:'number'});
 if(['EXPENSE','REIMBURSEMENT','ALLOWANCE'].includes(kind))fields.push({name:'reimbursement_channel',label:'Devolución solicitada',options:[{value:'PAYROLL',label:'Cierre mensual'},{value:'DIRECT_PAYMENT',label:'Pago directo'}]},{name:'category_id',label:'Categoría',options:[{value:'',label:'Sin categoría'},...categories.map(c=>({value:c.id,label:c.name}))]},{name:'vendor',label:'Proveedor'});
 if(['LEAVE','ABSENCE'].includes(kind))fields.push({name:'ends_on',label:'Hasta',type:'date'});
 fields.push({name:'draft',label:'Envío',options:[{value:'false',label:'Enviar a revisión'},{value:'true',label:'Guardar borrador'}]});
 return <><label>Tipo de novedad<select value={kind} onChange={e=>setKind(e.target.value as keyof typeof noveltyKinds)}>{Object.entries(noveltyKinds).map(([value,label])=><option key={value} value={value}>{label}</option>)}</select></label><RecordForm key={kind} companyId={companyId} kind="novelty.create" operationAction={saveNovelty} showReason={false} extra={{type:kind}} fields={fields} label="Guardar novedad"/></>;
}
