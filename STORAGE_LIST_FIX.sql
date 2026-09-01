-- =============================================================================
-- L1 fix: stop anonymous enumeration (LIST) of the menu-images bucket.
--
-- The bucket is PUBLIC, so individual images are served via their public URLs
-- (/storage/v1/object/public/menu-images/...) WITHOUT needing an RLS policy —
-- verified returning HTTP 200. The only thing the public SELECT policy enabled
-- was LISTing the bucket (enumerating filenames/metadata). We drop it, and add
-- an admin-only SELECT so staff can still browse the bucket if needed.
--
-- Result: images still display everywhere; anon can no longer list the bucket.
-- SQL-only — no app or edge-function redeploy.
-- =============================================================================

-- Remove the policy that let anyone LIST the bucket.
DROP POLICY IF EXISTS "menu_images_public_read" ON storage.objects;

-- Admins (authenticated, role=admin) can still SELECT/list the bucket.
DROP POLICY IF EXISTS "menu_images_admin_read" ON storage.objects;
CREATE POLICY "menu_images_admin_read" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'menu-images' AND public.is_admin());

-- (Upload/update/delete remain admin-only from the earlier hardening:
--  menu_images_admin_write / _update / _delete.)
