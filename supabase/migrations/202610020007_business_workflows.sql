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

