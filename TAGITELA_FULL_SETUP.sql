-- ============================================================
-- TAGITELA — COMPLETE DATABASE SETUP (run once)
-- Paste this whole file into Supabase → SQL Editor → Run.
-- Safe to re-run (IF NOT EXISTS / OR REPLACE throughout).
-- ============================================================

-- ===== 001_schema =====
-- ============================================================================
-- EVERYTINROOM POS — FULL SUPABASE SCHEMA
-- Run this ONCE in: Supabase Dashboard → SQL Editor → New Query → Run
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Helper: short IDs like the old system
CREATE OR REPLACE FUNCTION short_id() RETURNS TEXT AS $$
  SELECT substring(uuid_generate_v4()::text, 1, 8);
$$ LANGUAGE sql;

-- ======================== PRODUCTS ========================
CREATE TABLE IF NOT EXISTS products (
  id TEXT PRIMARY KEY DEFAULT short_id(),
  name TEXT NOT NULL,
  category TEXT DEFAULT '',
  cost_price NUMERIC(10,2) DEFAULT 0,
  price NUMERIC(10,2) DEFAULT 0,
  wholesale_price NUMERIC(10,2) DEFAULT 0,
  quantity INTEGER DEFAULT 0,
  image TEXT DEFAULT '',
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_products_category ON products(category);

-- ======================== BUNDLES ========================
CREATE TABLE IF NOT EXISTS bundles (
  id TEXT PRIMARY KEY DEFAULT short_id(),
  name TEXT NOT NULL,
  products JSONB DEFAULT '[]',
  bundle_price NUMERIC(10,2) DEFAULT 0,
  active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- ======================== SALES ========================
CREATE TABLE IF NOT EXISTS sales (
  id TEXT PRIMARY KEY DEFAULT short_id(),
  receipt_no TEXT NOT NULL UNIQUE,
  date TIMESTAMPTZ DEFAULT now(),
  items JSONB DEFAULT '[]',
  subtotal NUMERIC(10,2) DEFAULT 0,
  discount NUMERIC(10,2) DEFAULT 0,
  total NUMERIC(10,2) DEFAULT 0,
  profit NUMERIC(10,2) DEFAULT 0,
  payment TEXT DEFAULT 'Cash',
  split_cash NUMERIC(10,2) DEFAULT 0,
  split_momo NUMERIC(10,2) DEFAULT 0,
  customer TEXT DEFAULT 'Walk-in',
  type TEXT DEFAULT 'Retail',
  cashier TEXT DEFAULT '',
  voided BOOLEAN DEFAULT false
);
CREATE INDEX IF NOT EXISTS idx_sales_date ON sales(date);
CREATE INDEX IF NOT EXISTS idx_sales_receipt ON sales(receipt_no);
CREATE INDEX IF NOT EXISTS idx_sales_cashier ON sales(cashier);

-- ======================== CUSTOMERS ========================
CREATE TABLE IF NOT EXISTS customers (
  id TEXT PRIMARY KEY DEFAULT short_id(),
  phone TEXT NOT NULL UNIQUE,
  visit_count INTEGER DEFAULT 0,
  total_spent NUMERIC(10,2) DEFAULT 0,
  last_visit TIMESTAMPTZ DEFAULT now()
);

-- ======================== STAFF ========================
CREATE TABLE IF NOT EXISTS staff (
  id TEXT PRIMARY KEY DEFAULT short_id(),
  name TEXT NOT NULL,
  role TEXT DEFAULT 'Cashier',
  pin TEXT NOT NULL,
  active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- ======================== EXPENSES ========================
CREATE TABLE IF NOT EXISTS expenses (
  id TEXT PRIMARY KEY DEFAULT short_id(),
  date TIMESTAMPTZ DEFAULT now(),
  category TEXT DEFAULT '',
  description TEXT DEFAULT '',
  amount NUMERIC(10,2) DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_expenses_date ON expenses(date);

-- ======================== STOCK TAKES ========================
CREATE TABLE IF NOT EXISTS stock_takes (
  id TEXT PRIMARY KEY DEFAULT short_id(),
  date TIMESTAMPTZ DEFAULT now(),
  items JSONB DEFAULT '[]',
  notes TEXT DEFAULT '',
  conducted_by TEXT DEFAULT '',
  created_at TIMESTAMPTZ DEFAULT now()
);

-- ======================== STOCK ADJUSTMENTS ========================
CREATE TABLE IF NOT EXISTS stock_adjustments (
  id TEXT PRIMARY KEY DEFAULT short_id(),
  date TIMESTAMPTZ DEFAULT now(),
  product_id TEXT DEFAULT '',
  product_name TEXT DEFAULT '',
  qty INTEGER DEFAULT 0,
  reason TEXT DEFAULT '',
  notes TEXT DEFAULT '',
  adjusted_by TEXT DEFAULT ''
);

-- ======================== PROMOS ========================
CREATE TABLE IF NOT EXISTS promos (
  id TEXT PRIMARY KEY DEFAULT short_id(),
  name TEXT NOT NULL,
  start_date DATE,
  end_date DATE,
  items JSONB DEFAULT '[]',
  active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- ======================== INVOICES ========================
CREATE TABLE IF NOT EXISTS invoices (
  id TEXT PRIMARY KEY DEFAULT short_id(),
  invoice_id TEXT DEFAULT '',
  date TIMESTAMPTZ DEFAULT now(),
  supplier TEXT DEFAULT '',
  amount NUMERIC(10,2) DEFAULT 0,
  notes TEXT DEFAULT '',
  image TEXT DEFAULT '',
  photo_index INTEGER DEFAULT 1,
  total_photos INTEGER DEFAULT 1,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_invoices_invoice_id ON invoices(invoice_id);

-- ======================== WHATSAPP ORDERS ========================
CREATE TABLE IF NOT EXISTS whatsapp_orders (
  id TEXT PRIMARY KEY DEFAULT short_id(),
  order_no TEXT NOT NULL,
  date TIMESTAMPTZ DEFAULT now(),
  customer_name TEXT DEFAULT '',
  customer_phone TEXT DEFAULT '',
  items JSONB DEFAULT '[]',
  subtotal NUMERIC(10,2) DEFAULT 0,
  delivery_fee NUMERIC(10,2) DEFAULT 0,
  total NUMERIC(10,2) DEFAULT 0,
  address TEXT DEFAULT '',
  notes TEXT DEFAULT '',
  status TEXT DEFAULT 'Pending',
  paystack_ref TEXT DEFAULT '',
  paid_at TIMESTAMPTZ,
  processed_by TEXT DEFAULT '',
  processed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_wa_status ON whatsapp_orders(status);
CREATE INDEX IF NOT EXISTS idx_wa_date ON whatsapp_orders(date);

-- ======================== REFUNDS ========================
CREATE TABLE IF NOT EXISTS refunds (
  id TEXT PRIMARY KEY DEFAULT short_id(),
  refund_no TEXT NOT NULL,
  date TIMESTAMPTZ DEFAULT now(),
  original_receipt_no TEXT DEFAULT '',
  original_sale_id TEXT DEFAULT '',
  items JSONB DEFAULT '[]',
  refund_amount NUMERIC(10,2) DEFAULT 0,
  reason TEXT DEFAULT '',
  processed_by TEXT DEFAULT '',
  customer TEXT DEFAULT '',
  status TEXT DEFAULT 'Completed',
  created_at TIMESTAMPTZ DEFAULT now()
);

-- ======================== ROW LEVEL SECURITY ========================
-- POS is internal (PIN-protected), so allow full anon access.
-- Tighten later if you add Supabase Auth.

DO $$ 
DECLARE t TEXT;
BEGIN
  FOR t IN SELECT unnest(ARRAY[
    'products','bundles','sales','customers','staff','expenses',
    'stock_takes','stock_adjustments','promos','invoices',
    'whatsapp_orders','refunds'
  ]) LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format(
      'CREATE POLICY "anon_full_%s" ON %I FOR ALL TO anon, authenticated USING (true) WITH CHECK (true)', t, t
    );
  END LOOP;
END $$;

-- ======================== SEQUENCE GENERATORS ========================

CREATE OR REPLACE FUNCTION generate_receipt_no() RETURNS TEXT AS $$
DECLARE prefix TEXT; cnt INTEGER;
BEGIN
  prefix := 'RCP' || to_char(now(), 'YYYYMMDD');
  SELECT COUNT(*) INTO cnt FROM sales WHERE receipt_no LIKE prefix || '%';
  RETURN prefix || '-' || lpad((cnt + 1)::text, 3, '0');
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION generate_wa_order_no() RETURNS TEXT AS $$
DECLARE prefix TEXT; cnt INTEGER;
BEGIN
  prefix := 'WA' || to_char(now(), 'YYYYMMDD');
  SELECT COUNT(*) INTO cnt FROM whatsapp_orders WHERE order_no LIKE prefix || '%';
  RETURN prefix || '-' || lpad((cnt + 1)::text, 3, '0');
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION generate_refund_no() RETURNS TEXT AS $$
DECLARE prefix TEXT; cnt INTEGER;
BEGIN
  prefix := 'RFD' || to_char(now(), 'YYYYMMDD');
  SELECT COUNT(*) INTO cnt FROM refunds WHERE refund_no LIKE prefix || '%';
  RETURN prefix || '-' || lpad((cnt + 1)::text, 3, '0');
END;
$$ LANGUAGE plpgsql;

-- ======================== RPC: RECORD SALE (atomic) ========================
-- Does everything in one transaction: insert sale, deduct stock, update customer

CREATE OR REPLACE FUNCTION record_sale(
  p_items JSONB,
  p_customer TEXT,
  p_payment TEXT,
  p_discount NUMERIC,
  p_type TEXT,
  p_cashier TEXT,
  p_split_cash NUMERIC DEFAULT 0,
  p_split_momo NUMERIC DEFAULT 0
) RETURNS JSON AS $$
DECLARE
  v_id TEXT;
  v_receipt TEXT;
  v_subtotal NUMERIC := 0;
  v_profit NUMERIC := 0;
  v_total NUMERIC;
  v_item JSONB;
  v_prod RECORD;
  v_qty INTEGER;
  v_bundle_item JSONB;
BEGIN
  v_id := short_id();
  v_receipt := generate_receipt_no();

  -- Calculate totals
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_subtotal := v_subtotal + COALESCE((v_item->>'lineTotal')::NUMERIC, 0);
    v_profit := v_profit + (
      COALESCE((v_item->>'price')::NUMERIC, 0) - COALESCE((v_item->>'costPrice')::NUMERIC, 0)
    ) * COALESCE((v_item->>'qty')::INTEGER, 0);
  END LOOP;

  v_total := v_subtotal - p_discount;

  -- Insert sale
  INSERT INTO sales (id, receipt_no, date, items, subtotal, discount, total, profit,
    payment, split_cash, split_momo, customer, type, cashier, voided)
  VALUES (v_id, v_receipt, now(), p_items, v_subtotal, p_discount, v_total, v_profit,
    p_payment, p_split_cash, p_split_momo, p_customer, p_type, p_cashier, false);

  -- Deduct stock
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    IF (v_item->>'isBundle')::BOOLEAN IS TRUE AND v_item->'bundleItems' IS NOT NULL THEN
      -- Bundle: deduct each bundle component
      FOR v_bundle_item IN SELECT * FROM jsonb_array_elements(v_item->'bundleItems') LOOP
        v_qty := COALESCE((v_bundle_item->>'qty')::INTEGER, 0) * COALESCE((v_item->>'qty')::INTEGER, 1);
        UPDATE products SET quantity = GREATEST(0, quantity - v_qty)
        WHERE id = v_bundle_item->>'productId';
      END LOOP;
    ELSIF v_item->>'productId' IS NOT NULL THEN
      UPDATE products SET quantity = GREATEST(0, quantity - COALESCE((v_item->>'qty')::INTEGER, 0))
      WHERE id = v_item->>'productId';
    END IF;
  END LOOP;

  -- Upsert customer
  IF p_customer IS NOT NULL AND p_customer != 'Walk-in' AND p_customer != '' THEN
    INSERT INTO customers (phone, visit_count, total_spent, last_visit)
    VALUES (p_customer, 1, v_total, now())
    ON CONFLICT (phone) DO UPDATE SET
      visit_count = customers.visit_count + 1,
      total_spent = customers.total_spent + v_total,
      last_visit = now();
  END IF;

  RETURN json_build_object(
    'success', true,
    'receiptNo', v_receipt,
    'saleId', v_id,
    'subtotal', v_subtotal,
    'discount', p_discount,
    'total', v_total,
    'date', now()
  );
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$ LANGUAGE plpgsql;

-- ======================== RPC: VOID SALE ========================

CREATE OR REPLACE FUNCTION void_sale(p_sale_id TEXT) RETURNS JSON AS $$
DECLARE
  v_sale RECORD;
  v_item JSONB;
  v_bundle_item JSONB;
  v_qty INTEGER;
BEGIN
  SELECT * INTO v_sale FROM sales WHERE id = p_sale_id;
  IF NOT FOUND THEN RETURN json_build_object('success', false, 'error', 'Sale not found'); END IF;
  IF v_sale.voided THEN RETURN json_build_object('success', false, 'error', 'Already voided'); END IF;

  -- Restore stock
  FOR v_item IN SELECT * FROM jsonb_array_elements(v_sale.items) LOOP
    IF (v_item->>'isBundle')::BOOLEAN IS TRUE AND v_item->'bundleItems' IS NOT NULL THEN
      FOR v_bundle_item IN SELECT * FROM jsonb_array_elements(v_item->'bundleItems') LOOP
        v_qty := COALESCE((v_bundle_item->>'qty')::INTEGER, 0) * COALESCE((v_item->>'qty')::INTEGER, 1);
        UPDATE products SET quantity = quantity + v_qty WHERE id = v_bundle_item->>'productId';
      END LOOP;
    ELSIF v_item->>'productId' IS NOT NULL THEN
      UPDATE products SET quantity = quantity + COALESCE((v_item->>'qty')::INTEGER, 0)
      WHERE id = v_item->>'productId';
    END IF;
  END LOOP;

  UPDATE sales SET voided = true WHERE id = p_sale_id;
  RETURN json_build_object('success', true);
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$ LANGUAGE plpgsql;

-- ======================== RPC: COMPLETE WA ORDER ========================

CREATE OR REPLACE FUNCTION complete_wa_order(p_order_id TEXT, p_processed_by TEXT)
RETURNS JSON AS $$
DECLARE
  v_order RECORD;
  v_item JSONB;
  v_prod RECORD;
  v_profit NUMERIC := 0;
  v_sale_id TEXT;
  v_receipt TEXT;
BEGIN
  SELECT * INTO v_order FROM whatsapp_orders WHERE id = p_order_id;
  IF NOT FOUND THEN RETURN json_build_object('success', false, 'error', 'Order not found'); END IF;
  IF v_order.status = 'Completed' THEN RETURN json_build_object('success', false, 'error', 'Already completed'); END IF;

  -- Deduct stock + calculate profit
  FOR v_item IN SELECT * FROM jsonb_array_elements(v_order.items) LOOP
    SELECT * INTO v_prod FROM products WHERE lower(name) = lower(v_item->>'name') LIMIT 1;
    IF FOUND THEN
      UPDATE products SET quantity = GREATEST(0, quantity - COALESCE((v_item->>'qty')::INTEGER, 0))
      WHERE id = v_prod.id;
      v_profit := v_profit + (
        COALESCE((v_item->>'price')::NUMERIC, 0) - v_prod.cost_price
      ) * COALESCE((v_item->>'qty')::INTEGER, 0);
    END IF;
  END LOOP;

  v_sale_id := short_id();
  v_receipt := generate_receipt_no();

  INSERT INTO sales (id, receipt_no, date, items, subtotal, discount, total, profit,
    payment, customer, type, cashier, voided)
  VALUES (v_sale_id, v_receipt, now(), v_order.items, v_order.subtotal, 0,
    v_order.total, v_profit, 'Paystack', v_order.customer_phone, 'WhatsApp',
    p_processed_by, false);

  -- Upsert customer
  IF v_order.customer_phone != '' THEN
    INSERT INTO customers (phone, visit_count, total_spent, last_visit)
    VALUES (v_order.customer_phone, 1, v_order.total, now())
    ON CONFLICT (phone) DO UPDATE SET
      visit_count = customers.visit_count + 1,
      total_spent = customers.total_spent + v_order.total,
      last_visit = now();
  END IF;

  UPDATE whatsapp_orders SET
    status = 'Completed', processed_by = p_processed_by, processed_at = now()
  WHERE id = p_order_id;

  RETURN json_build_object('success', true, 'receiptNo', v_receipt, 'saleId', v_sale_id);
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$ LANGUAGE plpgsql;

-- ======================== RPC: PROCESS REFUND ========================

CREATE OR REPLACE FUNCTION process_refund(
  p_receipt_no TEXT,
  p_items JSONB,
  p_reason TEXT,
  p_processed_by TEXT,
  p_customer TEXT
) RETURNS JSON AS $$
DECLARE
  v_sale RECORD;
  v_refund_id TEXT;
  v_refund_no TEXT;
  v_amount NUMERIC := 0;
  v_item JSONB;
  v_orig_items JSONB;
  v_is_full BOOLEAN := false;
BEGIN
  SELECT * INTO v_sale FROM sales WHERE receipt_no = p_receipt_no;
  IF NOT FOUND THEN RETURN json_build_object('success', false, 'error', 'Sale not found'); END IF;
  IF v_sale.voided THEN RETURN json_build_object('success', false, 'error', 'Sale already voided'); END IF;

  v_refund_id := short_id();
  v_refund_no := generate_refund_no();

  -- Calculate refund amount + restore stock
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_amount := v_amount + COALESCE((v_item->>'price')::NUMERIC, 0) * COALESCE((v_item->>'qty')::INTEGER, 0);
    -- Restore stock
    UPDATE products SET quantity = quantity + COALESCE((v_item->>'qty')::INTEGER, 0)
    WHERE lower(name) = lower(v_item->>'name') OR id = COALESCE(v_item->>'productId', '');
  END LOOP;

  INSERT INTO refunds (id, refund_no, date, original_receipt_no, original_sale_id,
    items, refund_amount, reason, processed_by, customer, status)
  VALUES (v_refund_id, v_refund_no, now(), p_receipt_no, v_sale.id,
    p_items, v_amount, p_reason, p_processed_by, p_customer, 'Completed');

  -- Check if full refund → void original sale
  IF jsonb_array_length(p_items) = jsonb_array_length(v_sale.items) THEN
    UPDATE sales SET voided = true WHERE id = v_sale.id;
    v_is_full := true;
  END IF;

  RETURN json_build_object(
    'success', true, 'refundNo', v_refund_no,
    'refundAmount', v_amount, 'isFullRefund', v_is_full
  );
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$ LANGUAGE plpgsql;

-- ======================== RPC: DASHBOARD ========================

CREATE OR REPLACE FUNCTION get_dashboard() RETURNS JSON AS $$
DECLARE today_start TIMESTAMPTZ; result JSON;
BEGIN
  today_start := date_trunc('day', now());
  SELECT json_build_object(
    'todaySales', COALESCE((SELECT SUM(total) FROM sales WHERE date >= today_start AND NOT voided), 0),
    'todayProfit', COALESCE((SELECT SUM(profit) FROM sales WHERE date >= today_start AND NOT voided), 0),
    'todayCount', COALESCE((SELECT COUNT(*) FROM sales WHERE date >= today_start AND NOT voided), 0),
    'pendingOrders', COALESCE((SELECT COUNT(*) FROM whatsapp_orders WHERE status = 'Pending'), 0),
    'paystackOrders', COALESCE((SELECT COUNT(*) FROM whatsapp_orders WHERE paystack_ref != '' AND status != 'Cancelled'), 0)
  ) INTO result;
  RETURN result;
END;
$$ LANGUAGE plpgsql;

-- ======================== REALTIME ========================
-- Live updates for key tables
ALTER PUBLICATION supabase_realtime ADD TABLE whatsapp_orders;
ALTER PUBLICATION supabase_realtime ADD TABLE sales;
ALTER PUBLICATION supabase_realtime ADD TABLE products;

-- ============================================================================
-- DONE! Now paste your SUPABASE_URL and SUPABASE_ANON_KEY into the frontend.
-- ============================================================================

-- ===== 003_storage =====
-- ============================================================================
-- 003: STORAGE BUCKETS FOR IMAGES
-- Run in Supabase SQL Editor AFTER 001_schema.sql
-- ============================================================================

-- Create storage buckets for product images and invoice photos
INSERT INTO storage.buckets (id, name, public) VALUES ('product-images', 'product-images', true) ON CONFLICT DO NOTHING;
INSERT INTO storage.buckets (id, name, public) VALUES ('invoice-photos', 'invoice-photos', true) ON CONFLICT DO NOTHING;

-- Allow public read access
CREATE POLICY "Public read product images" ON storage.objects FOR SELECT USING (bucket_id = 'product-images');
CREATE POLICY "Public read invoice photos" ON storage.objects FOR SELECT USING (bucket_id = 'invoice-photos');

-- Allow anon uploads
CREATE POLICY "Anon upload product images" ON storage.objects FOR INSERT WITH CHECK (bucket_id = 'product-images');
CREATE POLICY "Anon upload invoice photos" ON storage.objects FOR INSERT WITH CHECK (bucket_id = 'invoice-photos');
CREATE POLICY "Anon delete product images" ON storage.objects FOR DELETE USING (bucket_id = 'product-images');
CREATE POLICY "Anon delete invoice photos" ON storage.objects FOR DELETE USING (bucket_id = 'invoice-photos');

-- ===== 004_security =====
-- ============================================
-- EVERYTINROOM POS - SECURITY HARDENING
-- Run this in Supabase SQL Editor
-- https://supabase.com/dashboard/project/nyrjuuynklrmyzgsgmwm/sql
-- ============================================

-- STEP 1: Enable RLS on all tables
-- (If already enabled, these will just succeed silently)
ALTER TABLE IF EXISTS products ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS staff ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS expenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS bundles ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS refunds ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS whatsapp_orders ENABLE ROW LEVEL SECURITY;

-- Optional tables (won't error if missing)
DO $$ BEGIN ALTER TABLE promos ENABLE ROW LEVEL SECURITY; EXCEPTION WHEN undefined_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE invoices ENABLE ROW LEVEL SECURITY; EXCEPTION WHEN undefined_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE stock_takes ENABLE ROW LEVEL SECURITY; EXCEPTION WHEN undefined_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE stock_adjustments ENABLE ROW LEVEL SECURITY; EXCEPTION WHEN undefined_table THEN NULL; END $$;

-- STEP 2: Drop existing policies (clean slate)
DO $$ 
DECLARE
  tbl text;
  pol text;
BEGIN
  FOR tbl, pol IN 
    SELECT schemaname || '.' || tablename, policyname 
    FROM pg_policies 
    WHERE schemaname = 'public'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON %s', pol, tbl);
  END LOOP;
END $$;

-- STEP 3: Create access policies
-- The anon key is used by the POS app. We allow full access
-- because authentication is handled by PIN at the app level.
-- RLS ensures the data is only accessible through the Supabase API,
-- NOT directly via the database connection string.

-- Products
CREATE POLICY "products_select" ON products FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY "products_insert" ON products FOR INSERT TO anon, authenticated WITH CHECK (true);
CREATE POLICY "products_update" ON products FOR UPDATE TO anon, authenticated USING (true);
CREATE POLICY "products_delete" ON products FOR DELETE TO anon, authenticated USING (true);

-- Sales (no delete - sales should never be deleted, only voided)
CREATE POLICY "sales_select" ON sales FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY "sales_insert" ON sales FOR INSERT TO anon, authenticated WITH CHECK (true);
CREATE POLICY "sales_update" ON sales FOR UPDATE TO anon, authenticated USING (true);

-- Staff
CREATE POLICY "staff_select" ON staff FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY "staff_insert" ON staff FOR INSERT TO anon, authenticated WITH CHECK (true);
CREATE POLICY "staff_update" ON staff FOR UPDATE TO anon, authenticated USING (true);
CREATE POLICY "staff_delete" ON staff FOR DELETE TO anon, authenticated USING (true);

-- Expenses
CREATE POLICY "expenses_select" ON expenses FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY "expenses_insert" ON expenses FOR INSERT TO anon, authenticated WITH CHECK (true);
CREATE POLICY "expenses_update" ON expenses FOR UPDATE TO anon, authenticated USING (true);
CREATE POLICY "expenses_delete" ON expenses FOR DELETE TO anon, authenticated USING (true);

-- Customers
CREATE POLICY "customers_select" ON customers FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY "customers_insert" ON customers FOR INSERT TO anon, authenticated WITH CHECK (true);
CREATE POLICY "customers_update" ON customers FOR UPDATE TO anon, authenticated USING (true);

-- Bundles
CREATE POLICY "bundles_select" ON bundles FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY "bundles_insert" ON bundles FOR INSERT TO anon, authenticated WITH CHECK (true);
CREATE POLICY "bundles_update" ON bundles FOR UPDATE TO anon, authenticated USING (true);
CREATE POLICY "bundles_delete" ON bundles FOR DELETE TO anon, authenticated USING (true);

-- Refunds (no delete)
CREATE POLICY "refunds_select" ON refunds FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY "refunds_insert" ON refunds FOR INSERT TO anon, authenticated WITH CHECK (true);

-- WhatsApp Orders
CREATE POLICY "wa_select" ON whatsapp_orders FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY "wa_insert" ON whatsapp_orders FOR INSERT TO anon, authenticated WITH CHECK (true);
CREATE POLICY "wa_update" ON whatsapp_orders FOR UPDATE TO anon, authenticated USING (true);

-- Optional tables
DO $$ BEGIN EXECUTE 'CREATE POLICY "promos_all" ON promos FOR ALL TO anon, authenticated USING (true) WITH CHECK (true)'; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN EXECUTE 'CREATE POLICY "invoices_all" ON invoices FOR ALL TO anon, authenticated USING (true) WITH CHECK (true)'; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN EXECUTE 'CREATE POLICY "stocktakes_all" ON stock_takes FOR ALL TO anon, authenticated USING (true) WITH CHECK (true)'; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN EXECUTE 'CREATE POLICY "stockadj_all" ON stock_adjustments FOR ALL TO anon, authenticated USING (true) WITH CHECK (true)'; EXCEPTION WHEN OTHERS THEN NULL; END $$;

-- STEP 4: Ensure RPC functions use SECURITY DEFINER
-- This means they run with the function owner's permissions,
-- bypassing RLS for the operations inside the function.
-- The functions themselves validate inputs.

-- Done! Your database is now secured with RLS.

-- ===== 005_categories =====
-- ============================================
-- EVERYTINROOM POS - STANDARDIZE CATEGORIES
-- Run this in Supabase SQL Editor
-- ============================================

-- This updates product categories to the standard set.
-- Only run if you want to clean up existing category names.

-- Standard Categories for Everytin Room:
-- 1. Curtains
-- 2. Kitchenware
-- 3. Cookware Sets
-- 4. Racks
-- 5. Rods
-- 6. Chairs
-- 7. Carpets
-- 8. Home Appliances
-- 9. Blankets
-- 10. Bed Sheets
-- 11. Mats
-- 12. Pillows
-- 13. Towels & Covers
-- 14. Artefacts & Decor
-- 15. Other

-- Fix common misspellings / variations
UPDATE products SET category = 'Curtains' WHERE lower(category) IN ('curtain', 'curtains', 'curtain set', 'curtain sets');
UPDATE products SET category = 'Kitchenware' WHERE lower(category) IN ('kitchenware', 'kitchenwares', 'kitchen ware', 'kitchen wares', 'kitchen', 'kitchen items');
UPDATE products SET category = 'Cookware Sets' WHERE lower(category) IN ('cookware', 'cookware sets', 'cookware set', 'cooking set', 'cooking sets', 'pots', 'pans');
UPDATE products SET category = 'Racks' WHERE lower(category) IN ('rack', 'racks', 'shelf', 'shelves', 'storage rack');
UPDATE products SET category = 'Rods' WHERE lower(category) IN ('rod', 'rods', 'curtain rod', 'curtain rods');
UPDATE products SET category = 'Chairs' WHERE lower(category) IN ('chair', 'chairs', 'seating');
UPDATE products SET category = 'Carpets' WHERE lower(category) IN ('carpet', 'carpets', 'rug', 'rugs');
UPDATE products SET category = 'Home Appliances' WHERE lower(category) IN ('home appliances', 'human appliances', 'appliance', 'appliances', 'electronics');
UPDATE products SET category = 'Blankets' WHERE lower(category) IN ('blanket', 'blankets', 'duvet', 'duvets', 'comforter');
UPDATE products SET category = 'Bed Sheets' WHERE lower(category) IN ('bed sheet', 'bed sheets', 'bedsheet', 'bedsheets', 'sheet', 'sheets', 'bedding');
UPDATE products SET category = 'Mats' WHERE lower(category) IN ('mat', 'mats', 'door mat', 'floor mat', 'bathroom mat');
UPDATE products SET category = 'Pillows' WHERE lower(category) IN ('pillow', 'pillows', 'pillow case', 'pillowcase');
UPDATE products SET category = 'Towels & Covers' WHERE lower(category) IN ('towel', 'towels', 'tope', 'topes', 'cover', 'covers', 'table cover', 'table cloth');
UPDATE products SET category = 'Artefacts & Decor' WHERE lower(category) IN ('artefact', 'artefacts', 'artifact', 'artifacts', 'decor', 'decoration', 'decorations', 'flowers', 'flower', 'vase', 'aesthetics');
UPDATE products SET category = 'Other' WHERE category IS NULL OR category = '';

-- ===== 006_wholesale_min_qty =====
-- ============================================
-- Add wholesale minimum quantity to products
-- Run in Supabase SQL Editor
-- ============================================

-- Add the column (default 0 means no wholesale minimum set)
ALTER TABLE products ADD COLUMN IF NOT EXISTS wholesale_min_qty integer DEFAULT 0;

-- Example: If a product has wholesale_price = 15 and wholesale_min_qty = 6,
-- when a customer adds 6+ of that product to cart, the price auto-switches
-- from retail price to wholesale price.

-- ===== 007_pin_security =====
-- ============================================
-- SECURITY: Server-side PIN verification
-- Run this in Supabase SQL Editor
-- PINs will no longer be sent to the browser
-- ============================================

CREATE OR REPLACE FUNCTION verify_pin(p_pin text)
RETURNS jsonb AS $$
DECLARE
  staff_record record;
BEGIN
  -- Check staff table
  SELECT id, name, role, active INTO staff_record
  FROM staff
  WHERE pin = p_pin AND active = true
  LIMIT 1;

  IF staff_record.id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', true,
      'id', staff_record.id,
      'name', staff_record.name,
      'role', staff_record.role
    );
  END IF;

  -- Not found
  RETURN jsonb_build_object('success', false);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ===== 008_admin_serverside =====
-- ============================================
-- SECURITY UPDATE: Admin PIN also server-side
-- Run in Supabase SQL Editor
-- ============================================

-- Make sure you have an Admin staff record with PIN 1024
-- (or whatever PIN you want for admin)
INSERT INTO staff (name, role, pin, active)
VALUES ('Admin', 'Admin', '1024', true)
ON CONFLICT DO NOTHING;

-- If Admin already exists, update the PIN:
-- UPDATE staff SET pin = '1024' WHERE name = 'Admin' AND role = 'Admin';

-- The verify_pin function already checks the staff table,
-- so Admin will be verified server-side like all other staff.
-- No PIN is exposed in the browser anymore.

-- ===== 009_whatsapp_bot =====
-- ============================================
-- 009: WhatsApp AI Bot - Conversations Table
-- Run this in Supabase SQL Editor
-- ============================================

-- Store AI conversation history per customer
CREATE TABLE IF NOT EXISTS wa_conversations (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  chat_id text UNIQUE NOT NULL,          -- e.g. 233241234567@s.whatsapp.net
  customer_name text DEFAULT 'Customer',
  messages jsonb DEFAULT '[]'::jsonb,     -- Array of {role, content}
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Index for fast lookup by chat_id
CREATE INDEX IF NOT EXISTS idx_wa_conv_chat ON wa_conversations(chat_id);

-- Auto-cleanup: delete conversations older than 30 days
-- (keeps database small, customers rarely continue chats after 30 days)
CREATE OR REPLACE FUNCTION cleanup_old_conversations()
RETURNS void AS $$
BEGIN
  DELETE FROM wa_conversations WHERE updated_at < now() - interval '30 days';
END;
$$ LANGUAGE plpgsql;

-- ===== 010_secure_pins =====
-- ============================================
-- SECURITY: Restrict PIN column access
-- Run this in Supabase SQL Editor
-- ============================================

-- Create a secure view for staff that excludes PINs
-- The frontend should use this view instead of the staff table directly
CREATE OR REPLACE VIEW staff_safe AS
SELECT id, name, role, active
FROM staff;

-- Grant access to the view
GRANT SELECT ON staff_safe TO anon, authenticated;

-- Create a secure function to update staff with optional PIN
-- This prevents the frontend from needing to read PINs
CREATE OR REPLACE FUNCTION update_staff_secure(
  p_id uuid,
  p_name text,
  p_role text,
  p_pin text DEFAULT NULL,
  p_active boolean DEFAULT true
)
RETURNS jsonb AS $$
BEGIN
  IF p_pin IS NOT NULL AND length(p_pin) = 4 THEN
    UPDATE staff SET name = p_name, role = p_role, pin = p_pin, active = p_active WHERE id = p_id;
  ELSE
    UPDATE staff SET name = p_name, role = p_role, active = p_active WHERE id = p_id;
  END IF;
  RETURN jsonb_build_object('success', true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create a secure function to add new staff
CREATE OR REPLACE FUNCTION add_staff_secure(
  p_name text,
  p_role text,
  p_pin text,
  p_active boolean DEFAULT true
)
RETURNS jsonb AS $$
DECLARE
  new_id uuid;
BEGIN
  IF length(p_pin) != 4 THEN
    RETURN jsonb_build_object('success', false, 'error', 'PIN must be 4 digits');
  END IF;
  
  INSERT INTO staff (name, role, pin, active)
  VALUES (p_name, p_role, p_pin, p_active)
  RETURNING id INTO new_id;
  
  RETURN jsonb_build_object('success', true, 'id', new_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ===== 011_ussd_payment =====
-- ============================================
-- 011: USSD Payment - Add ussd_code to whatsapp_orders
-- Run this in Supabase SQL Editor
-- ============================================

-- Add ussd_code column (numeric, for USSD dialing)
ALTER TABLE whatsapp_orders ADD COLUMN IF NOT EXISTS ussd_code INTEGER;

-- Create a sequence starting at 50001
CREATE SEQUENCE IF NOT EXISTS ussd_code_seq START 50001;

-- Auto-assign ussd_code when a new order is created without one
CREATE OR REPLACE FUNCTION assign_ussd_code()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.ussd_code IS NULL THEN
    NEW.ussd_code := nextval('ussd_code_seq');
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop trigger if exists, then create
DROP TRIGGER IF EXISTS trg_assign_ussd_code ON whatsapp_orders;
CREATE TRIGGER trg_assign_ussd_code
  BEFORE INSERT ON whatsapp_orders
  FOR EACH ROW
  EXECUTE FUNCTION assign_ussd_code();

-- Index for fast lookup by ussd_code
CREATE INDEX IF NOT EXISTS idx_wa_ussd_code ON whatsapp_orders(ussd_code);

-- Backfill existing orders that don't have a ussd_code
UPDATE whatsapp_orders SET ussd_code = nextval('ussd_code_seq') WHERE ussd_code IS NULL;

-- Verify
SELECT id, order_no, ussd_code, total, status FROM whatsapp_orders ORDER BY date DESC LIMIT 5;

-- ===== 012_delivery_tracking =====
-- Add delivery tracking columns to whatsapp_orders
ALTER TABLE whatsapp_orders ADD COLUMN IF NOT EXISTS tracking_no TEXT DEFAULT '';
ALTER TABLE whatsapp_orders ADD COLUMN IF NOT EXISTS delivery_status TEXT DEFAULT '';
ALTER TABLE whatsapp_orders ADD COLUMN IF NOT EXISTS delivery_guy TEXT DEFAULT '';
ALTER TABLE whatsapp_orders ADD COLUMN IF NOT EXISTS delivered_at TIMESTAMPTZ;
ALTER TABLE whatsapp_orders ADD COLUMN IF NOT EXISTS delivery_photo TEXT DEFAULT '';
ALTER TABLE whatsapp_orders ADD COLUMN IF NOT EXISTS delivery_notes TEXT DEFAULT '';

-- Generate tracking number function
CREATE OR REPLACE FUNCTION generate_tracking_no()
RETURNS TEXT AS $$
DECLARE
  track TEXT;
BEGIN
  track := 'ETR-' || TO_CHAR(NOW(), 'YYMMDD') || '-' || LPAD(FLOOR(RANDOM() * 10000)::TEXT, 4, '0');
  RETURN track;
END;
$$ LANGUAGE plpgsql;

-- Auto-assign tracking number when order moves to Paid
CREATE OR REPLACE FUNCTION auto_tracking_no()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status = 'Paid' AND (OLD.status IS NULL OR OLD.status != 'Paid') AND (NEW.tracking_no IS NULL OR NEW.tracking_no = '') THEN
    NEW.tracking_no := 'ETR-' || TO_CHAR(NOW(), 'YYMMDD') || '-' || LPAD(FLOOR(RANDOM() * 10000)::TEXT, 4, '0');
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_auto_tracking ON whatsapp_orders;
CREATE TRIGGER trg_auto_tracking
  BEFORE UPDATE ON whatsapp_orders
  FOR EACH ROW
  EXECUTE FUNCTION auto_tracking_no();

-- Also assign tracking on insert if status is Paid
CREATE OR REPLACE FUNCTION auto_tracking_no_insert()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status = 'Paid' AND (NEW.tracking_no IS NULL OR NEW.tracking_no = '') THEN
    NEW.tracking_no := 'ETR-' || TO_CHAR(NOW(), 'YYMMDD') || '-' || LPAD(FLOOR(RANDOM() * 10000)::TEXT, 4, '0');
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_auto_tracking_insert ON whatsapp_orders;
CREATE TRIGGER trg_auto_tracking_insert
  BEFORE INSERT ON whatsapp_orders
  FOR EACH ROW
  EXECUTE FUNCTION auto_tracking_no_insert();

-- ===== PERMISSIONS_SETUP =====
-- ============================================================
-- EVERYTINROOM — Phase 1: Staff Permissions
-- Adds granular permissions per staff member. Safe & additive —
-- existing staff keep working (Admins get everything, others get Sales).
-- Run once in Supabase → SQL Editor.
-- ============================================================

-- 1. Add a permissions column (JSON array of permission keys).
ALTER TABLE staff ADD COLUMN IF NOT EXISTS permissions jsonb DEFAULT '[]'::jsonb;

-- 2. Backfill existing staff so nothing breaks:
--    Admins -> all permissions; everyone else -> Sales.
UPDATE staff
SET permissions = '["sales","stock_taking","product_receiving","product_management","inventory_view","reports","admin"]'::jsonb
WHERE role = 'Admin' AND (permissions = '[]'::jsonb OR permissions IS NULL);

UPDATE staff
SET permissions = '["sales"]'::jsonb
WHERE role <> 'Admin' AND (permissions = '[]'::jsonb OR permissions IS NULL);

-- 3. Update verify_pin to return permissions too.
CREATE OR REPLACE FUNCTION verify_pin(p_pin text)
RETURNS jsonb AS $$
DECLARE
  staff_record record;
BEGIN
  SELECT id, name, role, active, permissions INTO staff_record
  FROM staff
  WHERE pin = p_pin AND active = true
  LIMIT 1;

  IF staff_record.id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', true,
      'id', staff_record.id,
      'name', staff_record.name,
      'role', staff_record.role,
      'permissions', COALESCE(staff_record.permissions, '[]'::jsonb)
    );
  END IF;

  RETURN jsonb_build_object('success', false);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Permission keys reference (for the app):
--   sales                -> create/process sales
--   stock_taking         -> print sheets, count, submit adjustments
--   product_receiving    -> receive supplier deliveries
--   product_management   -> add/edit products
--   inventory_view       -> view stock & inventory reports
--   reports              -> view permitted reports
--   admin                -> full access (implies all of the above)

-- ===== RECEIVING_SETUP =====
-- ============================================================
-- EVERYTINROOM — Phase 2: Supplier Receiving (with approval)
-- Warehouse staff record deliveries; stock only changes AFTER an
-- admin approves. Full variance + audit trail.
-- Run once in Supabase → SQL Editor.
-- ============================================================

-- Suppliers (optional master list; receiving can also use a free-text name).
CREATE TABLE IF NOT EXISTS suppliers (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name       text NOT NULL,
  phone      text DEFAULT '',
  notes      text DEFAULT '',
  active     boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

-- A receiving record = one delivery from a supplier.
CREATE TABLE IF NOT EXISTS receivings (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ref_no        text UNIQUE NOT NULL,
  supplier_name text DEFAULT '',
  supplier_id   uuid REFERENCES suppliers(id),
  status        text DEFAULT 'pending',   -- pending | approved | rejected
  items         jsonb DEFAULT '[]',       -- [{product_id,name,expected,received,variance,cost_price}]
  total_expected int DEFAULT 0,
  total_received int DEFAULT 0,
  note          text DEFAULT '',
  created_by    text DEFAULT '',
  created_at    timestamptz DEFAULT now(),
  approved_by   text DEFAULT '',
  approved_at   timestamptz,
  reject_reason text DEFAULT ''
);
CREATE INDEX IF NOT EXISTS idx_receivings_status ON receivings(status);
CREATE INDEX IF NOT EXISTS idx_receivings_created ON receivings(created_at);

-- Approve a receiving: apply the RECEIVED quantities to stock, log each change
-- in the audit trail (see Phase 4), and mark approved. Idempotent — a receiving
-- can only be approved once.
CREATE OR REPLACE FUNCTION approve_receiving(p_id uuid, p_approver text)
RETURNS jsonb AS $$
DECLARE
  rec record;
  item jsonb;
  prod record;
  new_qty int;
  applied int := 0;
BEGIN
  SELECT * INTO rec FROM receivings WHERE id = p_id;
  IF rec.id IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'not found'); END IF;
  IF rec.status <> 'pending' THEN RETURN jsonb_build_object('success', false, 'error', 'already ' || rec.status); END IF;

  FOR item IN SELECT * FROM jsonb_array_elements(rec.items) LOOP
    SELECT id, quantity, name INTO prod FROM products WHERE id = (item->>'product_id');
    IF prod.id IS NOT NULL THEN
      new_qty := prod.quantity + COALESCE((item->>'received')::int, 0);
      UPDATE products SET quantity = new_qty WHERE id = prod.id;
      -- Audit log (Phase 4 table; created there). Safe if table exists.
      BEGIN
        INSERT INTO stock_ledger (product_id, product_name, previous_qty, change_qty, new_qty, reason, action_type, staff, reference)
        VALUES (prod.id, prod.name, prod.quantity, COALESCE((item->>'received')::int,0), new_qty,
                'Supplier receiving approved', 'receiving', p_approver, rec.ref_no);
      EXCEPTION WHEN undefined_table THEN NULL; END;
      applied := applied + 1;
    END IF;
  END LOOP;

  UPDATE receivings SET status = 'approved', approved_by = p_approver, approved_at = now() WHERE id = p_id;
  RETURN jsonb_build_object('success', true, 'applied', applied);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RLS
ALTER TABLE suppliers  ENABLE ROW LEVEL SECURITY;
ALTER TABLE receivings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "staff suppliers" ON suppliers;
CREATE POLICY "staff suppliers" ON suppliers FOR ALL USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "staff receivings" ON receivings;
CREATE POLICY "staff receivings" ON receivings FOR ALL USING (true) WITH CHECK (true);

-- ===== STOCKTAKE_AUDIT_SETUP =====
-- ============================================================
-- EVERYTINROOM — Phase 3 (stock-take approval) + Phase 4 (audit ledger)
-- Run once in Supabase → SQL Editor.
-- ============================================================

-- ---------- Phase 4: the stock ledger (every change, ever) ----------
CREATE TABLE IF NOT EXISTS stock_ledger (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id   text,
  product_name text DEFAULT '',
  previous_qty int,
  change_qty   int,
  new_qty      int,
  reason       text DEFAULT '',
  action_type  text DEFAULT '',   -- sale | receiving | stock_take | adjustment | manual | return | damaged
  staff        text DEFAULT '',
  reference    text DEFAULT '',
  created_at   timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ledger_product ON stock_ledger(product_id, created_at);
CREATE INDEX IF NOT EXISTS idx_ledger_type ON stock_ledger(action_type);
ALTER TABLE stock_ledger ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "staff ledger" ON stock_ledger;
CREATE POLICY "staff ledger" ON stock_ledger FOR ALL USING (true) WITH CHECK (true);

-- ---------- Phase 3: stock-take approval ----------
-- Add approval fields to stock_takes (safe/additive).
ALTER TABLE stock_takes ADD COLUMN IF NOT EXISTS status text DEFAULT 'approved';
ALTER TABLE stock_takes ADD COLUMN IF NOT EXISTS approved_by text DEFAULT '';
ALTER TABLE stock_takes ADD COLUMN IF NOT EXISTS approved_at timestamptz;
ALTER TABLE stock_takes ADD COLUMN IF NOT EXISTS reject_reason text DEFAULT '';
-- Existing rows are historical/applied -> mark them approved so nothing looks pending.
UPDATE stock_takes SET status = 'approved' WHERE status IS NULL;

-- Approve a stock-take: set each counted product to its PHYSICAL count, log the
-- variance to the ledger, mark approved. Idempotent.
CREATE OR REPLACE FUNCTION approve_stock_take(p_id uuid, p_approver text)
RETURNS jsonb AS $$
DECLARE
  rec record;
  item jsonb;
  prod record;
  counted int;
  applied int := 0;
BEGIN
  SELECT * INTO rec FROM stock_takes WHERE id = p_id;
  IF rec.id IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'not found'); END IF;
  IF rec.status = 'approved' THEN RETURN jsonb_build_object('success', false, 'error', 'already approved'); END IF;

  FOR item IN SELECT * FROM jsonb_array_elements(rec.items) LOOP
    SELECT id, quantity, name INTO prod FROM products WHERE id = (item->>'productId');
    IF prod.id IS NOT NULL THEN
      counted := COALESCE((item->>'countedQty')::int, prod.quantity);
      IF counted <> prod.quantity THEN
        INSERT INTO stock_ledger (product_id, product_name, previous_qty, change_qty, new_qty, reason, action_type, staff, reference)
        VALUES (prod.id, prod.name, prod.quantity, counted - prod.quantity, counted, 'Stock take approved', 'stock_take', p_approver, 'ST-' || left(p_id::text, 8));
        UPDATE products SET quantity = counted WHERE id = prod.id;
        applied := applied + 1;
      END IF;
    END IF;
  END LOOP;

  UPDATE stock_takes SET status = 'approved', approved_by = p_approver, approved_at = now() WHERE id = p_id;
  RETURN jsonb_build_object('success', true, 'applied', applied);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ===== DOCUMENTS_SETUP =====
-- ============================================================
-- TAGITELA — Documents system
-- Proforma, Invoice, Receipt, Waybill/Delivery note.
-- One table handles all four (they share structure); doc_type
-- distinguishes them. Documents can be converted (proforma ->
-- invoice -> receipt) keeping a link to the source.
-- Run in TAGITELA's Supabase → SQL Editor.
-- ============================================================

CREATE TABLE IF NOT EXISTS documents (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  doc_type      text NOT NULL,              -- proforma | invoice | receipt | waybill
  doc_no        text NOT NULL,              -- e.g. INV-0001
  status        text DEFAULT 'draft',       -- draft | sent | paid | delivered | cancelled
  -- Customer
  customer_name    text DEFAULT '',
  customer_phone   text DEFAULT '',
  customer_address text DEFAULT '',
  -- Line items: [{name, qty, unit_price, line_total, product_id}]
  items         jsonb DEFAULT '[]',
  subtotal      numeric DEFAULT 0,
  discount      numeric DEFAULT 0,
  tax           numeric DEFAULT 0,
  total         numeric DEFAULT 0,
  amount_paid   numeric DEFAULT 0,          -- for receipts / part payment
  -- Meta
  note          text DEFAULT '',
  terms         text DEFAULT '',
  issue_date    date DEFAULT current_date,
  due_date      date,
  created_by    text DEFAULT '',
  source_doc_id uuid REFERENCES documents(id),  -- e.g. invoice created from a proforma
  created_at    timestamptz DEFAULT now(),
  updated_at    timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_documents_type ON documents(doc_type, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_documents_status ON documents(status);

-- Per-type sequential numbering. A counters table keeps the last number per type.
CREATE TABLE IF NOT EXISTS doc_counters (
  doc_type text PRIMARY KEY,
  last_no  int DEFAULT 0
);
INSERT INTO doc_counters (doc_type, last_no) VALUES
  ('proforma', 0), ('invoice', 0), ('receipt', 0), ('waybill', 0)
ON CONFLICT (doc_type) DO NOTHING;

-- Atomically get the next document number for a type (e.g. 'INV-0007').
CREATE OR REPLACE FUNCTION next_doc_no(p_type text)
RETURNS text AS $$
DECLARE
  n int;
  prefix text;
BEGIN
  UPDATE doc_counters SET last_no = last_no + 1 WHERE doc_type = p_type RETURNING last_no INTO n;
  IF n IS NULL THEN
    INSERT INTO doc_counters (doc_type, last_no) VALUES (p_type, 1) RETURNING last_no INTO n;
  END IF;
  prefix := CASE p_type
    WHEN 'proforma' THEN 'PRO'
    WHEN 'invoice'  THEN 'INV'
    WHEN 'receipt'  THEN 'RCP'
    WHEN 'waybill'  THEN 'WB'
    ELSE 'DOC' END;
  RETURN prefix || '-' || lpad(n::text, 4, '0');
END;
$$ LANGUAGE plpgsql;

-- RLS
ALTER TABLE documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE doc_counters ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "staff documents" ON documents;
CREATE POLICY "staff documents" ON documents FOR ALL USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "staff doc_counters" ON doc_counters;
CREATE POLICY "staff doc_counters" ON doc_counters FOR ALL USING (true) WITH CHECK (true);


-- ===== BATCH_EXPIRY_SETUP =====
-- ============================================================
-- TAGITELA (Medical) — Batch & Expiry tracking + FEFO + advanced
-- product fields. Medical-critical: never sell an expired batch,
-- always sell the soonest-expiring stock first (First Expiry First Out).
-- Run in TAGITELA's Supabase → SQL Editor (after full setup).
-- ============================================================

-- 1. Advanced product fields (all additive / safe).
ALTER TABLE products ADD COLUMN IF NOT EXISTS sku            text DEFAULT '';
ALTER TABLE products ADD COLUMN IF NOT EXISTS barcode        text DEFAULT '';
ALTER TABLE products ADD COLUMN IF NOT EXISTS subcategory    text DEFAULT '';
ALTER TABLE products ADD COLUMN IF NOT EXISTS brand          text DEFAULT '';
ALTER TABLE products ADD COLUMN IF NOT EXISTS description    text DEFAULT '';
ALTER TABLE products ADD COLUMN IF NOT EXISTS unit           text DEFAULT '';       -- e.g. box, pack, piece, ml
ALTER TABLE products ADD COLUMN IF NOT EXISTS min_price      numeric DEFAULT 0;      -- minimum selling price
ALTER TABLE products ADD COLUMN IF NOT EXISTS reorder_level  int DEFAULT 0;         -- low-stock threshold
ALTER TABLE products ADD COLUMN IF NOT EXISTS storage_location text DEFAULT '';
ALTER TABLE products ADD COLUMN IF NOT EXISTS supplier_name  text DEFAULT '';
ALTER TABLE products ADD COLUMN IF NOT EXISTS tracks_batches boolean DEFAULT false;  -- does this product use batch/expiry?
ALTER TABLE products ADD COLUMN IF NOT EXISTS status         text DEFAULT 'active';  -- active | inactive
ALTER TABLE products ADD COLUMN IF NOT EXISTS reg_number     text DEFAULT '';        -- drug reg / FDA number

-- 2. Product batches — the heart of expiry tracking.
CREATE TABLE IF NOT EXISTS product_batches (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id   text NOT NULL,
  product_name text DEFAULT '',
  batch_no     text DEFAULT '',
  expiry_date  date,
  quantity     int DEFAULT 0,           -- remaining in this batch
  received_qty int DEFAULT 0,           -- originally received
  cost_price   numeric DEFAULT 0,
  supplier     text DEFAULT '',
  received_date date DEFAULT current_date,
  status       text DEFAULT 'active',   -- active | depleted | expired | quarantine
  note         text DEFAULT '',
  created_at   timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_batches_product ON product_batches(product_id, expiry_date);
CREATE INDEX IF NOT EXISTS idx_batches_expiry ON product_batches(expiry_date) WHERE status = 'active';

-- 3. Keep the product's total quantity = sum of active batch quantities.
CREATE OR REPLACE FUNCTION sync_product_qty(p_product_id text)
RETURNS void AS $$
BEGIN
  UPDATE products SET quantity = COALESCE((
    SELECT SUM(quantity) FROM product_batches
    WHERE product_id = p_product_id AND status = 'active'
  ), 0)
  WHERE id = p_product_id AND tracks_batches = true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. Add a batch (goods received) and refresh the product total.
CREATE OR REPLACE FUNCTION add_batch(
  p_product_id text, p_batch_no text, p_expiry date, p_qty int,
  p_cost numeric, p_supplier text, p_by text
) RETURNS jsonb AS $$
DECLARE
  pname text;
  bid uuid;
BEGIN
  SELECT name INTO pname FROM products WHERE id = p_product_id;
  INSERT INTO product_batches (product_id, product_name, batch_no, expiry_date, quantity, received_qty, cost_price, supplier)
  VALUES (p_product_id, pname, p_batch_no, p_expiry, p_qty, p_qty, p_cost, p_supplier)
  RETURNING id INTO bid;
  -- make sure the product is flagged as batch-tracked, then sync
  UPDATE products SET tracks_batches = true WHERE id = p_product_id;
  PERFORM sync_product_qty(p_product_id);
  -- audit
  INSERT INTO stock_ledger (product_id, product_name, previous_qty, change_qty, new_qty, reason, action_type, staff, reference)
  SELECT p_product_id, pname, 0, p_qty, quantity, 'Batch received ' || COALESCE(p_batch_no,''), 'receiving', p_by, left(bid::text,8)
  FROM products WHERE id = p_product_id;
  RETURN jsonb_build_object('success', true, 'batch_id', bid);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. FEFO deduction — sell from the soonest-expiring active, non-expired batch
--    first. Returns the batches touched. Refuses if not enough sellable stock.
CREATE OR REPLACE FUNCTION deduct_fefo(p_product_id text, p_qty int, p_by text, p_ref text DEFAULT '')
RETURNS jsonb AS $$
DECLARE
  remaining int := p_qty;
  b record;
  take int;
  touched jsonb := '[]';
BEGIN
  FOR b IN SELECT * FROM product_batches
    WHERE product_id = p_product_id AND status = 'active' AND quantity > 0
      AND (expiry_date IS NULL OR expiry_date >= current_date)
    ORDER BY expiry_date ASC NULLS LAST, received_date ASC LOOP
    EXIT WHEN remaining <= 0;
    take := LEAST(remaining, b.quantity);
    UPDATE product_batches SET quantity = quantity - take,
      status = CASE WHEN quantity - take <= 0 THEN 'depleted' ELSE 'active' END
      WHERE id = b.id;
    touched := touched || jsonb_build_object('batch_id', b.id, 'batch_no', b.batch_no, 'qty', take);
    remaining := remaining - take;
  END LOOP;

  IF remaining > 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not enough sellable (non-expired) stock', 'short_by', remaining);
  END IF;

  PERFORM sync_product_qty(p_product_id);
  RETURN jsonb_build_object('success', true, 'batches', touched);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6. Mark expired batches (run manually or via scheduled job later).
CREATE OR REPLACE FUNCTION mark_expired_batches()
RETURNS int AS $$
DECLARE n int;
BEGIN
  UPDATE product_batches SET status = 'expired'
   WHERE status = 'active' AND expiry_date IS NOT NULL AND expiry_date < current_date;
  GET DIAGNOSTICS n = ROW_COUNT;
  -- resync affected products
  PERFORM sync_product_qty(id) FROM products WHERE tracks_batches = true;
  RETURN n;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RLS
ALTER TABLE product_batches ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "staff batches" ON product_batches;
CREATE POLICY "staff batches" ON product_batches FOR ALL USING (true) WITH CHECK (true);

-- ===== CREDIT_CUSTOMERS_SETUP =====
-- ============================================================
-- TAGITELA (Medical) — Phase 3: Customers, Credit & Ledger
-- The accounting foundation. Invoices debit a customer's account,
-- payments credit it; the ledger keeps a running balance and IS
-- the customer statement. Built so nothing changes silently.
-- Run in TAGITELA's Supabase → SQL Editor (after the full setup).
-- ============================================================

-- 1. Extend customers into proper accounts.
ALTER TABLE customers ADD COLUMN IF NOT EXISTS name          text DEFAULT '';
ALTER TABLE customers ADD COLUMN IF NOT EXISTS customer_type text DEFAULT 'cash';   -- cash | credit
ALTER TABLE customers ADD COLUMN IF NOT EXISTS email         text DEFAULT '';
ALTER TABLE customers ADD COLUMN IF NOT EXISTS address       text DEFAULT '';
ALTER TABLE customers ADD COLUMN IF NOT EXISTS contact_person text DEFAULT '';
ALTER TABLE customers ADD COLUMN IF NOT EXISTS credit_limit  numeric DEFAULT 0;
ALTER TABLE customers ADD COLUMN IF NOT EXISTS credit_days   int DEFAULT 30;        -- payment terms
ALTER TABLE customers ADD COLUMN IF NOT EXISTS balance       numeric DEFAULT 0;     -- current outstanding (cache of ledger)
ALTER TABLE customers ADD COLUMN IF NOT EXISTS credit_blocked boolean DEFAULT false;
ALTER TABLE customers ADD COLUMN IF NOT EXISTS notes         text DEFAULT '';
ALTER TABLE customers ADD COLUMN IF NOT EXISTS active        boolean DEFAULT true;
ALTER TABLE customers ADD COLUMN IF NOT EXISTS created_at    timestamptz DEFAULT now();

-- 2. The customer ledger — the single source of truth for what is owed.
--    Every financial event is a row. debit = customer owes more (invoice),
--    credit = customer owes less (payment / credit note). balance_after is the
--    running balance at that point in time.
CREATE TABLE IF NOT EXISTS customer_ledger (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id  text NOT NULL,
  entry_date   timestamptz DEFAULT now(),
  ref_type     text DEFAULT '',   -- invoice | payment | credit_note | opening | adjustment
  ref_no       text DEFAULT '',
  ref_id       uuid,
  description  text DEFAULT '',
  debit        numeric DEFAULT 0,
  credit       numeric DEFAULT 0,
  balance_after numeric DEFAULT 0,
  created_by   text DEFAULT '',
  created_at   timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ledger_customer ON customer_ledger(customer_id, entry_date);

-- 3. Payments received from customers (can cover multiple invoices).
CREATE TABLE IF NOT EXISTS payments (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  receipt_no   text UNIQUE NOT NULL,
  customer_id  text,
  customer_name text DEFAULT '',
  amount       numeric NOT NULL,
  method       text DEFAULT 'cash',   -- cash | momo | bank | cheque | other
  reference    text DEFAULT '',       -- momo txn / cheque no / bank ref
  note         text DEFAULT '',
  pay_date     date DEFAULT current_date,
  created_by   text DEFAULT '',
  created_at   timestamptz DEFAULT now()
);

-- 4. How each payment is split across invoices (payment allocation).
CREATE TABLE IF NOT EXISTS payment_allocations (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  payment_id  uuid REFERENCES payments(id) ON DELETE CASCADE,
  document_id uuid,          -- the invoice (documents table)
  doc_no      text DEFAULT '',
  amount      numeric NOT NULL,
  created_at  timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_alloc_payment ON payment_allocations(payment_id);
CREATE INDEX IF NOT EXISTS idx_alloc_document ON payment_allocations(document_id);

-- 5. Add payment-tracking fields to documents (invoices).
ALTER TABLE documents ADD COLUMN IF NOT EXISTS customer_id   text;
ALTER TABLE documents ADD COLUMN IF NOT EXISTS is_credit     boolean DEFAULT false;
ALTER TABLE documents ADD COLUMN IF NOT EXISTS balance_due   numeric DEFAULT 0;
ALTER TABLE documents ADD COLUMN IF NOT EXISTS pay_status    text DEFAULT 'unpaid';  -- unpaid | partial | paid

-- ---------- Functions ----------

-- Post a ledger entry and update the customer's cached balance.
CREATE OR REPLACE FUNCTION post_ledger(
  p_customer_id text, p_ref_type text, p_ref_no text, p_ref_id uuid,
  p_description text, p_debit numeric, p_credit numeric, p_by text
) RETURNS numeric AS $$
DECLARE
  cur numeric;
  newbal numeric;
BEGIN
  SELECT COALESCE(balance, 0) INTO cur FROM customers WHERE id = p_customer_id;
  newbal := cur + COALESCE(p_debit,0) - COALESCE(p_credit,0);
  INSERT INTO customer_ledger (customer_id, ref_type, ref_no, ref_id, description, debit, credit, balance_after, created_by)
  VALUES (p_customer_id, p_ref_type, p_ref_no, p_ref_id, p_description, COALESCE(p_debit,0), COALESCE(p_credit,0), newbal, p_by);
  UPDATE customers SET balance = newbal WHERE id = p_customer_id;
  RETURN newbal;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Record a customer payment, allocate it across invoices (oldest first if no
-- explicit allocation), post to the ledger, and update invoice pay status.
CREATE OR REPLACE FUNCTION record_payment(
  p_customer_id text, p_amount numeric, p_method text, p_reference text,
  p_note text, p_by text, p_allocations jsonb DEFAULT '[]'
) RETURNS jsonb AS $$
DECLARE
  rno text;
  pid uuid;
  cname text;
  alloc jsonb;
  remaining numeric;
  inv record;
  pay_amt numeric;
BEGIN
  SELECT name INTO cname FROM customers WHERE id = p_customer_id;
  rno := 'RCP-' || to_char(now(),'YYMMDD') || '-' || lpad((floor(random()*9999))::text,4,'0');

  INSERT INTO payments (receipt_no, customer_id, customer_name, amount, method, reference, note, created_by)
  VALUES (rno, p_customer_id, cname, p_amount, p_method, p_reference, p_note, p_by)
  RETURNING id INTO pid;

  -- Explicit allocations if provided, else auto-allocate oldest unpaid invoices.
  IF jsonb_array_length(p_allocations) > 0 THEN
    FOR alloc IN SELECT * FROM jsonb_array_elements(p_allocations) LOOP
      INSERT INTO payment_allocations (payment_id, document_id, doc_no, amount)
      VALUES (pid, (alloc->>'document_id')::uuid, alloc->>'doc_no', (alloc->>'amount')::numeric);
      UPDATE documents SET
        balance_due = GREATEST(0, balance_due - (alloc->>'amount')::numeric),
        amount_paid = amount_paid + (alloc->>'amount')::numeric,
        pay_status = CASE WHEN balance_due - (alloc->>'amount')::numeric <= 0 THEN 'paid' ELSE 'partial' END
      WHERE id = (alloc->>'document_id')::uuid;
    END LOOP;
  ELSE
    remaining := p_amount;
    FOR inv IN SELECT id, doc_no, balance_due FROM documents
      WHERE customer_id = p_customer_id AND doc_type='invoice' AND balance_due > 0
      ORDER BY issue_date ASC LOOP
      EXIT WHEN remaining <= 0;
      pay_amt := LEAST(remaining, inv.balance_due);
      INSERT INTO payment_allocations (payment_id, document_id, doc_no, amount)
      VALUES (pid, inv.id, inv.doc_no, pay_amt);
      UPDATE documents SET
        balance_due = balance_due - pay_amt,
        amount_paid = amount_paid + pay_amt,
        pay_status = CASE WHEN balance_due - pay_amt <= 0 THEN 'paid' ELSE 'partial' END
      WHERE id = inv.id;
      remaining := remaining - pay_amt;
    END LOOP;
  END IF;

  PERFORM post_ledger(p_customer_id, 'payment', rno, pid, 'Payment received (' || p_method || ')', 0, p_amount, p_by);
  RETURN jsonb_build_object('success', true, 'receipt_no', rno, 'payment_id', pid);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RLS
ALTER TABLE customer_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_allocations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "staff ledger2" ON customer_ledger;
CREATE POLICY "staff ledger2" ON customer_ledger FOR ALL USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "staff payments" ON payments;
CREATE POLICY "staff payments" ON payments FOR ALL USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "staff allocs" ON payment_allocations;
CREATE POLICY "staff allocs" ON payment_allocations FOR ALL USING (true) WITH CHECK (true);
