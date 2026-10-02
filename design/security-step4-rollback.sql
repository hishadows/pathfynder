-- Rollback for migration sec_lock_match_passenger_to_drivers (2026-10-02)
-- ACL before: {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}
GRANT EXECUTE ON FUNCTION public.match_passenger_to_drivers(uuid) TO PUBLIC, anon, authenticated, service_role;
