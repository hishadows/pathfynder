-- Rollback for migration sec_step3_lock_tg_tables (NOT applied automatically)
-- Captured 2026-10-02. Tables owned by postgres, RLS enabled, not forced. No column-level ACLs existed.

-- driver_routines
CREATE POLICY allow_insert ON public.driver_routines AS PERMISSIVE FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY anon_read_driver_routines ON public.driver_routines AS PERMISSIVE FOR SELECT TO anon USING (true);
CREATE POLICY anon_update_driver_routines ON public.driver_routines AS PERMISSIVE FOR UPDATE TO anon USING (true);
-- passenger_requests
CREATE POLICY allow_insert ON public.passenger_requests AS PERMISSIVE FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY anon_delete_passenger_requests ON public.passenger_requests AS PERMISSIVE FOR DELETE TO anon USING (true);
CREATE POLICY anon_insert_passenger_requests ON public.passenger_requests AS PERMISSIVE FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY anon_read_passenger_requests ON public.passenger_requests AS PERMISSIVE FOR SELECT TO anon USING (true);
CREATE POLICY anon_update_passenger_requests ON public.passenger_requests AS PERMISSIVE FOR UPDATE TO anon USING (true);
-- telegram_users
CREATE POLICY allow_insert ON public.telegram_users AS PERMISSIVE FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY allow_select ON public.telegram_users AS PERMISSIVE FOR SELECT TO anon USING (true);
CREATE POLICY allow_update ON public.telegram_users AS PERMISSIVE FOR UPDATE TO anon USING (true) WITH CHECK (true);

-- table grants (arwdDxtm)
GRANT ALL ON public.driver_routines, public.passenger_requests, public.telegram_users TO anon, authenticated;

-- function execute (original ACL: PUBLIC, postgres, anon, authenticated, service_role)
GRANT EXECUTE ON FUNCTION public.match_passenger_to_driver(uuid) TO PUBLIC, anon, authenticated, service_role;
