-- DEVELOPMENT ONLY. Run once in a new empty DEV project. No real personal data.
begin;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table public.roles (
  code text primary key check (code in ('ADMIN_GLOBAL','COMPANY_ADMIN','HR','SUPERVISOR','EMPLOYEE')),
  description text not null
);
create table public.permissions (code text primary key, description text not null);
create table public.role_permissions (
  role_code text not null references public.roles(code),
  permission_code text not null references public.permissions(code),
  primary key (role_code,permission_code)
);
create table public.companies (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (length(code) between 2 and 40),
  legal_name text not null check (length(legal_name) between 2 and 160),
  display_name text not null check (length(display_name) between 2 and 160),
  timezone text not null default 'America/Santiago',
  currency text not null default 'CLP' check (currency ~ '^[A-Z]{3}$'),
  status text not null default 'active' check (status in ('active','inactive')),
  version integer not null default 1 check (version > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.profiles (
  user_id uuid primary key references auth.users(id) on delete restrict,
  display_name text not null check (length(display_name) between 2 and 100),
  locale text not null default 'es-CL' check (locale in ('es-CL','en')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.user_company_memberships (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete restrict,
  role_code text not null references public.roles(code),
  status text not null default 'active' check (status in ('active','inactive')),
  valid_from timestamptz not null default now(),
  valid_until timestamptz,
  version integer not null default 1 check (version > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (company_id,user_id),
  unique (company_id,id),
  check (valid_until is null or valid_until > valid_from)
);
-- Núcleo de vínculo laboral para comprobar privacidad A/B. Sin CRUD de Fase 2.
create table public.employees (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete restrict,
  user_id uuid references auth.users(id) on delete restrict,
  display_name text not null check (length(display_name) between 2 and 100),
  status text not null default 'active' check (status in ('active','inactive')),
  created_at timestamptz not null default now(),
  unique (company_id,id)
);
create unique index employees_one_identity_per_company on public.employees(company_id,user_id) where user_id is not null;
create table public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete restrict,
  actor_user_id uuid references auth.users(id) on delete restrict,
  action text not null,
  entity_type text not null,
  entity_id uuid not null,
  reason text,
  changed_fields jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp()
);
create table private.auth_rate_limits (
  bucket text primary key,
  window_start timestamptz not null,
  attempts integer not null
);

create index memberships_user_scope on public.user_company_memberships(user_id,status,company_id);
create index memberships_company on public.user_company_memberships(company_id,status);
create index employees_identity on public.employees(user_id,company_id);
create index audit_company_time on public.audit_logs(company_id,created_at desc,id);

insert into public.roles values
('ADMIN_GLOBAL','Administración de empresas asignadas'),
('COMPANY_ADMIN','Administración de empresa asignada'),
('HR','Administración de personas'),('SUPERVISOR','Supervisión asignada'),('EMPLOYEE','Acceso personal');
insert into public.permissions values
('company.read','Leer contexto de empresa'),
('membership.read_company','Leer accesos de empresa'),
('employee.read_company','Leer núcleo laboral de empresa'),
('audit.read_company','Leer auditoría de empresa'),
('dashboard.consolidated.read','Leer empresas consolidadas autorizadas');
insert into public.role_permissions
select r.code,p.code from public.roles r cross join public.permissions p
where p.code='company.read'
or (r.code in ('ADMIN_GLOBAL','COMPANY_ADMIN','HR') and p.code in ('membership.read_company','employee.read_company'))
or (r.code in ('ADMIN_GLOBAL','COMPANY_ADMIN') and p.code='audit.read_company')
or (r.code='ADMIN_GLOBAL' and p.code='dashboard.consolidated.read');

create function private.is_member(p_company uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.user_company_memberships m join public.companies c on c.id=m.company_id
    where m.company_id=p_company and m.user_id=(select auth.uid())
      and m.status='active' and c.status='active'
      and m.valid_from<=now() and (m.valid_until is null or m.valid_until>now())
  );
$$;
create function private.has_permission(p_company uuid,p_permission text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.user_company_memberships m
    join public.companies c on c.id=m.company_id
    join public.role_permissions rp on rp.role_code=m.role_code
    where m.company_id=p_company and m.user_id=(select auth.uid())
      and m.status='active' and c.status='active'
      and m.valid_from<=now() and (m.valid_until is null or m.valid_until>now())
      and rp.permission_code=p_permission
  );
$$;
revoke all on function private.is_member(uuid),private.has_permission(uuid,text) from public,anon,authenticated;
grant usage on schema private to authenticated;
grant execute on function private.is_member(uuid),private.has_permission(uuid,text) to authenticated;

create function private.validate_company() returns trigger
language plpgsql set search_path = '' as $$
begin
  if not exists(select 1 from pg_catalog.pg_timezone_names where name=new.timezone) then
    raise exception 'INVALID_TIMEZONE' using errcode='22023';
  end if;
  if tg_op='UPDATE' then
    if new.id<>old.id then raise exception 'IMMUTABLE_ID'; end if;
    new.version:=old.version+1;
    new.updated_at:=clock_timestamp();
  end if;
  return new;
end;
$$;
create trigger validate_company before insert or update on public.companies
for each row execute function private.validate_company();

create function private.audit_foundation_change() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_company uuid; v_id uuid; v_before jsonb; v_after jsonb;
begin
  if tg_table_name='companies' then
    v_company:=new.id; v_id:=new.id;
    v_after:=jsonb_build_object('status',new.status,'version',new.version);
    if tg_op='UPDATE' then v_before:=jsonb_build_object('status',old.status,'version',old.version); end if;
  else
    v_company:=new.company_id; v_id:=new.id;
    v_after:=jsonb_build_object('role_code',new.role_code,'status',new.status,'version',new.version);
    if tg_op='UPDATE' then v_before:=jsonb_build_object('role_code',old.role_code,'status',old.status,'version',old.version); end if;
  end if;
  insert into public.audit_logs(company_id,actor_user_id,action,entity_type,entity_id,reason,changed_fields)
  values(v_company,auth.uid(),lower(tg_op),tg_table_name,v_id,
    nullif(current_setting('app.audit_reason',true),''),jsonb_build_object('before',v_before,'after',v_after));
  return new;
end;
$$;
revoke all on function private.validate_company(),private.audit_foundation_change() from public,anon,authenticated;
create trigger audit_company_change after insert or update on public.companies for each row execute function private.audit_foundation_change();
create trigger audit_membership_change after insert or update on public.user_company_memberships for each row execute function private.audit_foundation_change();

create function public.take_auth_attempt(p_bucket text) returns boolean
language plpgsql security definer set search_path = '' as $$
declare v_attempts integer;
begin
  if p_bucket !~ '^[a-f0-9]{64}$' then raise exception 'INVALID_BUCKET'; end if;
  -- Shared, fixed 15-minute window. Concurrent upsert serializes per bucket.
  insert into private.auth_rate_limits(bucket,window_start,attempts) values(p_bucket,clock_timestamp(),1)
  on conflict(bucket) do update set
    attempts=case when private.auth_rate_limits.window_start<clock_timestamp()-interval '15 minutes' then 1 else private.auth_rate_limits.attempts+1 end,
    window_start=case when private.auth_rate_limits.window_start<clock_timestamp()-interval '15 minutes' then clock_timestamp() else private.auth_rate_limits.window_start end
  returning attempts into v_attempts;
  delete from private.auth_rate_limits where window_start<clock_timestamp()-interval '1 day';
  return v_attempts<=5;
end;
$$;
revoke all on function public.take_auth_attempt(text) from public,anon,authenticated;
grant execute on function public.take_auth_attempt(text) to service_role;

alter table public.companies enable row level security;
alter table public.profiles enable row level security;
alter table public.user_company_memberships enable row level security;
alter table public.employees enable row level security;
alter table public.roles enable row level security;
alter table public.permissions enable row level security;
alter table public.role_permissions enable row level security;
alter table public.audit_logs enable row level security;

revoke all on public.companies,public.profiles,public.user_company_memberships,public.employees,public.roles,public.permissions,public.role_permissions,public.audit_logs from anon,authenticated;
grant select on public.companies,public.profiles,public.user_company_memberships,public.employees,public.roles,public.permissions,public.role_permissions,public.audit_logs to authenticated;
grant update(display_name,locale) on public.profiles to authenticated;
grant all on public.companies,public.profiles,public.user_company_memberships,public.employees,public.roles,public.permissions,public.role_permissions,public.audit_logs to service_role;

create policy companies_select on public.companies for select to authenticated using(private.is_member(id));
create policy profiles_select on public.profiles for select to authenticated using(user_id=(select auth.uid()));
create policy profiles_update on public.profiles for update to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()));
create policy memberships_select on public.user_company_memberships for select to authenticated
using(private.is_member(company_id) and (user_id=(select auth.uid()) or private.has_permission(company_id,'membership.read_company')));
create policy employees_select on public.employees for select to authenticated
using(private.is_member(company_id) and (user_id=(select auth.uid()) or private.has_permission(company_id,'employee.read_company')));
create policy roles_select on public.roles for select to authenticated using(true);
create policy permissions_select on public.permissions for select to authenticated using(true);
create policy role_permissions_select on public.role_permissions for select to authenticated using(true);
create policy audit_select on public.audit_logs for select to authenticated using(private.has_permission(company_id,'audit.read_company'));

comment on table public.employees is 'Access-to-employment identity kernel only. Business CRUD deferred to Phase 2.';
comment on table public.audit_logs is 'Application append-only; generated transactionally by internal triggers; infrastructure admins remain privileged.';
commit;

begin;
-- Authority explicitly approved by the user: only scoped ADMIN_GLOBAL mutations.
insert into public.permissions values ('membership.manage','Cambiar roles y estado dentro de empresa asignada'),('company.deactivate','Desactivar empresa asignada');
insert into public.role_permissions values ('ADMIN_GLOBAL','membership.manage'),('ADMIN_GLOBAL','company.deactivate');

create function public.change_membership(p_company uuid,p_membership uuid,p_role text,p_status text,p_version integer,p_reason text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_target public.user_company_memberships;
begin
  if auth.uid() is null or not private.has_permission(p_company,'membership.manage') then
    raise exception 'ACCESS_DENIED' using errcode='42501';
  end if;
  if length(trim(p_reason))<5 or length(p_reason)>500 or p_reason is null then raise exception 'REASON_REQUIRED' using errcode='22023'; end if;
  if p_status not in ('active','inactive') or p_status is null or not exists(select 1 from public.roles where code=p_role) then raise exception 'INVALID_INPUT' using errcode='22023'; end if;
  -- Shared company lock serializes administration and protects the last admin.
  perform 1 from public.companies where id=p_company for update;
  -- Recheck permission after waiting for lock; another transaction may suspend actor.
  if not private.has_permission(p_company,'membership.manage') then raise exception 'ACCESS_DENIED' using errcode='42501'; end if;
  select * into v_target from public.user_company_memberships where company_id=p_company and id=p_membership for update;
  if not found then raise exception 'ACCESS_DENIED' using errcode='42501'; end if;
  if p_version<>v_target.version or p_version is null then raise exception 'VERSION_CONFLICT' using errcode='40001'; end if;
  if v_target.role_code='ADMIN_GLOBAL' and v_target.status='active' and (p_role<>'ADMIN_GLOBAL' or p_status<>'active') then
    if not exists(select 1 from public.user_company_memberships where company_id=p_company and id<>p_membership and role_code='ADMIN_GLOBAL' and status='active' and valid_from<=now() and (valid_until is null or valid_until>now())) then
      raise exception 'LAST_ADMIN_REQUIRED' using errcode='23514';
    end if;
  end if;
  perform set_config('app.audit_reason',trim(p_reason),true);
  update public.user_company_memberships set role_code=p_role,status=p_status,version=version+1,updated_at=clock_timestamp() where company_id=p_company and id=p_membership;
end;
$$;
create function public.deactivate_company(p_company uuid,p_version integer,p_reason text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or not private.has_permission(p_company,'company.deactivate') then raise exception 'ACCESS_DENIED' using errcode='42501'; end if;
  if p_reason is null or length(trim(p_reason))<5 or length(p_reason)>500 then raise exception 'REASON_REQUIRED' using errcode='22023'; end if;
  perform 1 from public.companies where id=p_company for update;
  if not private.has_permission(p_company,'company.deactivate') then raise exception 'ACCESS_DENIED' using errcode='42501'; end if;
  perform set_config('app.audit_reason',trim(p_reason),true);
  update public.companies set status='inactive' where id=p_company and version=p_version;
  if not found then raise exception 'VERSION_CONFLICT' using errcode='40001'; end if;
end;
$$;
revoke all on function public.change_membership(uuid,uuid,text,text,integer,text),public.deactivate_company(uuid,integer,text) from public,anon;
grant execute on function public.change_membership(uuid,uuid,text,text,integer,text),public.deactivate_company(uuid,integer,text) to authenticated;
commit;

begin;

-- Defense in depth: no client may access the internal limiter table directly.
-- The service-role-only SECURITY DEFINER RPC operates as its owner.
alter table private.auth_rate_limits enable row level security;
revoke all on private.auth_rate_limits from public, anon, authenticated;

commit;

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

begin;
alter table public.employees add constraint employee_job_title_length check(length(job_title)<=120);
create function public.end_workforce_history(p_company uuid,p_kind text,p_id uuid,p_version integer,p_ends_on date,p_reason text) returns void language plpgsql security definer set search_path='' as $$
declare t text; start_date date; end_date date; current_version integer;
begin
 if not private.has_permission(p_company,'workforce.manage') then raise exception 'ACCESS_DENIED' using errcode='42501';end if;
 if p_reason is null or length(trim(p_reason)) not between 5 and 500 or p_ends_on is null then raise exception 'INVALID_INPUT' using errcode='22023';end if;
 t:=case p_kind when 'contract' then 'employee_contracts' when 'project_assignment' then 'employee_project_assignments' when 'supervisor_assignment' then 'employee_supervisor_assignments' else null end;
 if t is null then raise exception 'INVALID_KIND' using errcode='22023';end if;
 execute format('select starts_on,ends_on,version from public.%I where company_id=$1 and id=$2 for update',t) into start_date,end_date,current_version using p_company,p_id;
 if current_version is null then raise exception 'ACCESS_DENIED' using errcode='42501';end if;
 if current_version<>p_version then raise exception 'STALE_VERSION' using errcode='40001';end if;
 if end_date is not null or p_ends_on<start_date then raise exception 'HISTORY_IMMUTABLE' using errcode='23514';end if;
 perform set_config('app.audit_reason',trim(p_reason),true);
 execute format('update public.%I set ends_on=$1,version=version+1 where company_id=$2 and id=$3',t) using p_ends_on,p_company,p_id;
end; $$;
revoke all on function public.end_workforce_history(uuid,text,uuid,integer,date,text) from public,anon;
grant execute on function public.end_workforce_history(uuid,text,uuid,integer,date,text) to authenticated;
commit;

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

begin;
insert into public.permissions values ('novelty.manage','Revisar novedades y registrar pagos'),('payroll.manage','Administrar estimaciones y cierres') on conflict do nothing;
insert into public.role_permissions select r.code,p.code from public.roles r cross join public.permissions p where r.code in ('ADMIN_GLOBAL','COMPANY_ADMIN','HR') and p.code in ('novelty.manage','payroll.manage') on conflict do nothing;

create table public.payroll_periods (
 id uuid primary key default gen_random_uuid(),company_id uuid not null references public.companies(id),month date not null,
 state text not null default 'OPEN' check(state in ('OPEN','REVIEW','CLOSED','PAID')),cutoff_at timestamptz,
 version integer not null default 1,close_revision integer not null default 0,closed_at timestamptz,paid_at timestamptz,
 unique(company_id,id),unique(company_id,month),check(extract(day from month)=1)
);
create table public.expense_categories (
 id uuid primary key default gen_random_uuid(),company_id uuid not null references public.companies(id),name text not null check(length(name) between 2 and 100),status text not null default 'active' check(status in ('active','inactive')),
 unique(company_id,id),unique(company_id,name)
);
create table public.novelties (
 id uuid primary key default gen_random_uuid(),company_id uuid not null references public.companies(id),employee_id uuid not null,period_id uuid not null,project_id uuid,
 kind text not null check(kind in ('OVERTIME','EXPENSE','REIMBURSEMENT','ADVANCE','ALLOWANCE','LEAVE','ABSENCE','OTHER')),
 status text not null check(status in ('DRAFT','SUBMITTED','PENDING_REVIEW','APPROVED','PARTIALLY_APPROVED','REJECTED','PAID','CANCELLED','DEDUCTED')),
 occurs_on date not null,ends_on date,starts_at timestamptz,ends_at timestamptz,
 requested_amount bigint not null default 0 check(requested_amount between 0 and 100000000000),approved_amount bigint not null default 0 check(approved_amount between 0 and requested_amount),paid_amount bigint not null default 0 check(paid_amount between 0 and approved_amount),
 requested_minutes integer not null default 0 check(requested_minutes between 0 and 10080),detected_minutes integer,approved_minutes integer not null default 0 check(approved_minutes between 0 and requested_minutes),
 category_id uuid,vendor text not null default '' check(length(vendor)<=160),description text not null check(length(description) between 5 and 2000),
 reimbursement_channel text not null default 'PAYROLL' check(reimbursement_channel in ('PAYROLL','DIRECT_PAYMENT')),
 created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),approved_by uuid references auth.users(id),approved_at timestamptz,version integer not null default 1,
 unique(company_id,id),foreign key(company_id,employee_id) references public.employees(company_id,id),foreign key(company_id,period_id) references public.payroll_periods(company_id,id),foreign key(company_id,project_id) references public.projects(company_id,id),foreign key(company_id,category_id) references public.expense_categories(company_id,id),
 check(ends_on is null or ends_on>=occurs_on),check(ends_at is null or (starts_at is not null and ends_at>starts_at)),
 check((kind='OVERTIME' and requested_minutes>0 and requested_amount=0 and starts_at is not null and ends_at is not null) or (kind in ('EXPENSE','REIMBURSEMENT','ADVANCE','ALLOWANCE') and requested_amount>0 and requested_minutes=0) or (kind in ('LEAVE','ABSENCE','OTHER') and requested_amount=0 and requested_minutes=0))
);
create table public.novelty_comments (
 id uuid primary key default gen_random_uuid(),company_id uuid not null references public.companies(id),novelty_id uuid not null,
 author_id uuid not null references auth.users(id),body text not null check(length(body) between 1 and 2000),created_at timestamptz not null default clock_timestamp(),
 foreign key(company_id,novelty_id) references public.novelties(company_id,id)
);
create table public.novelty_payments (
 id uuid primary key default gen_random_uuid(),company_id uuid not null references public.companies(id),novelty_id uuid not null,client_id uuid not null,
 amount bigint not null check(amount between 1 and 100000000000),payment_method text not null check(length(payment_method) between 2 and 80),reference text not null default '' check(length(reference)<=160),reason text not null check(length(reason) between 5 and 500),
 paid_by uuid not null references auth.users(id),paid_at timestamptz not null default clock_timestamp(),request_payload jsonb not null,
 foreign key(company_id,novelty_id) references public.novelties(company_id,id),unique(company_id,client_id)
);
create index novelty_employee_period on public.novelties(company_id,employee_id,period_id,status);
create index novelty_company_pending on public.novelties(company_id,status,occurs_on);
create index novelty_comments_record on public.novelty_comments(company_id,novelty_id,created_at);
create index novelty_payments_record on public.novelty_payments(company_id,novelty_id);

create function private.can_read_novelty(p_company uuid,p_employee uuid,p_kind text) returns boolean language sql stable security definer set search_path='' as $$
 select private.is_member(p_company) and (private.has_permission(p_company,'novelty.manage') or exists(select 1 from public.employees e where e.company_id=p_company and e.id=p_employee and e.user_id=auth.uid()) or (p_kind in ('OVERTIME','LEAVE','ABSENCE','OTHER') and private.can_read_employee(p_company,p_employee)));
$$;
revoke all on function private.can_read_novelty(uuid,uuid,text) from public,anon;
grant execute on function private.can_read_novelty(uuid,uuid,text) to authenticated;
alter table public.payroll_periods enable row level security;
alter table public.expense_categories enable row level security;
alter table public.novelties enable row level security;
alter table public.novelty_comments enable row level security;
alter table public.novelty_payments enable row level security;
create policy periods_read on public.payroll_periods for select to authenticated using(private.is_member(company_id));
create policy categories_read on public.expense_categories for select to authenticated using(private.is_member(company_id));
create policy novelties_read on public.novelties for select to authenticated using(private.can_read_novelty(company_id,employee_id,kind));
create policy comments_read on public.novelty_comments for select to authenticated using(exists(select 1 from public.novelties n where n.company_id=novelty_comments.company_id and n.id=novelty_id and private.can_read_novelty(n.company_id,n.employee_id,n.kind)));
create policy payments_read on public.novelty_payments for select to authenticated using(exists(select 1 from public.novelties n where n.company_id=novelty_payments.company_id and n.id=novelty_id and private.can_read_novelty(n.company_id,n.employee_id,n.kind)));
revoke all on public.payroll_periods,public.expense_categories,public.novelties,public.novelty_comments,public.novelty_payments from public,anon,authenticated;
grant select on public.payroll_periods,public.expense_categories,public.novelties,public.novelty_comments,public.novelty_payments to authenticated;
grant all on public.payroll_periods,public.expense_categories,public.novelties,public.novelty_comments,public.novelty_payments to service_role;
create trigger novelty_payment_immutable before update or delete on public.novelty_payments for each row execute function private.attendance_immutable();
create trigger novelty_comment_immutable before update or delete on public.novelty_comments for each row execute function private.attendance_immutable();

create function private.require_open_period(p_company uuid,p_period uuid) returns void language plpgsql security definer set search_path='' as $$
declare state text;
begin
 select p.state into state from public.payroll_periods p where p.company_id=p_company and p.id=p_period for share;
 if state is null then raise exception 'DENIED' using errcode='42501'; end if;
 if state in ('CLOSED','PAID') then raise exception 'PERIOD_LOCKED' using errcode='23514'; end if;
end; $$;
revoke all on function private.require_open_period(uuid,uuid) from public,anon,authenticated;

-- Company row locks serialize closure against every business write, then period/employee rows.
create function public.create_novelty(p_company uuid,p_data jsonb,p_draft boolean default false) returns uuid language plpgsql security definer set search_path='' as $$
declare employee public.employees; period public.payroll_periods; result uuid; date_value date:=(p_data->>'occurs_on')::date; project uuid:=nullif(p_data->>'project_id','')::uuid; employee_id uuid:=nullif(p_data->>'employee_id','')::uuid;
begin
 if not private.is_member(p_company) then raise exception 'DENIED' using errcode='42501'; end if;
 perform 1 from public.companies where id=p_company and status='active' for update;
 if employee_id is null then select * into employee from public.employees e where e.company_id=p_company and e.user_id=auth.uid() and e.status='active';
 else select * into employee from public.employees e where e.company_id=p_company and e.id=employee_id and e.status='active'; end if;
 if employee.id is null or not private.is_member(p_company) or not (coalesce(employee.user_id=auth.uid(),false) or private.has_permission(p_company,'novelty.manage')) then raise exception 'DENIED' using errcode='42501'; end if;
 if date_value is null or p_draft is null or pg_column_size(p_data)>8000 then raise exception 'INVALID_NOVELTY' using errcode='22023'; end if;
 insert into public.payroll_periods(company_id,month) values(p_company,date_trunc('month',date_value)::date) on conflict(company_id,month) do nothing;
 select * into period from public.payroll_periods where company_id=p_company and month=date_trunc('month',date_value)::date for share;
 perform private.require_open_period(p_company,period.id);
 if period.state='REVIEW' and not private.has_permission(p_company,'novelty.manage') then raise exception 'PERIOD_IN_REVIEW' using errcode='23514'; end if;
 if period.cutoff_at is not null and clock_timestamp()>period.cutoff_at and not private.has_permission(p_company,'novelty.manage') then raise exception 'CUTOFF_PASSED' using errcode='23514'; end if;
 if project is not null and not (private.has_permission(p_company,'novelty.manage') or exists(select 1 from public.employee_project_assignments a where a.company_id=p_company and a.employee_id=employee.id and a.project_id=project and a.status='active' and a.starts_on<=date_value and (a.ends_on is null or a.ends_on>=date_value))) then raise exception 'PROJECT_NOT_ASSIGNED' using errcode='42501'; end if;
 insert into public.novelties(company_id,employee_id,period_id,project_id,kind,status,occurs_on,ends_on,starts_at,ends_at,requested_amount,requested_minutes,category_id,vendor,description,reimbursement_channel,created_by)
 values(p_company,employee.id,period.id,project,p_data->>'kind',case when p_draft then 'DRAFT' else 'SUBMITTED' end,date_value,nullif(p_data->>'ends_on','')::date,nullif(p_data->>'starts_at','')::timestamptz,nullif(p_data->>'ends_at','')::timestamptz,coalesce(nullif(p_data->>'requested_amount','')::bigint,0),coalesce(nullif(p_data->>'requested_minutes','')::integer,0),nullif(p_data->>'category_id','')::uuid,coalesce(p_data->>'vendor',''),p_data->>'description',coalesce(nullif(p_data->>'reimbursement_channel',''),'PAYROLL'),auth.uid()) returning id into result;
 update public.payroll_periods set version=version+1 where id=period.id;
 insert into public.audit_logs(company_id,actor_user_id,action,entity_type,entity_id) values(p_company,auth.uid(),'novelty.create','novelties',result);
 return result;
end; $$;
create function public.transition_novelty(p_company uuid,p_id uuid,p_version integer,p_action text,p_data jsonb,p_reason text) returns void language plpgsql security definer set search_path='' as $$
declare record public.novelties; requested_by_self boolean; amount bigint; minutes integer; next_status text;
begin
 if not private.is_member(p_company) then raise exception 'DENIED' using errcode='42501'; end if;
 perform 1 from public.companies where id=p_company and status='active' for update;
 select * into record from public.novelties where company_id=p_company and id=p_id;
 if record.id is null then raise exception 'DENIED' using errcode='42501'; end if;
 perform private.require_open_period(p_company,record.period_id);
 select * into record from public.novelties where id=p_id for update;
 requested_by_self:=record.created_by=auth.uid() or exists(select 1 from public.employees e where e.company_id=p_company and e.id=record.employee_id and e.user_id=auth.uid());
 if not (private.has_permission(p_company,'novelty.manage') or requested_by_self) then raise exception 'DENIED' using errcode='42501'; end if;
 if p_version is null or record.version<>p_version then raise exception 'STALE_VERSION' using errcode='40001'; end if;
 if p_reason is null or length(trim(p_reason)) not between 5 and 500 then raise exception 'REASON_REQUIRED' using errcode='22023'; end if;
 if p_action='submit' and requested_by_self and record.status='DRAFT' then next_status:='SUBMITTED';
 elsif p_action='cancel' and requested_by_self and record.status in ('DRAFT','SUBMITTED') then next_status:='CANCELLED';
 elsif p_action='start_review' and private.has_permission(p_company,'novelty.manage') and not requested_by_self and record.status='SUBMITTED' then next_status:='PENDING_REVIEW';
 elsif p_action in ('approve','reject') and private.has_permission(p_company,'novelty.manage') and not requested_by_self and record.status='PENDING_REVIEW' then
  if p_action='reject' then next_status:='REJECTED';
  else amount:=coalesce(nullif(p_data->>'approved_amount','')::bigint,0);minutes:=coalesce(nullif(p_data->>'approved_minutes','')::integer,0);
   if amount<0 or amount>record.requested_amount or minutes<0 or minutes>record.requested_minutes or (record.kind='OVERTIME' and minutes=0) or (record.kind in ('EXPENSE','REIMBURSEMENT','ADVANCE','ALLOWANCE') and amount=0) then raise exception 'INVALID_APPROVAL' using errcode='23514'; end if;
   next_status:=case when amount<record.requested_amount or minutes<record.requested_minutes then 'PARTIALLY_APPROVED' else 'APPROVED' end;
  end if;
 else raise exception 'INVALID_TRANSITION' using errcode='23514'; end if;
 update public.novelties set status=next_status,approved_amount=coalesce(amount,approved_amount),approved_minutes=coalesce(minutes,approved_minutes),approved_by=case when p_action in ('approve','reject') then auth.uid() else approved_by end,approved_at=case when p_action in ('approve','reject') then clock_timestamp() else approved_at end,version=version+1 where id=p_id;
 update public.payroll_periods set version=version+1 where id=record.period_id;
 insert into public.novelty_comments(company_id,novelty_id,author_id,body) values(p_company,p_id,auth.uid(),trim(p_reason));
 insert into public.audit_logs(company_id,actor_user_id,action,entity_type,entity_id,reason,changed_fields) values(p_company,auth.uid(),'novelty.'||p_action,'novelties',p_id,trim(p_reason),jsonb_build_object('before',record.status,'after',next_status));
end; $$;
create function public.add_novelty_comment(p_company uuid,p_id uuid,p_body text) returns void language plpgsql security definer set search_path='' as $$
declare record public.novelties;
begin
 select * into record from public.novelties where company_id=p_company and id=p_id;
 if record.id is null or not private.can_read_novelty(p_company,record.employee_id,record.kind) then raise exception 'DENIED' using errcode='42501'; end if;
 if p_body is null or length(trim(p_body)) not between 1 and 2000 then raise exception 'INVALID_COMMENT' using errcode='22023'; end if;
 insert into public.novelty_comments(company_id,novelty_id,author_id,body) values(p_company,p_id,auth.uid(),trim(p_body));
 insert into public.audit_logs(company_id,actor_user_id,action,entity_type,entity_id) values(p_company,auth.uid(),'novelty.comment','novelties',p_id);
end; $$;
create function public.record_novelty_payment(p_company uuid,p_id uuid,p_client_id uuid,p_data jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare record public.novelties; payment public.novelty_payments; amount bigint:=nullif(p_data->>'amount','')::bigint; result uuid;
begin
 if not private.has_permission(p_company,'novelty.manage') then raise exception 'DENIED' using errcode='42501'; end if;
 perform 1 from public.companies where id=p_company and status='active' for update;
 select * into record from public.novelties where company_id=p_company and id=p_id;
 if record.id is null then raise exception 'DENIED' using errcode='42501'; end if;
 perform private.require_open_period(p_company,record.period_id);
 select * into record from public.novelties where id=p_id for update;
 select * into payment from public.novelty_payments where company_id=p_company and client_id=p_client_id;
 if payment.id is not null then if payment.novelty_id<>p_id or payment.request_payload<>p_data then raise exception 'IDEMPOTENCY_CONFLICT' using errcode='23505'; end if;return payment.id; end if;
 if record.kind not in ('ADVANCE','EXPENSE','REIMBURSEMENT','ALLOWANCE') or (record.kind in ('EXPENSE','REIMBURSEMENT','ALLOWANCE') and record.reimbursement_channel<>'DIRECT_PAYMENT') or record.status not in ('APPROVED','PARTIALLY_APPROVED') or record.created_by=auth.uid() or exists(select 1 from public.employees where id=record.employee_id and user_id=auth.uid()) or amount is null or amount<=0 or record.paid_amount+amount>record.approved_amount then raise exception 'INVALID_PAYMENT' using errcode='23514'; end if;
 insert into public.novelty_payments(company_id,novelty_id,client_id,amount,payment_method,reference,reason,paid_by,request_payload) values(p_company,p_id,p_client_id,amount,p_data->>'payment_method',coalesce(p_data->>'reference',''),p_data->>'reason',auth.uid(),p_data) returning id into result;
 update public.novelties set paid_amount=paid_amount+amount,status=case when paid_amount+amount=approved_amount then 'PAID' else status end,version=version+1 where id=p_id;
 update public.payroll_periods set version=version+1 where id=record.period_id;
 insert into public.audit_logs(company_id,actor_user_id,action,entity_type,entity_id,reason) values(p_company,auth.uid(),'novelty.payment.record','novelty_payments',result,p_data->>'reason');
 return result;
end; $$;
create function public.save_expense_category(p_company uuid,p_name text) returns uuid language plpgsql security definer set search_path='' as $$
declare result uuid;
begin
 if not private.has_permission(p_company,'novelty.manage') then raise exception 'DENIED' using errcode='42501'; end if;
 insert into public.expense_categories(company_id,name) values(p_company,trim(p_name)) returning id into result;
 insert into public.audit_logs(company_id,actor_user_id,action,entity_type,entity_id) values(p_company,auth.uid(),'expense.category.create','expense_categories',result);return result;
end; $$;
revoke all on function public.create_novelty(uuid,jsonb,boolean),public.transition_novelty(uuid,uuid,integer,text,jsonb,text),public.add_novelty_comment(uuid,uuid,text),public.record_novelty_payment(uuid,uuid,uuid,jsonb),public.save_expense_category(uuid,text) from public,anon;
grant execute on function public.create_novelty(uuid,jsonb,boolean),public.transition_novelty(uuid,uuid,integer,text,jsonb,text),public.add_novelty_comment(uuid,uuid,text),public.record_novelty_payment(uuid,uuid,uuid,jsonb),public.save_expense_category(uuid,text) to authenticated;
commit;


-- Fictional development records only. Never apply this seed to production.
insert into public.companies(id,code,legal_name,display_name)
values ('10000000-0000-4000-8000-000000000001','SUACOF','SUACOF Solutions SpA','SUACOF Solutions'),
       ('10000000-0000-4000-8000-000000000002','CLOUD9','CLOUD 9 SpA','CLOUD 9')
on conflict(code) do nothing;
