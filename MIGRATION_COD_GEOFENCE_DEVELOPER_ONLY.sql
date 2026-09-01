-- =============================================================================
-- Cash-on-delivery geofence settings (cod_geofence_enabled, cod_center_lat,
-- cod_center_lng, cod_radius_m — all inside app_config.bill_config) may only
-- be changed by the 'developer' role. Everyone who already passes
-- is_sub_manager() (admin, developer, sub_manager) can still write the rest
-- of bill_config (business name, GST, delivery charge, footer) — this only
-- blocks changes to the four COD fields specifically.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.enforce_cod_geofence_developer_only()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  cod_keys text[] := ARRAY[
    'cod_geofence_enabled', 'cod_center_lat', 'cod_center_lng', 'cod_radius_m'
  ];
  k text;
  old_cod jsonb := '{}'::jsonb;
  new_cod jsonb := '{}'::jsonb;
BEGIN
  IF NEW.key <> 'bill_config' THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    FOREACH k IN ARRAY cod_keys LOOP
      old_cod := old_cod || jsonb_build_object(k, OLD.value -> k);
    END LOOP;
  END IF;
  FOREACH k IN ARRAY cod_keys LOOP
    new_cod := new_cod || jsonb_build_object(k, NEW.value -> k);
  END LOOP;

  IF old_cod IS DISTINCT FROM new_cod THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'developer'
    ) THEN
      RAISE EXCEPTION 'Only the developer role can change cash-on-delivery geofence settings';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_cod_geofence_developer_only ON public.app_config;
CREATE TRIGGER trg_cod_geofence_developer_only
  BEFORE INSERT OR UPDATE ON public.app_config
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_cod_geofence_developer_only();
