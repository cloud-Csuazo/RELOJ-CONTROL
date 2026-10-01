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
