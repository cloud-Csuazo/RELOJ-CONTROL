begin;

insert into public.permissions values ('workforce.manage','Gestionar personas y proyectos'),('workforce.read','Leer administración de personas') on conflict do nothing;
insert into public.role_permissions select r.code,p.code from public.roles r cross join public.permissions p where r.code in ('ADMIN_GLOBAL','COMPANY_ADMIN','HR') and p.code in ('workforce.manage','workforce.read') on conflict do nothing;

alter table public.employees add column job_title text not null default '', add column hired_on date, add column ended_on date, add column version integer not null default 1, add column updated_at timestamptz not null default now(), add constraint employees_dates check(ended_on is null or (hired_on is not null and ended_on>=hired_on));
create function private.valid_rut(value text) returns boolean language plpgsql immutable set search_path='' as $$
declare body text; digit text; total integer:=0; factor integer:=2; i integer; expected text; number integer;
begin
  if value is null then return true; end if;
  if value !~ '^[0-9]{7,8}-[0-9K]$' then return false; end if;
  body:=split_part(value,'-',1); digit:=split_part(value,'-',2);
  if body::bigint=0 then return false; end if;
  for i in reverse length(body)..1 loop total:=total+substr(body,i,1)::integer*factor; factor:=case when factor=7 then 2 else factor+1 end; end loop;
  number:=11-(total%11); expected:=case number when 11 then '0' when 10 then 'K' else number::text end;
  return digit=expected;
end; $$;

create table public.employee_personal_data (
  employee_id uuid primary key, company_id uuid not null references public.companies(id),
  rut text check(private.valid_rut(rut)), email text check(email is null or (length(email)<=254 and email like '%_@_%._%')),
  phone text check(length(phone)<=40), address text check(length(address)<=300), born_on date,
  foreign key(company_id,employee_id) references public.employees(company_id,id), unique(company_id,rut)
);
create table public.cost_centers (
  id uuid primary key default gen_random_uuid(), company_id uuid not null references public.companies(id),
  code text not null check(length(code) between 1 and 40), name text not null check(length(name) between 2 and 120),
  status text not null default 'active' check(status in ('active','inactive')), version integer not null default 1,
  unique(company_id,id), unique(company_id,code), created_at timestamptz not null default now()
);
create table public.projects (
  id uuid primary key default gen_random_uuid(), company_id uuid not null references public.companies(id),
  code text not null check(length(code) between 1 and 40), name text not null check(length(name) between 2 and 160),
  client_name text not null default '', description text not null default '', starts_on date, ends_on date,
  cost_center_id uuid, status text not null default 'active' check(status in ('active','inactive','completed')),
  version integer not null default 1, created_at timestamptz not null default now(),
  unique(company_id,id), unique(company_id,code), foreign key(company_id,cost_center_id) references public.cost_centers(company_id,id),
  check(ends_on is null or (starts_on is not null and ends_on>=starts_on)), check(length(description)<=2000), check(length(client_name)<=160)
);
create table public.project_locations (
  id uuid primary key default gen_random_uuid(),company_id uuid not null references public.companies(id),project_id uuid not null,
  name text not null check(length(name) between 2 and 160),address text not null default '' check(length(address)<=300),
  latitude numeric(10,7) not null check(latitude between -90 and 90), longitude numeric(10,7) not null check(longitude between -180 and 180),
  radius_meters integer not null default 200 check(radius_meters between 1 and 100000), version integer not null default 1,
  foreign key(company_id,project_id) references public.projects(company_id,id)
);
create table public.employee_project_assignments (
  id uuid primary key default gen_random_uuid(), company_id uuid not null references public.companies(id), employee_id uuid not null, project_id uuid not null,
  starts_on date not null, ends_on date, status text not null default 'active' check(status in ('active','inactive')),
  version integer not null default 1, created_at timestamptz not null default now(),
  foreign key(company_id,employee_id) references public.employees(company_id,id),foreign key(company_id,project_id) references public.projects(company_id,id),
  check(ends_on is null or ends_on>=starts_on),unique(company_id,employee_id,project_id,starts_on)
);
create table public.employee_supervisor_assignments (
  id uuid primary key default gen_random_uuid(),company_id uuid not null references public.companies(id),employee_id uuid not null,supervisor_user_id uuid not null,
  starts_on date not null,ends_on date,status text not null default 'active' check(status in ('active','inactive')),version integer not null default 1,
  foreign key(company_id,employee_id) references public.employees(company_id,id),
  foreign key(company_id,supervisor_user_id) references public.user_company_memberships(company_id,user_id),check(ends_on is null or ends_on>=starts_on)
);
create table public.employee_contracts (
  id uuid primary key default gen_random_uuid(),company_id uuid not null references public.companies(id),employee_id uuid not null,
  contract_type text not null check(contract_type in ('indefinite','fixed_term','project')),job_title text not null check(length(job_title) between 2 and 120),
  starts_on date not null,ends_on date,weekly_minutes integer not null check(weekly_minutes between 1 and 10080),
  base_salary bigint not null check(base_salary between 0 and 100000000000),schedule text not null default '' check(length(schedule)<=1000),
  created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
  ended_reason text, version integer not null default 1,
  foreign key(company_id,employee_id) references public.employees(company_id,id),check(ends_on is null or ends_on>=starts_on)
);

create index assignment_employee_time on public.employee_project_assignments(company_id,employee_id,starts_on,ends_on);
create index supervisor_employee_time on public.employee_supervisor_assignments(company_id,supervisor_user_id,employee_id);
create index contracts_employee_time on public.employee_contracts(company_id,employee_id,starts_on,ends_on);
create index employees_search_company on public.employees(company_id,status,display_name);
create index projects_company_status on public.projects(company_id,status);

create function private.can_read_employee(p_company uuid,p_employee uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.is_member(p_company) and (
   private.has_permission(p_company,'workforce.read') or exists(select 1 from public.employees e where e.company_id=p_company and e.id=p_employee and e.user_id=auth.uid())
   or exists(select 1 from public.employee_supervisor_assignments a join public.user_company_memberships m on m.company_id=a.company_id and m.user_id=a.supervisor_user_id where a.company_id=p_company and a.employee_id=p_employee and a.supervisor_user_id=auth.uid() and m.role_code='SUPERVISOR' and a.status='active' and a.starts_on<=current_date and (a.ends_on is null or a.ends_on>=current_date))
 ); $$;
create function private.can_read_project(p_company uuid,p_project uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.is_member(p_company) and (private.has_permission(p_company,'workforce.read') or exists(select 1 from public.employee_project_assignments a where a.company_id=p_company and a.project_id=p_project and a.status='active' and a.starts_on<=current_date and (a.ends_on is null or a.ends_on>=current_date) and private.can_read_employee(p_company,a.employee_id)));
$$;
revoke all on function private.valid_rut(text),private.can_read_employee(uuid,uuid),private.can_read_project(uuid,uuid) from public,anon;
grant execute on function private.can_read_employee(uuid,uuid),private.can_read_project(uuid,uuid) to authenticated;

-- Replace the initial worker kernel policy to include explicit supervisor assignments.
drop policy if exists employees_select on public.employees;
create policy employees_workforce_read on public.employees for select to authenticated using(private.can_read_employee(company_id,id));
alter table public.employee_personal_data enable row level security;
alter table public.cost_centers enable row level security;
alter table public.projects enable row level security;
alter table public.project_locations enable row level security;
alter table public.employee_project_assignments enable row level security;
alter table public.employee_supervisor_assignments enable row level security;
alter table public.employee_contracts enable row level security;
create policy personal_read on public.employee_personal_data for select to authenticated using(private.is_member(company_id) and (private.has_permission(company_id,'workforce.read') or exists(select 1 from public.employees e where e.company_id=employee_personal_data.company_id and e.id=employee_id and e.user_id=auth.uid())));
create policy centers_read on public.cost_centers for select to authenticated using(private.has_permission(company_id,'workforce.read'));
create policy projects_read on public.projects for select to authenticated using(private.can_read_project(company_id,id));
create policy locations_read on public.project_locations for select to authenticated using(private.can_read_project(company_id,project_id));
create policy projects_assignments_read on public.employee_project_assignments for select to authenticated using(private.can_read_employee(company_id,employee_id));
create policy supervisors_assignments_read on public.employee_supervisor_assignments for select to authenticated using(private.can_read_employee(company_id,employee_id));
create policy contracts_read on public.employee_contracts for select to authenticated using(private.is_member(company_id) and (private.has_permission(company_id,'workforce.read') or exists(select 1 from public.employees e where e.company_id=employee_contracts.company_id and e.id=employee_id and e.user_id=auth.uid())));
revoke all on public.employee_personal_data,public.cost_centers,public.projects,public.project_locations,public.employee_project_assignments,public.employee_supervisor_assignments,public.employee_contracts from public,anon,authenticated;
grant select on public.employee_personal_data,public.cost_centers,public.projects,public.project_locations,public.employee_project_assignments,public.employee_supervisor_assignments,public.employee_contracts to authenticated;
grant all on public.employee_personal_data,public.cost_centers,public.projects,public.project_locations,public.employee_project_assignments,public.employee_supervisor_assignments,public.employee_contracts to service_role;

create function private.audit_workforce() returns trigger language plpgsql security definer set search_path='' as $$
declare keys jsonb; entity uuid;
begin
 if tg_op='UPDATE' then select coalesce(jsonb_agg(n.key),'[]'::jsonb) into keys from jsonb_each(to_jsonb(new)) n where n.value is distinct from to_jsonb(old)->n.key; else keys:='[]'::jsonb; end if;
 entity:=coalesce((to_jsonb(new)->>'id')::uuid,(to_jsonb(new)->>'employee_id')::uuid);
 insert into public.audit_logs(company_id,actor_user_id,action,entity_type,entity_id,reason,changed_fields) values(new.company_id,auth.uid(),tg_op,tg_table_name,entity,nullif(current_setting('app.audit_reason',true),''),jsonb_build_object('fields',keys));
 return new;
end; $$;
revoke all on function private.audit_workforce() from public,anon,authenticated;
do $$declare t text;begin foreach t in array array['employees','employee_personal_data','cost_centers','projects','project_locations','employee_project_assignments','employee_supervisor_assignments','employee_contracts'] loop execute format('create trigger workforce_audit after insert or update on public.%I for each row execute function private.audit_workforce()',t);end loop;end $$;

create function public.save_workforce(p_company uuid,p_kind text,p_id uuid,p_version integer,p_data jsonb,p_reason text) returns uuid language plpgsql security definer set search_path='' as $$
declare result uuid; current_version integer; worker uuid; supervisor uuid;
begin
 if not private.has_permission(p_company,'workforce.manage') then raise exception 'ACCESS_DENIED' using errcode='42501';end if;
 if p_reason is null or length(trim(p_reason)) not between 5 and 500 then raise exception 'REASON_REQUIRED' using errcode='22023';end if;
 perform 1 from public.companies where id=p_company for share;
 if not private.has_permission(p_company,'workforce.manage') then raise exception 'ACCESS_DENIED' using errcode='42501';end if;
 perform set_config('app.audit_reason',trim(p_reason),true);
 result:=coalesce(p_id,gen_random_uuid());
 if p_kind='employee' then
   if p_id is null then insert into public.employees(id,company_id,user_id,display_name,status,job_title,hired_on,ended_on) values(result,p_company,nullif(p_data->>'user_id','')::uuid,p_data->>'display_name',coalesce(p_data->>'status','active'),coalesce(p_data->>'job_title',''),nullif(p_data->>'hired_on','')::date,nullif(p_data->>'ended_on','')::date);
   else select version into current_version from public.employees where id=p_id and company_id=p_company for update;
     if current_version is null then raise exception 'ACCESS_DENIED' using errcode='42501';end if;
     if current_version<>p_version then raise exception 'STALE_VERSION' using errcode='40001';end if;
     update public.employees set display_name=p_data->>'display_name',status=p_data->>'status',job_title=coalesce(p_data->>'job_title',''),hired_on=nullif(p_data->>'hired_on','')::date,ended_on=nullif(p_data->>'ended_on','')::date,version=version+1,updated_at=now() where id=p_id and company_id=p_company;
   end if;
   if nullif(p_data->>'user_id','') is not null and not exists(select 1 from public.user_company_memberships where company_id=p_company and user_id=(p_data->>'user_id')::uuid) then raise exception 'IDENTITY_NOT_MEMBER' using errcode='23514';end if;
   insert into public.employee_personal_data(employee_id,company_id,rut,email,phone,address,born_on) values(result,p_company,nullif(p_data->>'rut',''),nullif(p_data->>'email',''),nullif(p_data->>'phone',''),nullif(p_data->>'address',''),nullif(p_data->>'born_on','')::date) on conflict(employee_id) do update set rut=excluded.rut,email=excluded.email,phone=excluded.phone,address=excluded.address,born_on=excluded.born_on;
 elsif p_kind in ('cost_center','project') then
   if p_id is not null then
     if p_kind='cost_center' then select version into current_version from public.cost_centers where id=p_id and company_id=p_company for update;else select version into current_version from public.projects where id=p_id and company_id=p_company for update;end if;
     if current_version is null then raise exception 'ACCESS_DENIED' using errcode='42501';end if;
     if current_version<>p_version then raise exception 'STALE_VERSION' using errcode='40001';end if;
   end if;
   if p_kind='cost_center' then
     if p_id is null then insert into public.cost_centers(id,company_id,code,name,status) values(result,p_company,p_data->>'code',p_data->>'name',coalesce(p_data->>'status','active'));
     else update public.cost_centers set code=p_data->>'code',name=p_data->>'name',status=p_data->>'status',version=version+1 where id=p_id and company_id=p_company;end if;
   else
     if p_id is null then insert into public.projects(id,company_id,code,name,client_name,description,starts_on,ends_on,cost_center_id,status) values(result,p_company,p_data->>'code',p_data->>'name',coalesce(p_data->>'client_name',''),coalesce(p_data->>'description',''),nullif(p_data->>'starts_on','')::date,nullif(p_data->>'ends_on','')::date,nullif(p_data->>'cost_center_id','')::uuid,coalesce(p_data->>'status','active'));
     else update public.projects set code=p_data->>'code',name=p_data->>'name',client_name=coalesce(p_data->>'client_name',''),description=coalesce(p_data->>'description',''),starts_on=nullif(p_data->>'starts_on','')::date,ends_on=nullif(p_data->>'ends_on','')::date,cost_center_id=nullif(p_data->>'cost_center_id','')::uuid,status=p_data->>'status',version=version+1 where id=p_id and company_id=p_company;end if;
   end if;
 elsif p_kind in ('project_assignment','supervisor_assignment','contract','location') then
   if p_id is not null then raise exception 'HISTORY_IMMUTABLE' using errcode='42501';end if;
   worker:=nullif(p_data->>'employee_id','')::uuid;
   if p_kind<>'location' then perform 1 from public.employees where id=worker and company_id=p_company for update;if not found then raise exception 'ACCESS_DENIED' using errcode='42501';end if;end if;
   if p_kind='project_assignment' then insert into public.employee_project_assignments(id,company_id,employee_id,project_id,starts_on,ends_on) values(result,p_company,worker,(p_data->>'project_id')::uuid,(p_data->>'starts_on')::date,nullif(p_data->>'ends_on','')::date);
   elsif p_kind='supervisor_assignment' then
     supervisor:=(p_data->>'supervisor_user_id')::uuid;
     if not exists(select 1 from public.user_company_memberships where company_id=p_company and user_id=supervisor and role_code='SUPERVISOR' and status='active') then raise exception 'INVALID_SUPERVISOR' using errcode='23514';end if;
     insert into public.employee_supervisor_assignments(id,company_id,employee_id,supervisor_user_id,starts_on,ends_on) values(result,p_company,worker,supervisor,(p_data->>'starts_on')::date,nullif(p_data->>'ends_on','')::date);
   elsif p_kind='contract' then
     if exists(select 1 from public.employee_contracts where company_id=p_company and employee_id=worker and daterange(starts_on,ends_on,'[]')&&daterange((p_data->>'starts_on')::date,nullif(p_data->>'ends_on','')::date,'[]')) then raise exception 'CONTRACT_OVERLAP' using errcode='23514';end if;
     insert into public.employee_contracts(id,company_id,employee_id,contract_type,job_title,starts_on,ends_on,weekly_minutes,base_salary,schedule,created_by) values(result,p_company,worker,p_data->>'contract_type',p_data->>'job_title',(p_data->>'starts_on')::date,nullif(p_data->>'ends_on','')::date,(p_data->>'weekly_minutes')::integer,(p_data->>'base_salary')::bigint,coalesce(p_data->>'schedule',''),auth.uid());
   else insert into public.project_locations(id,company_id,project_id,name,address,latitude,longitude,radius_meters) values(result,p_company,(p_data->>'project_id')::uuid,p_data->>'name',coalesce(p_data->>'address',''),(p_data->>'latitude')::numeric,(p_data->>'longitude')::numeric,(p_data->>'radius_meters')::integer);end if;
 else raise exception 'INVALID_KIND' using errcode='22023';end if;
 return result;
end; $$;
revoke all on function public.save_workforce(uuid,text,uuid,integer,jsonb,text) from public,anon;
grant execute on function public.save_workforce(uuid,text,uuid,integer,jsonb,text) to authenticated;
commit;
