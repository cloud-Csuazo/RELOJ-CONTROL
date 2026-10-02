begin;

-- Defense in depth: no client may access the internal limiter table directly.
-- The service-role-only SECURITY DEFINER RPC operates as its owner.
alter table private.auth_rate_limits enable row level security;
revoke all on private.auth_rate_limits from public, anon, authenticated;

commit;
