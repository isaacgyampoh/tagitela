import { SHOP, money } from '../lib/utils'

// Opens a print window with a clean, professional document (proforma / invoice /
// receipt / waybill). Prints to paper or "Save as PDF".
const TITLES = { proforma: 'PROFORMA INVOICE', invoice: 'INVOICE', receipt: 'RECEIPT', waybill: 'WAYBILL / DELIVERY NOTE' }

export function printDocument(d) {
  const items = typeof d.items === 'string' ? JSON.parse(d.items) : (d.items || [])
  const title = TITLES[d.doc_type] || 'DOCUMENT'
  const isWaybill = d.doc_type === 'waybill'
  const isReceipt = d.doc_type === 'receipt'

  const rows = items.map(it => `
    <tr>
      <td>${escapeHtml(it.name)}</td>
      <td class="c">${it.qty}</td>
      ${isWaybill ? '' : `<td class="r">${money(it.unit_price)}</td><td class="r">${money(it.line_total)}</td>`}
    </tr>`).join('')

  const totalsBlock = isWaybill ? '' : `
    <table class="totals">
      <tr><td>Subtotal</td><td class="r">${money(d.subtotal)}</td></tr>
      ${num(d.discount) ? `<tr><td>Discount</td><td class="r">- ${money(d.discount)}</td></tr>` : ''}
      ${num(d.tax) ? `<tr><td>Tax / Charges</td><td class="r">${money(d.tax)}</td></tr>` : ''}
      <tr class="grand"><td>Total</td><td class="r">${money(d.total)}</td></tr>
      ${isReceipt ? `<tr class="paid"><td>Amount Paid</td><td class="r">${money(d.amount_paid || d.total)}</td></tr>` : ''}
    </table>`

  const html = `<!DOCTYPE html><html><head><meta charset="utf-8"><title>${d.doc_no}</title>
  <style>
    * { margin:0; padding:0; box-sizing:border-box; }
    body { font-family: -apple-system, Segoe UI, Roboto, sans-serif; color:#1a1a1a; padding:32px; font-size:13px; line-height:1.5; }
    .top { display:flex; justify-content:space-between; align-items:flex-start; border-bottom:2px solid #111; padding-bottom:16px; margin-bottom:20px; }
    .shop { font-size:22px; font-weight:800; letter-spacing:-0.02em; }
    .shop-sub { font-size:11px; color:#666; margin-top:2px; }
    .doc-title { text-align:right; }
    .doc-title h1 { font-size:18px; font-weight:800; letter-spacing:0.02em; }
    .doc-title .no { font-size:13px; color:#444; margin-top:2px; font-weight:600; }
    .doc-title .date { font-size:11px; color:#888; margin-top:2px; }
    .parties { display:flex; justify-content:space-between; gap:24px; margin-bottom:20px; }
    .party h3 { font-size:10px; text-transform:uppercase; letter-spacing:0.08em; color:#999; margin-bottom:4px; }
    .party p { font-size:13px; }
    .party .nm { font-weight:700; }
    table.items { width:100%; border-collapse:collapse; margin-bottom:16px; }
    table.items th { text-align:left; font-size:10px; text-transform:uppercase; letter-spacing:0.05em; color:#999; border-bottom:1px solid #ddd; padding:8px 6px; }
    table.items td { padding:9px 6px; border-bottom:1px solid #f0f0f0; }
    .c { text-align:center; } .r { text-align:right; }
    table.totals { margin-left:auto; width:260px; border-collapse:collapse; }
    table.totals td { padding:5px 6px; font-size:13px; }
    table.totals tr.grand td { font-weight:800; font-size:15px; border-top:2px solid #111; padding-top:8px; }
    table.totals tr.paid td { color:#059669; font-weight:700; }
    .note { margin-top:24px; font-size:12px; color:#555; }
    .note strong { color:#111; }
    .sign { margin-top:48px; display:flex; justify-content:space-between; gap:40px; }
    .sign div { flex:1; border-top:1px solid #999; padding-top:6px; font-size:11px; color:#777; text-align:center; }
    .foot { margin-top:32px; text-align:center; font-size:11px; color:#999; border-top:1px solid #eee; padding-top:12px; }
    @media print { body { padding:0; } }
  </style></head><body>
    <div class="top">
      <div>
        <div class="shop">${escapeHtml(SHOP.name || 'TAGITELA')}</div>
        ${SHOP.address ? `<div class="shop-sub">${escapeHtml(SHOP.address)}</div>` : ''}
        ${SHOP.phone ? `<div class="shop-sub">${escapeHtml(SHOP.phone)}</div>` : ''}
        ${SHOP.website ? `<div class="shop-sub">${escapeHtml(SHOP.website)}</div>` : ''}
      </div>
      <div class="doc-title">
        <h1>${title}</h1>
        <div class="no">${escapeHtml(d.doc_no)}</div>
        <div class="date">Date: ${d.issue_date || ''}</div>
        ${d.due_date && !isReceipt && !isWaybill ? `<div class="date">Due: ${d.due_date}</div>` : ''}
      </div>
    </div>

    <div class="parties">
      <div class="party">
        <h3>${isWaybill ? 'Deliver To' : 'Bill To'}</h3>
        <p class="nm">${escapeHtml(d.customer_name || '')}</p>
        ${d.customer_phone ? `<p>${escapeHtml(d.customer_phone)}</p>` : ''}
        ${d.customer_address ? `<p>${escapeHtml(d.customer_address)}</p>` : ''}
      </div>
    </div>

    <table class="items">
      <thead><tr><th>Item</th><th class="c">Qty</th>${isWaybill ? '' : '<th class="r">Unit Price</th><th class="r">Total</th>'}</tr></thead>
      <tbody>${rows}</tbody>
    </table>

    ${totalsBlock}

    ${d.note ? `<div class="note"><strong>Note:</strong> ${escapeHtml(d.note)}</div>` : ''}
    ${d.terms && !isWaybill && !isReceipt ? `<div class="note"><strong>Terms:</strong> ${escapeHtml(d.terms)}</div>` : ''}

    ${isWaybill ? `<div class="sign"><div>Received by (name & signature)</div><div>Date</div></div>` : ''}

    <div class="foot">
      ${isReceipt ? 'Thank you for your business.' : d.doc_type === 'proforma' ? 'This is a proforma invoice, not a demand for payment.' : 'Thank you for your business.'}
    </div>

    <script>window.onload = () => { window.print(); }</script>
  </body></html>`

  const w = window.open('', '_blank', 'width=800,height=1000')
  if (!w) { alert('Please allow pop-ups to print'); return }
  w.document.write(html)
  w.document.close()
}

function num(n) { return Number(n) || 0 }
function escapeHtml(s) { return String(s || '').replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c])) }
