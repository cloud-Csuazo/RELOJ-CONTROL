begin;

insert into public.permissions values ('attendance.review','Revisar y corregir asistencia') on conflict do nothing;
insert into public.role_permissions select code,'attendance.review' from public.roles where code in ('ADMIN_GLOBAL','COMPANY_ADMIN','HR') on conflict do nothing;

create table public.attendance_sessions (
 id uuid primary key default gen_random_uuid(), company_id uuid not null references public.companies(id), employee_id uuid not null,
 state text not null check(state in ('WORKING','BREAK','FINISHED')), started_at timestamptz not null, ended_at timestamptz,
 timezone text not null, project_id uuid, version integer not null default 1,
 unique(company_id,id), foreign key(company_id,employee_id) references public.employees(company_id,id),
 foreign key(company_id,project_id) references public.projects(company_id,id), check(ended_at is null or ended_at>=started_at)
);
create unique index attendance_one_open_session on public.attendance_sessions(company_id,employee_id) where state<>'FINISHED';
create table public.attendance_events (
 id uuid primary key default gen_random_uuid(), company_id uuid not null references public.companies(id), employee_id uuid not null,
 session_id uuid not null, client_id uuid not null, project_id uuid, expected_location_id uuid,
 event_type text not null check(event_type in ('CLOCK_IN','BREAK_START','BREAK_END','CLOCK_OUT')),
 timestamp_server timestamptz not null default clock_timestamp(), timestamp_device timestamptz not null,
 timezone text not null, latitude double precision check(latitude between -90 and 90), longitude double precision check(longitude between -180 and 180),
 gps_accuracy double precision check(gps_accuracy between 0 and 100000), distance_meters double precision,
 ip inet, user_agent text not null default '' check(length(user_agent)<=500), device_info text not null default '' check(length(device_info)<=500),
 sync_status text not null check(sync_status in ('ONLINE','OFFLINE_REVIEW')), alerts text[] not null default '{}',
 request_payload jsonb not null, created_by uuid not null references auth.users(id), created_at timestamptz not null default clock_timestamp(),
 unique(company_id,employee_id,client_id), unique(company_id,id),
 foreign key(company_id,employee_id) references public.employees(company_id,id), foreign key(company_id,session_id) references public.attendance_sessions(company_id,id),
 foreign key(company_id,project_id) references public.projects(company_id,id),
 check((latitude is null)=(longitude is null)), check((latitude is null)=(gps_accuracy is null))
);
create table public.attendance_corrections (
 id uuid primary key default gen_random_uuid(),company_id uuid not null references public.companies(id),employee_id uuid not null,event_id uuid not null,
 original_timestamp timestamptz not null,corrected_timestamp timestamptz not null,
 reason text not null check(length(reason) between 5 and 500),requested_by uuid not null references auth.users(id),requested_at timestamptz not null default clock_timestamp(),
 status text not null default 'REQUESTED' check(status in ('REQUESTED','APPROVED','REJECTED')),
 approved_by uuid references auth.users(id), reviewed_at timestamptz, review_reason text check(length(review_reason) between 5 and 500),
 foreign key(company_id,employee_id) references public.employees(company_id,id),foreign key(company_id,event_id) references public.attendance_events(company_id,id),
 check((status='REQUESTED')=(approved_by is null)), check((status='REQUESTED')=(reviewed_at is null))
);
create unique index attendance_one_approved_correction on public.attendance_corrections(event_id) where status='APPROVED';
create index attendance_company_time on public.attendance_events(company_id,timestamp_server desc,id);
create index attendance_employee_time on public.attendance_events(company_id,employee_id,timestamp_server,id);
create index attendance_session_order on public.attendance_events(session_id,timestamp_server,id);
create index attendance_corrections_pending on public.attendance_corrections(company_id,status,requested_at);

alter table public.attendance_sessions enable row level security;
alter table public.attendance_events enable row level security;
alter table public.attendance_corrections enable row level security;
create policy attendance_sessions_read on public.attendance_sessions for select to authenticated using(private.can_read_employee(company_id,employee_id));
create policy attendance_events_read on public.attendance_events for select to authenticated using(private.can_read_employee(company_id,employee_id));
create policy attendance_corrections_read on public.attendance_corrections for select to authenticated using(private.can_read_employee(company_id,employee_id));
revoke all on public.attendance_sessions,public.attendance_events,public.attendance_corrections from public,anon,authenticated;
grant select on public.attendance_sessions,public.attendance_events,public.attendance_corrections to authenticated;
grant all on public.attendance_sessions,public.attendance_events,public.attendance_corrections to service_role;

create function private.attendance_immutable() returns trigger language plpgsql set search_path='' as $$
begin raise exception 'ATTENDANCE_APPEND_ONLY' using errcode='42501'; end; $$;
create trigger attendance_append_only before update or delete on public.attendance_events for each row execute function private.attendance_immutable();
revoke all on function private.attendance_immutable() from public,anon,authenticated;

-- Serialized per employment relationship. Device time never replaces official server time.
create function public.record_attendance(p_company uuid,p_client_id uuid,p_data jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare employee public.employees; session public.attendance_sessions; existing public.attendance_events; result uuid;
 kind text:=p_data->>'event_type'; project uuid:=nullif(p_data->>'project_id','')::uuid;
 lat double precision:=nullif(p_data->>'latitude','')::double precision; lon double precision:=nullif(p_data->>'longitude','')::double precision;
 accuracy double precision:=nullif(p_data->>'gps_accuracy','')::double precision; device_time timestamptz:=(p_data->>'timestamp_device')::timestamptz;
 official_time timestamptz; tz text; location public.project_locations; distance double precision; flags text[]:='{}'; offline boolean:=coalesce((p_data->>'offline')::boolean,false);
begin
 if not private.is_member(p_company) then raise exception 'DENIED' using errcode='42501'; end if;
 perform 1 from public.companies where id=p_company and status='active' for share;
 select * into employee from public.employees where company_id=p_company and user_id=auth.uid() and status='active' for update;
 if employee.id is null or not private.is_member(p_company) then raise exception 'DENIED' using errcode='42501'; end if;
 if p_client_id is null or p_data is null or kind is null or device_time is null or kind not in ('CLOCK_IN','BREAK_START','BREAK_END','CLOCK_OUT') or jsonb_typeof(p_data)<>'object' or pg_column_size(p_data)>8000 then raise exception 'INVALID_EVENT' using errcode='22023'; end if;
 select * into existing from public.attendance_events where company_id=p_company and employee_id=employee.id and client_id=p_client_id;
 if existing.id is not null then
  if existing.request_payload<>p_data then raise exception 'IDEMPOTENCY_CONFLICT' using errcode='23505'; end if;
  return existing.id;
 end if;
 if (lat is null)<>(lon is null) or (lat is null)<>(accuracy is null) or lat not between -90 and 90 or lon not between -180 and 180 or accuracy not between 0 and 100000 or length(coalesce(p_data->>'user_agent',''))>500 or length(coalesce(p_data->>'device_info',''))>500 then raise exception 'INVALID_METADATA' using errcode='22023'; end if;
 official_time:=clock_timestamp(); select timezone into tz from public.companies where id=p_company;
 select * into session from public.attendance_sessions where company_id=p_company and employee_id=employee.id and state<>'FINISHED' for update;
 if kind='CLOCK_IN' then
  if session.id is not null then raise exception 'ALREADY_STARTED' using errcode='23514'; end if;
  if project is not null and not exists(select 1 from public.employee_project_assignments a join public.projects p on p.company_id=a.company_id and p.id=a.project_id where a.company_id=p_company and a.employee_id=employee.id and a.project_id=project and a.status='active' and p.status='active' and a.starts_on<=(official_time at time zone tz)::date and (a.ends_on is null or a.ends_on>=(official_time at time zone tz)::date)) then raise exception 'PROJECT_NOT_ASSIGNED' using errcode='42501'; end if;
  insert into public.attendance_sessions(company_id,employee_id,state,started_at,timezone,project_id) values(p_company,employee.id,'WORKING',official_time,tz,project) returning * into session;
 else
  if session.id is null then raise exception 'NO_OPEN_SESSION' using errcode='23514'; end if;
  if project is distinct from session.project_id then raise exception 'PROJECT_CHANGED' using errcode='23514'; end if;
  if (kind='BREAK_START' and session.state<>'WORKING') or (kind='BREAK_END' and session.state<>'BREAK') or (kind='CLOCK_OUT' and session.state<>'WORKING') then raise exception 'INVALID_TRANSITION' using errcode='23514'; end if;
  update public.attendance_sessions set state=case kind when 'BREAK_START' then 'BREAK' when 'BREAK_END' then 'WORKING' else 'FINISHED' end,ended_at=case when kind='CLOCK_OUT' then official_time else null end,version=version+1 where id=session.id;
 end if;
 if lat is null then flags:=array_append(flags,'GPS_UNAVAILABLE'); end if;
 if accuracy>100 then flags:=array_append(flags,'GPS_LOW_ACCURACY'); end if;
 if offline then flags:=array_append(flags,'OFFLINE_NEEDS_REVIEW'); end if;
 if abs(extract(epoch from official_time-device_time))>300 then flags:=array_append(flags,'DEVICE_CLOCK_DIFFERENCE'); end if;
 if session.started_at<official_time-interval '18 hours' then flags:=array_append(flags,'LONG_OPEN_SESSION'); end if;
 if project is not null and lat is not null then
  select l.* into location from public.project_locations l where l.company_id=p_company and l.project_id=project
   order by power(l.latitude::double precision-lat,2)+power((l.longitude::double precision-lon)*cos(radians(lat)),2),l.id limit 1;
  if location.id is not null then
   distance:=6371000*2*asin(sqrt(least(1::double precision,power(sin(radians(lat-location.latitude::double precision)/2),2)+cos(radians(lat))*cos(radians(location.latitude::double precision))*power(sin(radians(lon-location.longitude::double precision)/2),2))));
   if distance>location.radius_meters then flags:=array_append(flags,'OUTSIDE_EXPECTED_LOCATION'); end if;
  else flags:=array_append(flags,'NO_EXPECTED_LOCATION'); end if;
 end if;
 insert into public.attendance_events(company_id,employee_id,session_id,client_id,project_id,expected_location_id,event_type,timestamp_server,timestamp_device,timezone,latitude,longitude,gps_accuracy,distance_meters,user_agent,device_info,sync_status,alerts,request_payload,created_by)
 values(p_company,employee.id,session.id,p_client_id,project,location.id,kind,official_time,device_time,tz,lat,lon,accuracy,distance,coalesce(p_data->>'user_agent',''),coalesce(p_data->>'device_info',''),case when offline then 'OFFLINE_REVIEW' else 'ONLINE' end,flags,p_data,auth.uid()) returning id into result;
 insert into public.audit_logs(company_id,actor_user_id,action,entity_type,entity_id,changed_fields) values(p_company,auth.uid(),'attendance.record','attendance_events',result,jsonb_build_object('event_type',kind,'sync_status',case when offline then 'OFFLINE_REVIEW' else 'ONLINE' end));
 return result;
end; $$;
revoke all on function public.record_attendance(uuid,uuid,jsonb) from public,anon;
grant execute on function public.record_attendance(uuid,uuid,jsonb) to authenticated;

create function public.request_attendance_correction(p_company uuid,p_event uuid,p_timestamp timestamptz,p_reason text) returns uuid language plpgsql security definer set search_path='' as $$
declare event public.attendance_events; result uuid;
begin
 if not private.is_member(p_company) then raise exception 'DENIED' using errcode='42501'; end if;
 select * into event from public.attendance_events where company_id=p_company and id=p_event;
 if event.id is null or not (private.has_permission(p_company,'attendance.review') or exists(select 1 from public.employees where company_id=p_company and id=event.employee_id and user_id=auth.uid() and status='active')) then raise exception 'DENIED' using errcode='42501'; end if;
 perform 1 from public.employees where id=event.employee_id and company_id=p_company for update;
 if p_timestamp is null or p_reason is null or length(trim(p_reason)) not between 5 and 500 or p_timestamp>clock_timestamp() or (p_timestamp at time zone event.timezone)::date<>(event.timestamp_server at time zone event.timezone)::date then raise exception 'INVALID_CORRECTION' using errcode='22023'; end if;
 if exists(select 1 from public.attendance_corrections where event_id=event.id and status in ('REQUESTED','APPROVED')) then raise exception 'CORRECTION_EXISTS' using errcode='23505'; end if;
 insert into public.attendance_corrections(company_id,employee_id,event_id,original_timestamp,corrected_timestamp,reason,requested_by) values(p_company,event.employee_id,event.id,event.timestamp_server,p_timestamp,trim(p_reason),auth.uid()) returning id into result;
 insert into public.audit_logs(company_id,actor_user_id,action,entity_type,entity_id,reason) values(p_company,auth.uid(),'attendance.correction.request','attendance_corrections',result,trim(p_reason));
 return result;
end; $$;
create function public.review_attendance_correction(p_company uuid,p_id uuid,p_approve boolean,p_reason text) returns void language plpgsql security definer set search_path='' as $$
declare correction public.attendance_corrections; event public.attendance_events; prior timestamptz; following timestamptz;
begin
 if not private.has_permission(p_company,'attendance.review') then raise exception 'DENIED' using errcode='42501'; end if;
 select * into correction from public.attendance_corrections where company_id=p_company and id=p_id;
 if correction.id is null then raise exception 'DENIED' using errcode='42501'; end if;
 perform 1 from public.employees where company_id=p_company and id=correction.employee_id for update;
 select * into correction from public.attendance_corrections where id=p_id for update;
 if correction.status<>'REQUESTED' or correction.requested_by=auth.uid() or p_approve is null or p_reason is null or length(trim(p_reason)) not between 5 and 500 then raise exception 'INVALID_REVIEW' using errcode='23514'; end if;
 select * into event from public.attendance_events where id=correction.event_id;
 select max(coalesce(c.corrected_timestamp,e.timestamp_server)) into prior from public.attendance_events e left join public.attendance_corrections c on c.event_id=e.id and c.status='APPROVED' where e.session_id=event.session_id and e.timestamp_server<event.timestamp_server;
 select min(coalesce(c.corrected_timestamp,e.timestamp_server)) into following from public.attendance_events e left join public.attendance_corrections c on c.event_id=e.id and c.status='APPROVED' where e.session_id=event.session_id and e.timestamp_server>event.timestamp_server;
 if p_approve and ((prior is not null and correction.corrected_timestamp<=prior) or (following is not null and correction.corrected_timestamp>=following)) then raise exception 'INVALID_EVENT_ORDER' using errcode='23514'; end if;
 update public.attendance_corrections set status=case when p_approve then 'APPROVED' else 'REJECTED' end,approved_by=auth.uid(),reviewed_at=clock_timestamp(),review_reason=trim(p_reason) where id=p_id;
 insert into public.audit_logs(company_id,actor_user_id,action,entity_type,entity_id,reason) values(p_company,auth.uid(),case when p_approve then 'attendance.correction.approve' else 'attendance.correction.reject' end,'attendance_corrections',p_id,trim(p_reason));
end; $$;
revoke all on function public.request_attendance_correction(uuid,uuid,timestamptz,text),public.review_attendance_correction(uuid,uuid,boolean,text) from public,anon;
grant execute on function public.request_attendance_correction(uuid,uuid,timestamptz,text),public.review_attendance_correction(uuid,uuid,boolean,text) to authenticated;
commit;
