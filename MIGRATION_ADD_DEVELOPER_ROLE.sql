-- =============================================================================
-- ADD 'developer' ROLE — gets everything 'admin' currently gets (same RLS
-- grants across gym + subscription models), and 'admin' loses the app-level
-- Settings menu item (client-side only; not an RLS change).
-- =============================================================================

-- 1. Allow 'developer' as a valid profiles.role value.
ALTER TABLE public.profiles DROP CONSTRAINT profiles_role_check;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_role_check
  CHECK (role IS NULL OR role = ANY (ARRAY[
    'admin','developer','gym_manager','sub_manager','gym_chef','gym_delivery',
    'subs_chef','subs_delivery','member','user','gold_member'
  ]));

-- 2. Role-check helpers: everywhere 'admin' passes, 'developer' now passes
--    too (is_admin() itself, plus every function that special-cases admin).
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role IN ('admin','developer')
  );
$$;

CREATE OR REPLACE FUNCTION public.is_gym_manager()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role IN ('admin','developer','gym_manager')
  );
$$;

CREATE OR REPLACE FUNCTION public.is_sub_manager()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role IN ('admin','developer','sub_manager')
  );
$$;

CREATE OR REPLACE FUNCTION public.is_sub_staff()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role IN ('admin','developer','sub_manager','chef','delivery')
  );
$$;
