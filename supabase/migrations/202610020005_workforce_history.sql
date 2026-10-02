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
