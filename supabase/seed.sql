-- Fictional development records only. Never apply this seed to production.
insert into public.companies(id,code,legal_name,display_name)
values ('10000000-0000-4000-8000-000000000001','SUACOF','SUACOF Solutions SpA','SUACOF Solutions'),
       ('10000000-0000-4000-8000-000000000002','CLOUD9','CLOUD 9 SpA','CLOUD 9')
on conflict(code) do nothing;
