-- ============================================================
-- TAGITELA — WhatsApp/website order numbering
-- Sequential order numbers (WA-0001) for orders placed from the
-- online shop. Run in Supabase → SQL Editor.
-- ============================================================

-- Reuse the doc_counters table (from DOCUMENTS_SETUP) for a 'wa_order' counter.
INSERT INTO doc_counters (doc_type, last_no) VALUES ('wa_order', 0)
ON CONFLICT (doc_type) DO NOTHING;

CREATE OR REPLACE FUNCTION next_order_no()
RETURNS text AS $$
DECLARE n int;
BEGIN
  UPDATE doc_counters SET last_no = last_no + 1 WHERE doc_type = 'wa_order' RETURNING last_no INTO n;
  IF n IS NULL THEN
    INSERT INTO doc_counters (doc_type, last_no) VALUES ('wa_order', 1) RETURNING last_no INTO n;
  END IF;
  RETURN 'WA-' || lpad(n::text, 4, '0');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Make sure the columns the website order writes exist.
ALTER TABLE whatsapp_orders ADD COLUMN IF NOT EXISTS source         text DEFAULT '';
ALTER TABLE whatsapp_orders ADD COLUMN IF NOT EXISTS details_filled boolean DEFAULT false;
ALTER TABLE whatsapp_orders ADD COLUMN IF NOT EXISTS subtotal       numeric DEFAULT 0;
