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
