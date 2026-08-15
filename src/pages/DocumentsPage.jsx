import { useState, useEffect, useMemo } from 'react'
import { useStore } from '../hooks/useStore'
import { getSupabase } from '../lib/supabase'
import { money, num, today } from '../lib/utils'
import { SHOP } from '../lib/utils'
import toast from 'react-hot-toast'
import { printDocument } from '../components/DocumentPrint'

const DOC_TYPES = [
  { key: 'proforma', label: 'Proforma', desc: 'Quote before payment' },
  { key: 'invoice', label: 'Invoice', desc: 'Bill for payment' },
  { key: 'receipt', label: 'Receipt', desc: 'Proof of payment' },
  { key: 'waybill', label: 'Waybill', desc: 'Delivery note' },
]

const emptyDoc = () => ({
  id: '', doc_type: 'invoice', customer_id: '', customer_name: '', customer_phone: '', customer_address: '',
  is_credit: false, items: [{ name: '', qty: 1, unit_price: 0 }], discount: 0, tax: 0, note: '', terms: '',
  issue_date: today(), due_date: '', amount_paid: 0,
})

export default function DocumentsPage() {
  const { products, user } = useStore()
  const sb = getSupabase()
  const [tab, setTab] = useState('invoice')
  const [docs, setDocs] = useState([])
  const [customers, setCustomers] = useState([])
  const [loading, setLoading] = useState(true)
  const [modal, setModal] = useState(false)
  const [form, setForm] = useState(emptyDoc())
  const [saving, setSaving] = useState(false)
  const [prodQuery, setProdQuery] = useState('')
  const [activeItemIdx, setActiveItemIdx] = useState(null)
  const [custQuery, setCustQuery] = useState('')
  const [showCustList, setShowCustList] = useState(false)

  const load = async () => {
    setLoading(true)
    const [d, c] = await Promise.all([
      sb.from('documents').select('*').order('created_at', { ascending: false }).limit(200),
      sb.from('customers').select('*').order('name', { ascending: true }).limit(500),
    ])
    setDocs(d.data || [])
    setCustomers(c.data || [])
    setLoading(false)
  }
  useEffect(() => { load() }, []) // eslint-disable-line

  const shown = docs.filter(d => d.doc_type === tab)

  // Line item maths
  const subtotal = useMemo(() => form.items.reduce((a, i) => a + num(i.qty) * num(i.unit_price), 0), [form.items])
  const total = Math.max(0, subtotal - num(form.discount) + num(form.tax))

  const openNew = (type) => { setForm({ ...emptyDoc(), doc_type: type }); setModal(true) }
  const openEdit = (d) => {
    setForm({
      id: d.id, doc_type: d.doc_type, customer_id: d.customer_id || '', is_credit: d.is_credit || false, customer_name: d.customer_name, customer_phone: d.customer_phone,
      customer_address: d.customer_address, items: (typeof d.items === 'string' ? JSON.parse(d.items) : d.items) || [{ name: '', qty: 1, unit_price: 0 }],
      discount: d.discount, tax: d.tax, note: d.note, terms: d.terms, issue_date: d.issue_date, due_date: d.due_date || '', amount_paid: d.amount_paid,
    })
    setModal(true)
  }

  const setItem = (i, field, val) => { const items = [...form.items]; items[i][field] = val; setForm({ ...form, items }) }
  const addItem = () => setForm({ ...form, items: [...form.items, { name: '', qty: 1, unit_price: 0 }] })
  const rmItem = (i) => { const items = [...form.items]; items.splice(i, 1); setForm({ ...form, items: items.length ? items : [{ name: '', qty: 1, unit_price: 0 }] }) }

  const pickProduct = (i, p) => { setItem(i, 'name', p.name); setItem(i, 'unit_price', p.price); setProdQuery(''); setActiveItemIdx(null) }
  const prodMatches = useMemo(() => {
    if (!prodQuery.trim()) return []
    const q = prodQuery.toLowerCase()
    return products.filter(p => p.name.toLowerCase().includes(q)).slice(0, 6)
  }, [prodQuery, products])

  const save = async (thenPrint = false) => {
    if (!form.customer_name.trim()) { toast.error('Enter customer name'); return }
    const validItems = form.items.filter(i => i.name.trim() && num(i.qty) > 0)
    if (validItems.length === 0) { toast.error('Add at least one item'); return }
    setSaving(true)
    const items = validItems.map(i => ({ name: i.name.trim(), qty: num(i.qty), unit_price: num(i.unit_price), line_total: num(i.qty) * num(i.unit_price) }))
    const sub = items.reduce((a, i) => a + i.line_total, 0)
    const tot = Math.max(0, sub - num(form.discount) + num(form.tax))

    const payload = {
      doc_type: form.doc_type, customer_id: form.customer_id || null,
      customer_name: form.customer_name.trim(), customer_phone: form.customer_phone.trim(),
      customer_address: form.customer_address.trim(), items: JSON.stringify(items), subtotal: sub, discount: num(form.discount),
      tax: num(form.tax), total: tot, amount_paid: form.doc_type === 'receipt' ? (num(form.amount_paid) || tot) : num(form.amount_paid),
      note: form.note.trim(), terms: form.terms.trim(), issue_date: form.issue_date || today(), due_date: form.due_date || null,
      created_by: user?.name || '', updated_at: new Date().toISOString(),
    }

    // Credit invoice: mark it, set the outstanding balance, unpaid.
    const isCreditInvoice = form.doc_type === 'invoice' && form.is_credit && form.customer_id
    if (isCreditInvoice) { payload.is_credit = true; payload.balance_due = tot; payload.pay_status = 'unpaid' }

    let saved
    if (form.id) {
      const { data, error } = await sb.from('documents').update(payload).eq('id', form.id).select().single()
      if (error) { toast.error('Save failed: ' + error.message); setSaving(false); return }
      saved = data
    } else {
      const { data: noData, error: noErr } = await sb.rpc('next_doc_no', { p_type: form.doc_type })
      if (noErr) { toast.error('Numbering failed — run the documents SQL setup'); setSaving(false); return }
      const { data, error } = await sb.from('documents').insert({ ...payload, doc_no: noData, status: form.doc_type === 'receipt' ? 'paid' : 'draft' }).select().single()
      if (error) { toast.error('Save failed: ' + error.message); setSaving(false); return }
      saved = data
      // Post the debit to the customer's ledger for a NEW credit invoice.
      if (isCreditInvoice) {
        const { error: ledErr } = await sb.rpc('post_ledger', {
          p_customer_id: form.customer_id, p_ref_type: 'invoice', p_ref_no: noData, p_ref_id: saved.id,
          p_description: 'Invoice ' + noData, p_debit: tot, p_credit: 0, p_by: user?.name || '',
        })
        if (ledErr) toast('Invoice saved, but ledger posting failed — check credit setup', { icon: '⚠️' })
      }
    }
    setSaving(false); setModal(false); toast.success('Saved ' + saved.doc_no)
    load()
    if (thenPrint) printDocument(saved)
  }

  const convertTo = async (d, newType) => {
    const items = typeof d.items === 'string' ? JSON.parse(d.items) : d.items
    const { data: noData } = await sb.rpc('next_doc_no', { p_type: newType })
    const { data, error } = await sb.from('documents').insert({
      doc_type: newType, doc_no: noData, status: newType === 'receipt' ? 'paid' : 'draft',
      customer_name: d.customer_name, customer_phone: d.customer_phone, customer_address: d.customer_address,
      items: JSON.stringify(items), subtotal: d.subtotal, discount: d.discount, tax: d.tax, total: d.total,
      amount_paid: newType === 'receipt' ? d.total : 0, note: d.note, terms: d.terms, issue_date: today(),
      created_by: user?.name || '', source_doc_id: d.id,
    }).select().single()
    if (error) { toast.error('Convert failed: ' + error.message); return }
    toast.success(`Created ${data.doc_no} from ${d.doc_no}`); setTab(newType); load()
  }

  const setStatus = async (d, status) => { await sb.from('documents').update({ status }).eq('id', d.id); load() }
  const del = async (d) => { if (!confirm(`Delete ${d.doc_no}?`)) return; await sb.from('documents').delete().eq('id', d.id); load() }

  const parseItems = (d) => { try { return typeof d.items === 'string' ? JSON.parse(d.items) : (d.items || []) } catch { return [] } }
  const typeLabel = (t) => DOC_TYPES.find(x => x.key === t)?.label || t

  return (
    <div className="max-w-5xl mx-auto">
      <div className="flex justify-between items-start flex-wrap gap-4 mb-5">
        <div>
          <h1 className="text-[22px] md:text-[26px] font-bold">Documents</h1>
          <p className="text-xs text-gray-500 mt-1">Create proformas, invoices, receipts & waybills</p>
        </div>
        <button onClick={() => openNew(tab)} className="h-11 px-5 bg-gray-900 text-white rounded-xl text-sm font-bold">New {typeLabel(tab)}</button>
      </div>

      <div className="flex gap-2 mb-5 overflow-x-auto scrollbar-hide">
        {DOC_TYPES.map(t => (
          <button key={t.key} onClick={() => setTab(t.key)} className={`h-9 px-4 rounded-lg text-xs font-semibold whitespace-nowrap ${tab === t.key ? 'bg-gray-900 text-white' : 'bg-gray-100 text-gray-500'}`}>{t.label}</button>
        ))}
      </div>

      {loading ? <p className="text-sm text-gray-400 py-10 text-center">Loading…</p> : shown.length === 0 ? (
        <div className="text-center py-16 text-gray-400">
          <p className="text-sm">No {typeLabel(tab).toLowerCase()}s yet</p>
          <button onClick={() => openNew(tab)} className="mt-3 h-10 px-5 bg-gray-100 rounded-xl text-xs font-semibold text-gray-600">Create the first one</button>
        </div>
      ) : (
        <div className="space-y-3">
          {shown.map(d => (
            <div key={d.id} className="bg-white rounded-2xl p-4 shadow-md">
              <div className="flex items-start justify-between flex-wrap gap-2">
                <div>
                  <div className="font-bold text-sm">{d.doc_no} <span className="text-gray-400 font-normal">· {d.customer_name}</span></div>
                  <div className="text-[11px] text-gray-400">{d.issue_date} · {parseItems(d).length} item(s) · {money(d.total)}</div>
                </div>
                <span className={`text-[10px] font-bold px-2 py-1 rounded ${d.status === 'paid' || d.status === 'delivered' ? 'bg-green-100 text-green-700' : d.status === 'cancelled' ? 'bg-red-100 text-red-700' : d.status === 'sent' ? 'bg-blue-100 text-blue-700' : 'bg-gray-100 text-gray-500'}`}>{d.status.toUpperCase()}</span>
              </div>
              <div className="flex flex-wrap gap-2 mt-3">
                <button onClick={() => printDocument(d)} className="h-9 px-3 bg-gray-900 text-white rounded-lg text-xs font-semibold">Print / PDF</button>
                <button onClick={() => openEdit(d)} className="h-9 px-3 border border-gray-200 rounded-lg text-xs font-medium text-gray-600">Edit</button>
                {d.doc_type === 'proforma' && <button onClick={() => convertTo(d, 'invoice')} className="h-9 px-3 border border-gray-200 rounded-lg text-xs font-medium text-gray-600">→ Invoice</button>}
                {d.doc_type === 'invoice' && <button onClick={() => convertTo(d, 'receipt')} className="h-9 px-3 border border-gray-200 rounded-lg text-xs font-medium text-gray-600">→ Receipt</button>}
                {d.doc_type === 'invoice' && <button onClick={() => convertTo(d, 'waybill')} className="h-9 px-3 border border-gray-200 rounded-lg text-xs font-medium text-gray-600">→ Waybill</button>}
                {d.status !== 'paid' && d.doc_type === 'invoice' && <button onClick={() => setStatus(d, 'paid')} className="h-9 px-3 border border-green-200 text-green-600 rounded-lg text-xs font-medium">Mark paid</button>}
                <button onClick={() => del(d)} className="h-9 px-3 text-red-400 rounded-lg text-xs font-medium ml-auto">Delete</button>
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Create / edit modal */}
      {modal && (
        <div className="fixed inset-0 z-50 bg-black/40 flex items-end md:items-center justify-center p-0 md:p-4" onClick={() => setModal(false)}>
          <div className="bg-white w-full md:max-w-2xl md:rounded-2xl rounded-t-2xl max-h-[92vh] overflow-y-auto" onClick={e => e.stopPropagation()}>
            <div className="sticky top-0 bg-white border-b border-gray-100 px-5 py-4 flex items-center justify-between z-10">
              <h2 className="font-bold">{form.id ? 'Edit' : 'New'} {typeLabel(form.doc_type)}</h2>
              <button onClick={() => setModal(false)} className="text-gray-400 text-2xl leading-none">×</button>
            </div>
            <div className="p-5 space-y-4">
              {/* Type (only for new) */}
              {!form.id && (
                <div className="grid grid-cols-4 gap-2">
                  {DOC_TYPES.map(t => (
                    <button key={t.key} onClick={() => setForm({ ...form, doc_type: t.key })} className={`p-2 rounded-lg text-[11px] font-semibold border-2 ${form.doc_type === t.key ? 'border-gray-900 bg-gray-50' : 'border-gray-200 text-gray-500'}`}>{t.label}</button>
                  ))}
                </div>
              )}

              {/* Customer picker (for invoices — enables credit + ledger) */}
              {form.doc_type === 'invoice' && (
                <div className="relative">
                  <label className="block text-[11px] font-semibold text-gray-500 mb-1">Link a customer account (for credit sales)</label>
                  <input className="w-full h-11 px-4 bg-gray-50 border-2 border-gray-200 rounded-xl text-sm" placeholder="Search customer by name/phone…"
                    value={custQuery || (form.customer_id ? form.customer_name : '')}
                    onChange={e => { setCustQuery(e.target.value); setShowCustList(true); setForm({ ...form, customer_id: '' }) }}
                    onFocus={() => setShowCustList(true)} />
                  {showCustList && custQuery.trim() && (
                    <div className="absolute z-30 left-0 right-0 mt-1 bg-white border border-gray-200 rounded-xl shadow-lg max-h-52 overflow-y-auto">
                      {customers.filter(c => (c.name || '').toLowerCase().includes(custQuery.toLowerCase()) || (c.phone || '').includes(custQuery)).slice(0, 8).map(c => (
                        <button key={c.id} onClick={() => { setForm({ ...form, customer_id: c.id, customer_name: c.name || '', customer_phone: c.phone || '', customer_address: c.address || '' }); setCustQuery(''); setShowCustList(false) }} className="w-full text-left px-3 py-2 hover:bg-gray-50 text-sm flex justify-between">
                          <span>{c.name || c.phone}</span>
                          <span className={`text-[10px] font-bold px-1.5 py-0.5 rounded ${c.customer_type === 'credit' ? 'bg-blue-100 text-blue-600' : 'bg-gray-100 text-gray-400'}`}>{c.customer_type === 'credit' ? 'CREDIT' : 'CASH'}</span>
                        </button>
                      ))}
                      {customers.filter(c => (c.name || '').toLowerCase().includes(custQuery.toLowerCase()) || (c.phone || '').includes(custQuery)).length === 0 && <div className="px-3 py-3 text-xs text-gray-400">No match. Add them in Customers first, or leave blank for a walk-in.</div>}
                    </div>
                  )}
                  {form.customer_id && (
                    <label className="flex items-center gap-2 mt-2 cursor-pointer">
                      <input type="checkbox" checked={form.is_credit} onChange={e => setForm({ ...form, is_credit: e.target.checked })} className="w-4 h-4" />
                      <span className="text-sm text-gray-700">This is a <b>credit sale</b> (adds to customer's account balance)</span>
                    </label>
                  )}
                </div>
              )}

              {/* Customer */}
              <div className="grid md:grid-cols-2 gap-3">
                <input className="h-12 px-4 bg-gray-50 border-2 border-gray-200 rounded-xl text-base" placeholder="Customer name *" value={form.customer_name} onChange={e => setForm({ ...form, customer_name: e.target.value })} />
                <input className="h-12 px-4 bg-gray-50 border-2 border-gray-200 rounded-xl text-base" placeholder="Phone" value={form.customer_phone} onChange={e => setForm({ ...form, customer_phone: e.target.value })} />
              </div>
              <input className="w-full h-12 px-4 bg-gray-50 border-2 border-gray-200 rounded-xl text-base" placeholder="Address (for delivery/waybill)" value={form.customer_address} onChange={e => setForm({ ...form, customer_address: e.target.value })} />

              {/* Line items */}
              <div>
                <div className="text-xs font-bold text-gray-500 mb-2">Items</div>
                <div className="space-y-2">
                  {form.items.map((it, i) => (
                    <div key={i} className="relative">
                      <div className="grid grid-cols-[1fr_50px_80px_28px] gap-2 items-center">
                        <input className="h-10 px-3 bg-gray-50 border-2 border-gray-200 rounded-lg text-sm" placeholder="Item / product" value={it.name}
                          onChange={e => { setItem(i, 'name', e.target.value); setProdQuery(e.target.value); setActiveItemIdx(i) }} onFocus={() => { setActiveItemIdx(i); setProdQuery(it.name) }} />
                        <input type="tel" className="h-10 px-2 bg-gray-50 border-2 border-gray-200 rounded-lg text-sm text-center" placeholder="Qty" value={it.qty} onChange={e => setItem(i, 'qty', e.target.value.replace(/\D/g, ''))} />
                        <input type="tel" className="h-10 px-2 bg-gray-50 border-2 border-gray-200 rounded-lg text-sm text-center" placeholder="Price" value={it.unit_price} onChange={e => setItem(i, 'unit_price', e.target.value.replace(/[^\d.]/g, ''))} />
                        <button onClick={() => rmItem(i)} className="text-gray-300 hover:text-red-500 text-lg">×</button>
                      </div>
                      {activeItemIdx === i && prodMatches.length > 0 && (
                        <div className="absolute z-20 left-0 right-0 mt-1 bg-white border border-gray-200 rounded-xl shadow-lg max-h-48 overflow-y-auto">
                          {prodMatches.map(p => (
                            <button key={p.id} onClick={() => pickProduct(i, p)} className="w-full text-left px-3 py-2 hover:bg-gray-50 text-sm flex justify-between">
                              <span>{p.name}</span><span className="text-gray-400">{money(p.price)}</span>
                            </button>
                          ))}
                        </div>
                      )}
                    </div>
                  ))}
                </div>
                <button onClick={addItem} className="mt-2 text-xs font-semibold text-gray-500">+ Add item</button>
              </div>

              {/* Totals */}
              <div className="bg-gray-50 rounded-xl p-4 space-y-2">
                <div className="flex justify-between text-sm"><span className="text-gray-500">Subtotal</span><span className="font-semibold">{money(subtotal)}</span></div>
                <div className="flex justify-between items-center text-sm"><span className="text-gray-500">Discount</span><input type="tel" className="w-24 h-9 px-2 bg-white border border-gray-200 rounded-lg text-sm text-right" value={form.discount} onChange={e => setForm({ ...form, discount: e.target.value.replace(/[^\d.]/g, '') })} /></div>
                <div className="flex justify-between items-center text-sm"><span className="text-gray-500">Tax / Charges</span><input type="tel" className="w-24 h-9 px-2 bg-white border border-gray-200 rounded-lg text-sm text-right" value={form.tax} onChange={e => setForm({ ...form, tax: e.target.value.replace(/[^\d.]/g, '') })} /></div>
                <div className="flex justify-between text-base font-bold border-t border-gray-200 pt-2"><span>Total</span><span>{money(total)}</span></div>
              </div>

              {/* Dates + notes */}
              <div className="grid md:grid-cols-2 gap-3">
                <div><label className="block text-[11px] font-semibold text-gray-500 mb-1">Issue date</label><input type="date" className="w-full h-11 px-3 bg-gray-50 border-2 border-gray-200 rounded-xl text-sm" value={form.issue_date} onChange={e => setForm({ ...form, issue_date: e.target.value })} /></div>
                {form.doc_type !== 'receipt' && form.doc_type !== 'waybill' && <div><label className="block text-[11px] font-semibold text-gray-500 mb-1">Due date</label><input type="date" className="w-full h-11 px-3 bg-gray-50 border-2 border-gray-200 rounded-xl text-sm" value={form.due_date} onChange={e => setForm({ ...form, due_date: e.target.value })} /></div>}
              </div>
              <input className="w-full h-11 px-4 bg-gray-50 border-2 border-gray-200 rounded-xl text-sm" placeholder="Note (optional)" value={form.note} onChange={e => setForm({ ...form, note: e.target.value })} />
              {(form.doc_type === 'proforma' || form.doc_type === 'invoice') && <input className="w-full h-11 px-4 bg-gray-50 border-2 border-gray-200 rounded-xl text-sm" placeholder="Terms (e.g. payment terms)" value={form.terms} onChange={e => setForm({ ...form, terms: e.target.value })} />}
            </div>
            <div className="sticky bottom-0 bg-white border-t border-gray-100 px-5 py-4 flex gap-2">
              <button onClick={() => setModal(false)} className="h-12 px-5 border border-gray-300 rounded-xl text-sm font-semibold text-gray-600">Cancel</button>
              <button onClick={() => save(false)} disabled={saving} className="flex-1 h-12 bg-gray-200 text-gray-700 rounded-xl text-sm font-bold disabled:opacity-50">Save</button>
              <button onClick={() => save(true)} disabled={saving} className="flex-1 h-12 bg-gray-900 text-white rounded-xl text-sm font-bold disabled:opacity-50">Save & Print</button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
