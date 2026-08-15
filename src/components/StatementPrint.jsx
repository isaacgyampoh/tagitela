import { SHOP, money } from '../lib/utils'

// Print/PDF a customer account statement (the ledger).
export function printStatement(customer, ledger) {
  const rows = (ledger || []).map(e => `
    <tr>
      <td>${new Date(e.entry_date).toLocaleDateString('en-GB')}</td>
      <td>${esc(e.ref_no)}</td>
      <td>${esc(e.description)}</td>
      <td class="r">${num(e.debit) ? money(e.debit) : '—'}</td>
      <td class="r">${num(e.credit) ? money(e.credit) : '—'}</td>
      <td class="r b">${money(e.balance_after)}</td>
    </tr>`).join('')

  const html = `<!DOCTYPE html><html><head><meta charset="utf-8"><title>Statement — ${esc(customer.name)}</title>
  <style>
    *{margin:0;padding:0;box-sizing:border-box}
    body{font-family:-apple-system,Segoe UI,Roboto,sans-serif;color:#1a1a1a;padding:32px;font-size:13px}
    .top{display:flex;justify-content:space-between;border-bottom:2px solid #111;padding-bottom:16px;margin-bottom:20px}
    .shop{font-size:22px;font-weight:800}
    .sub{font-size:11px;color:#666;margin-top:2px}
    h1{font-size:18px;font-weight:800;text-align:right}
    .cust{margin-bottom:16px}
    .cust h3{font-size:10px;text-transform:uppercase;letter-spacing:.08em;color:#999;margin-bottom:4px}
    .cust .nm{font-weight:700;font-size:15px}
    table{width:100%;border-collapse:collapse;margin-top:8px}
    th{text-align:left;font-size:10px;text-transform:uppercase;color:#999;border-bottom:1px solid #ddd;padding:8px 6px}
    td{padding:8px 6px;border-bottom:1px solid #f2f2f2;font-size:12px}
    .r{text-align:right}.b{font-weight:700}
    .summary{margin-top:20px;margin-left:auto;width:260px}
    .summary .box{background:#f8f8f8;border-radius:8px;padding:14px;text-align:right}
    .summary .lbl{font-size:11px;color:#888}
    .summary .amt{font-size:22px;font-weight:800;color:#dc2626}
    .foot{margin-top:32px;text-align:center;font-size:11px;color:#999;border-top:1px solid #eee;padding-top:12px}
    @media print{body{padding:0}}
  </style></head><body>
    <div class="top">
      <div>
        <div class="shop">${esc(SHOP.name || 'TAGITELA')}</div>
        ${SHOP.address ? `<div class="sub">${esc(SHOP.address)}</div>` : ''}
        ${SHOP.phone ? `<div class="sub">${esc(SHOP.phone)}</div>` : ''}
      </div>
      <div><h1>ACCOUNT STATEMENT</h1><div class="sub" style="text-align:right">As at ${new Date().toLocaleDateString('en-GB')}</div></div>
    </div>
    <div class="cust">
      <h3>Statement For</h3>
      <div class="nm">${esc(customer.name || '')}</div>
      ${customer.phone ? `<div class="sub">${esc(customer.phone)}</div>` : ''}
      ${customer.address ? `<div class="sub">${esc(customer.address)}</div>` : ''}
    </div>
    <table>
      <thead><tr><th>Date</th><th>Ref</th><th>Description</th><th class="r">Debit</th><th class="r">Credit</th><th class="r">Balance</th></tr></thead>
      <tbody>${rows || '<tr><td colspan="6" style="text-align:center;padding:24px;color:#999">No transactions</td></tr>'}</tbody>
    </table>
    <div class="summary"><div class="box"><div class="lbl">Total Outstanding</div><div class="amt">${money(customer.balance)}</div></div></div>
    <div class="foot">Please settle outstanding balances within your agreed credit terms. Thank you.</div>
    <script>window.onload=()=>window.print()</script>
  </body></html>`

  const w = window.open('', '_blank', 'width=800,height=1000')
  if (!w) { alert('Please allow pop-ups to print'); return }
  w.document.write(html); w.document.close()
}

function num(n){return Number(n)||0}
function esc(s){return String(s||'').replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]))}
