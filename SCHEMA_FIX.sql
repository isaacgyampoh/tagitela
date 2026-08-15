-- ============================================================
-- TAGITELA — Schema completeness fix
-- Ensures every column the app reads actually exists, so the
-- initial load never fails silently (the "products don't show" bug).
-- Safe to run anytime; all additive.
-- Run in TAGITELA's Supabase → SQL Editor.
-- ============================================================

-- Products: columns the app's initial load selects explicitly.
ALTER TABLE products ADD COLUMN IF NOT EXISTS wholesale_price   numeric DEFAULT 0;
ALTER TABLE products ADD COLUMN IF NOT EXISTS wholesale_min_qty int DEFAULT 0;
ALTER TABLE products ADD COLUMN IF NOT EXISTS group_tag         text DEFAULT '';
CREATE INDEX IF NOT EXISTS products_group_tag_idx ON products (group_tag);

-- whatsapp_orders: columns the app reads (from later migrations).
ALTER TABLE whatsapp_orders ADD COLUMN IF NOT EXISTS ussd_code       text DEFAULT '';
ALTER TABLE whatsapp_orders ADD COLUMN IF NOT EXISTS paystack_ref    text DEFAULT '';
ALTER TABLE whatsapp_orders ADD COLUMN IF NOT EXISTS source          text DEFAULT '';
ALTER TABLE whatsapp_orders ADD COLUMN IF NOT EXISTS details_filled  boolean DEFAULT false;
ALTER TABLE whatsapp_orders ADD COLUMN IF NOT EXISTS tracking_no     text DEFAULT '';
ALTER TABLE whatsapp_orders ADD COLUMN IF NOT EXISTS delivery_status text DEFAULT '';
ALTER TABLE whatsapp_orders ADD COLUMN IF NOT EXISTS delivery_guy    text DEFAULT '';

-- sales: split payment columns.
ALTER TABLE sales ADD COLUMN IF NOT EXISTS split_cash numeric DEFAULT 0;
ALTER TABLE sales ADD COLUMN IF NOT EXISTS split_momo numeric DEFAULT 0;

-- ============================================================
-- MEDICAL categories (replaces EVERYTINROOM's home/bedding set).
-- This retags any legacy retail categories on existing products to
-- 'Other' so nothing shows curtains/blankets/etc. New products use
-- the medical list in the app's category dropdown.
-- ============================================================
UPDATE products SET category = 'Other'
 WHERE lower(category) IN (
   'curtains','kitchenware','cookware sets','racks','rods','chairs','carpets',
   'home appliances','blankets','bed sheets','mats','pillows','towels & covers',
   'artefacts & decor'
 );
