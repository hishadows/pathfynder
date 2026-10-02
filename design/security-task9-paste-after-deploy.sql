-- security task 9, part 3: run ONLY AFTER the new HQ (hq_check / p_pass) is deployed and live.
-- The live HQ still calls the old get_feed / get_power_users until it is redeployed.
DROP FUNCTION public.get_feed(timestamptz, timestamptz, text, text, integer, integer);
DROP FUNCTION public.get_power_users(timestamptz, timestamptz, text, integer);
DROP POLICY anon_read_extracted ON public.extracted_data_01;
DROP POLICY anon_read_extracted_data_01 ON public.extracted_data_01;
