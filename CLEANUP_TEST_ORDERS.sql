-- =============================================================================
-- Remove the verification test orders created during checks.
-- These used all-zero test phone numbers and distinctive names.
-- order_items rows cascade-delete with their order (FK ON DELETE CASCADE).
-- =============================================================================

-- Optional: see what will be deleted first
-- SELECT order_number, customer_name, customer_phone, status, total_price
-- FROM public.orders
-- WHERE customer_phone IN ('0000000000','0000000001','0000000002','0000000003')
--    OR customer_name IN ('ROTATION TEST','DELIVERY FEE TEST','FEE CHECK','FEE CHECK2');

DELETE FROM public.orders
WHERE customer_phone IN ('0000000000','0000000001','0000000002','0000000003')
   OR customer_name IN ('ROTATION TEST','DELIVERY FEE TEST','FEE CHECK','FEE CHECK2');

-- Clear those test attempts from the rate limiter too (tidy)
DELETE FROM public.order_rate_limit
WHERE phone IN ('0000000000','0000000001','0000000002','0000000003');
