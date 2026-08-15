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
