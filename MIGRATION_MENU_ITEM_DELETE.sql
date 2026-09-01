-- Allows deleting a menu item even if it has past orders.
--
-- order_items.menu_item_id had a plain FK to menu_items(id) (ON DELETE NO
-- ACTION), so deleting a menu item that had ever been ordered failed with a
-- foreign-key violation. order_items already snapshots each line's name and
-- price at order time, so it doesn't need menu_item_id to survive — safe to
-- null it out instead of blocking the delete.
--
-- Applied directly to production via `supabase db query --linked` on
-- 2026-08-03; kept here for history/reference.

ALTER TABLE public.order_items
  DROP CONSTRAINT order_items_menu_item_id_fkey,
  ADD CONSTRAINT order_items_menu_item_id_fkey
    FOREIGN KEY (menu_item_id) REFERENCES public.menu_items(id) ON DELETE SET NULL;
