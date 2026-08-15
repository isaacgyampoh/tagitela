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
