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
