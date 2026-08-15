import { useState, useEffect, useMemo } from 'react'
import { useStore } from '../hooks/useStore'
import { getSupabase } from '../lib/supabase'
import { money, num, today } from '../lib/utils'
import toast from 'react-hot-toast'
import { printStatement } from '../components/StatementPrint'

const emptyCust = () => ({ id: '', name: '', phone: '', email: '', address: '', contact_person: '', customer_type: 'cash', credit_limit: 0, credit_days: 30, notes: '' })

export default function CustomersPage() {
  const { user } = useStore()
  const sb = getSupabase()
  const [customers, setCustomers] = useState([])
  const [loading, setLoading] = useState(true)
  const [query, setQuery] = useState('')
  const [filter, setFilter] = useState('all')       // all | credit | owing
  const [modal, setModal] = useState(false)
  const [form, setForm] = useState(emptyCust())
  const [detail, setDetail] = useState(null)         // selected customer for statement
  const [ledger, setLedger] = useState([])
  const [payModal, setPayModal] = useState(false)
  const [payForm, setPayForm] = useState({ amount: '', method: 'cash', reference: '', note: '' })

  const load = async () => {
    setLoading(true)
    const { data } = await sb.from('customers').select('*').order('created_at', { ascending: false }).limit(500)
    setCustomers(data || [])
    setLoading(false)
  }
  useEffect(() => { load() }, []) // eslint-disable-line

  const shown = useMemo(() => {
    let list = customers
    if (filter === 'credit') list = list.filter(c => c.customer_type === 'credit')
    if (filter === 'owing') list = list.filter(c => num(c.balance) > 0)
    if (query.trim()) {
      const q = query.toLowerCase()
      list = list.filter(c => (c.name || '').toLowerCase().includes(q) || (c.phone || '').includes(q))
    }
    return list
  }, [customers, filter, query])

  const totalReceivables = customers.reduce((a, c) => a + num(c.balance), 0)
  const creditCount = customers.filter(c => c.customer_type === 'credit').length

  const save = async () => {
    if (!form.name.trim()) { toast.error('Customer name required'); return }
    if (!form.phone.trim()) { toast.error('Phone required'); return }
    const data = {
      name: form.name.trim(), phone: form.phone.trim(), email: form.email.trim(), address: form.address.trim(),
      contact_person: form.contact_person.trim(), customer_type: form.customer_type,
      credit_limit: num(form.credit_limit), credit_days: num(form.credit_days) || 30, notes: form.notes.trim(),
    }
    let err
    if (form.id) ({ error: err } = await sb.from('customers').update(data).eq('id', form.id))
    else ({ error: err } = await sb.from('customers').insert(data))
    if (err) { toast.error('Save failed: ' + err.message); return }
    toast.success('Saved'); setModal(false); load()
  }

  const openStatement = async (c) => {
    setDetail(c)
    const { data } = await sb.from('customer_ledger').select('*').eq('customer_id', c.id).order('entry_date', { ascending: true })
    setLedger(data || [])
  }

  const recordPayment = async () => {
    if (num(payForm.amount) <= 0) { toast.error('Enter amount'); return }
    const { data, error } = await sb.rpc('record_payment', {
      p_customer_id: detail.id, p_amount: num(payForm.amount), p_method: payForm.method,
      p_reference: payForm.reference.trim(), p_note: payForm.note.trim(), p_by: user?.name || '', p_allocations: [],
    })
    if (error || !data?.success) { toast.error('Payment failed: ' + (error?.message || 'error')); return }
    toast.success('Payment recorded — ' + data.receipt_no)
    setPayModal(false); setPayForm({ amount: '', method: 'cash', reference: '', note: '' })
    await load()
    const refreshed = (await sb.from('customers').select('*').eq('id', detail.id).single()).data
    setDetail(refreshed); openStatement(refreshed)
  }

  const availableCredit = (c) => num(c.credit_limit) - num(c.balance)

  // ---- Statement detail view ----
  if (detail) {
    return (
      <div className="max-w-4xl mx-auto">
        <button onClick={() => { setDetail(null); setLedger([]) }} className="text-sm text-gray-500 mb-4">← Back to customers</button>
        <div className="bg-white rounded-2xl p-5 shadow-md mb-4">
          <div className="flex justify-between items-start flex-wrap gap-3">
            <div>
              <h1 className="text-xl font-bold">{detail.name}</h1>
              <p className="text-sm text-gray-500">{detail.phone}{detail.address ? ' · ' + detail.address : ''}</p>
              <span className={`inline-block mt-2 text-[10px] font-bold px-2 py-1 rounded ${detail.customer_type === 'credit' ? 'bg-blue-100 text-blue-700' : 'bg-gray-100 text-gray-500'}`}>{detail.customer_type === 'credit' ? 'CREDIT CUSTOMER' : 'CASH CUSTOMER'}</span>
            </div>
            <div className="text-right">
              <div className="text-xs text-gray-400">Outstanding balance</div>
              <div className={`text-2xl font-black ${num(detail.balance) > 0 ? 'text-red-500' : 'text-green-600'}`}>{money(detail.balance)}</div>
              {detail.customer_type === 'credit' && <div className="text-[11px] text-gray-400 mt-1">Limit {money(detail.credit_limit)} · Available {money(availableCredit(detail))}</div>}
            </div>
          </div>
          <div className="flex gap-2 mt-4">
            <button onClick={() => setPayModal(true)} className="h-10 px-4 bg-green-600 text-white rounded-lg text-xs font-bold">Record Payment</button>
            <button onClick={() => printStatement(detail, ledger)} className="h-10 px-4 bg-gray-900 text-white rounded-lg text-xs font-bold">Print Statement</button>
          </div>
        </div>

        {/* Ledger / statement */}
        <div className="bg-white rounded-2xl shadow-md overflow-hidden">
          <div className="px-5 py-3 border-b border-gray-100 text-sm font-bold">Account Statement</div>
          <div className="overflow-x-auto">
            <table className="w-full min-w-[520px] text-sm">
              <thead><tr className="text-[10px] uppercase text-gray-400">
                <th className="p-3 text-left">Date</th><th className="p-3 text-left">Ref</th><th className="p-3 text-left">Description</th>
                <th className="p-3 text-right">Debit</th><th className="p-3 text-right">Credit</th><th className="p-3 text-right">Balance</th>
              </tr></thead>
              <tbody>
                {ledger.length === 0 && <tr><td colSpan={6} className="text-center py-10 text-gray-400">No transactions yet</td></tr>}
                {ledger.map(e => (
                  <tr key={e.id} className="border-t border-gray-50">
                    <td className="p-3 text-xs">{new Date(e.entry_date).toLocaleDateString('en-GB')}</td>
                    <td className="p-3 text-xs font-medium">{e.ref_no}</td>
                    <td className="p-3 text-xs text-gray-600">{e.description}</td>
                    <td className="p-3 text-right text-xs">{num(e.debit) ? money(e.debit) : '—'}</td>
                    <td className="p-3 text-right text-xs text-green-600">{num(e.credit) ? money(e.credit) : '—'}</td>
                    <td className="p-3 text-right text-xs font-bold">{money(e.balance_after)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>

        {/* Payment modal */}
        {payModal && (
          <div className="fixed inset-0 z-50 bg-black/40 flex items-center justify-center p-4" onClick={() => setPayModal(false)}>
            <div className="bg-white rounded-2xl w-full max-w-md p-5" onClick={e => e.stopPropagation()}>
              <h2 className="font-bold mb-4">Record Payment — {detail.name}</h2>
              <div className="space-y-3">
                <div><label className="block text-xs font-semibold text-gray-500 mb-1">Amount</label><input type="tel" className="w-full h-12 px-4 bg-gray-50 border-2 border-gray-200 rounded-xl text-base" value={payForm.amount} onChange={e => setPayForm({ ...payForm, amount: e.target.value.replace(/[^\d.]/g, '') })} /></div>
                <div><label className="block text-xs font-semibold text-gray-500 mb-1">Method</label><select className="w-full h-12 px-4 bg-gray-50 border-2 border-gray-200 rounded-xl text-base" value={payForm.method} onChange={e => setPayForm({ ...payForm, method: e.target.value })}><option value="cash">Cash</option><option value="momo">Mobile Money</option><option value="bank">Bank</option><option value="cheque">Cheque</option><option value="other">Other</option></select></div>
                <div><label className="block text-xs font-semibold text-gray-500 mb-1">Reference (optional)</label><input className="w-full h-11 px-4 bg-gray-50 border-2 border-gray-200 rounded-xl text-sm" value={payForm.reference} onChange={e => setPayForm({ ...payForm, reference: e.target.value })} placeholder="MoMo txn / cheque no" /></div>
                <p className="text-[11px] text-gray-400">Payment auto-applies to oldest unpaid invoices first.</p>
              </div>
              <div className="flex gap-2 mt-5">
                <button onClick={() => setPayModal(false)} className="h-12 px-5 border border-gray-300 rounded-xl text-sm font-semibold text-gray-600">Cancel</button>
                <button onClick={recordPayment} className="flex-1 h-12 bg-green-600 text-white rounded-xl text-sm font-bold">Record Payment</button>
              </div>
            </div>
          </div>
        )}
      </div>
    )
  }

  // ---- List view ----
  return (
    <div className="max-w-5xl mx-auto">
      <div className="flex justify-between items-start flex-wrap gap-4 mb-5">
        <div><h1 className="text-[22px] md:text-[26px] font-bold">Customers & Credit</h1><p className="text-xs text-gray-500 mt-1">Accounts, credit limits & statements</p></div>
        <button onClick={() => { setForm(emptyCust()); setModal(true) }} className="h-11 px-5 bg-gray-900 text-white rounded-xl text-sm font-bold">Add Customer</button>
      </div>

      {/* Summary cards */}
      <div className="grid grid-cols-3 gap-3 mb-5">
        <div className="bg-white rounded-2xl p-4 shadow-md"><div className="text-[11px] text-gray-400">Total Receivables</div><div className="text-xl font-black text-red-500">{money(totalReceivables)}</div></div>
        <div className="bg-white rounded-2xl p-4 shadow-md"><div className="text-[11px] text-gray-400">Credit Customers</div><div className="text-xl font-black">{creditCount}</div></div>
        <div className="bg-white rounded-2xl p-4 shadow-md"><div className="text-[11px] text-gray-400">Total Customers</div><div className="text-xl font-black">{customers.length}</div></div>
      </div>

      <div className="flex gap-2 mb-4">
        {['all', 'credit', 'owing'].map(f => <button key={f} onClick={() => setFilter(f)} className={`h-9 px-4 rounded-lg text-xs font-semibold capitalize ${filter === f ? 'bg-gray-900 text-white' : 'bg-gray-100 text-gray-500'}`}>{f === 'owing' ? 'Owing' : f}</button>)}
        <input className="flex-1 min-w-[120px] h-9 px-4 bg-gray-50 border border-gray-200 rounded-lg text-sm" placeholder="Search name or phone…" value={query} onChange={e => setQuery(e.target.value)} />
      </div>

      {loading ? <p className="text-sm text-gray-400 py-10 text-center">Loading…</p> : (
        <div className="bg-white rounded-2xl shadow-md overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full min-w-[520px]">
              <thead><tr className="text-[10px] uppercase text-gray-400 bg-gray-50">
                <th className="p-3 text-left">Customer</th><th className="p-3 text-left">Type</th><th className="p-3 text-right">Balance</th><th className="p-3 text-right">Available Credit</th><th className="p-3"></th>
              </tr></thead>
              <tbody>
                {shown.length === 0 && <tr><td colSpan={5} className="text-center py-12 text-gray-400">No customers</td></tr>}
                {shown.map(c => (
                  <tr key={c.id} className="border-t border-gray-50 hover:bg-gray-50/50">
                    <td className="p-3"><div className="text-sm font-semibold">{c.name || c.phone}</div><div className="text-[11px] text-gray-400">{c.phone}</div></td>
                    <td className="p-3"><span className={`text-[10px] font-bold px-2 py-1 rounded ${c.customer_type === 'credit' ? 'bg-blue-100 text-blue-700' : 'bg-gray-100 text-gray-500'}`}>{c.customer_type === 'credit' ? 'CREDIT' : 'CASH'}</span></td>
                    <td className={`p-3 text-right text-sm font-bold ${num(c.balance) > 0 ? 'text-red-500' : 'text-gray-400'}`}>{money(c.balance)}</td>
                    <td className="p-3 text-right text-xs text-gray-500">{c.customer_type === 'credit' ? money(availableCredit(c)) : '—'}</td>
                    <td className="p-3 text-right"><div className="flex gap-2 justify-end"><button onClick={() => openStatement(c)} className="h-8 px-3 bg-gray-100 rounded-lg text-xs font-semibold text-gray-600">Statement</button><button onClick={() => { setForm({ id: c.id, name: c.name || '', phone: c.phone, email: c.email || '', address: c.address || '', contact_person: c.contact_person || '', customer_type: c.customer_type || 'cash', credit_limit: c.credit_limit || 0, credit_days: c.credit_days || 30, notes: c.notes || '' }); setModal(true) }} className="h-8 px-3 border border-gray-200 rounded-lg text-xs font-medium text-gray-600">Edit</button></div></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* Add/edit customer modal */}
      {modal && (
        <div className="fixed inset-0 z-50 bg-black/40 flex items-end md:items-center justify-center p-0 md:p-4" onClick={() => setModal(false)}>
          <div className="bg-white w-full md:max-w-lg md:rounded-2xl rounded-t-2xl max-h-[92vh] overflow-y-auto" onClick={e => e.stopPropagation()}>
            <div className="sticky top-0 bg-white border-b border-gray-100 px-5 py-4 flex items-center justify-between"><h2 className="font-bold">{form.id ? 'Edit' : 'Add'} Customer</h2><button onClick={() => setModal(false)} className="text-gray-400 text-2xl leading-none">×</button></div>
            <div className="p-5 space-y-3">
              <input className="w-full h-12 px-4 bg-gray-50 border-2 border-gray-200 rounded-xl text-base" placeholder="Business / customer name *" value={form.name} onChange={e => setForm({ ...form, name: e.target.value })} />
              <div className="grid grid-cols-2 gap-3">
                <input className="h-12 px-4 bg-gray-50 border-2 border-gray-200 rounded-xl text-base" placeholder="Phone *" value={form.phone} onChange={e => setForm({ ...form, phone: e.target.value })} />
                <input className="h-12 px-4 bg-gray-50 border-2 border-gray-200 rounded-xl text-base" placeholder="Contact person" value={form.contact_person} onChange={e => setForm({ ...form, contact_person: e.target.value })} />
              </div>
              <input className="w-full h-12 px-4 bg-gray-50 border-2 border-gray-200 rounded-xl text-base" placeholder="Email" value={form.email} onChange={e => setForm({ ...form, email: e.target.value })} />
              <input className="w-full h-12 px-4 bg-gray-50 border-2 border-gray-200 rounded-xl text-base" placeholder="Address" value={form.address} onChange={e => setForm({ ...form, address: e.target.value })} />
              <div>
                <label className="block text-xs font-semibold text-gray-500 mb-2">Customer type</label>
                <div className="grid grid-cols-2 gap-2">
                  <button onClick={() => setForm({ ...form, customer_type: 'cash' })} className={`h-11 rounded-xl text-sm font-semibold border-2 ${form.customer_type === 'cash' ? 'border-gray-900 bg-gray-50' : 'border-gray-200 text-gray-500'}`}>Cash</button>
                  <button onClick={() => setForm({ ...form, customer_type: 'credit' })} className={`h-11 rounded-xl text-sm font-semibold border-2 ${form.customer_type === 'credit' ? 'border-blue-500 bg-blue-50 text-blue-700' : 'border-gray-200 text-gray-500'}`}>Credit</button>
                </div>
              </div>
              {form.customer_type === 'credit' && (
                <div className="grid grid-cols-2 gap-3">
                  <div><label className="block text-[11px] font-semibold text-gray-500 mb-1">Credit limit</label><input type="tel" className="w-full h-11 px-4 bg-gray-50 border-2 border-gray-200 rounded-xl text-sm" value={form.credit_limit} onChange={e => setForm({ ...form, credit_limit: e.target.value.replace(/[^\d.]/g, '') })} /></div>
                  <div><label className="block text-[11px] font-semibold text-gray-500 mb-1">Payment terms (days)</label><input type="tel" className="w-full h-11 px-4 bg-gray-50 border-2 border-gray-200 rounded-xl text-sm" value={form.credit_days} onChange={e => setForm({ ...form, credit_days: e.target.value.replace(/\D/g, '') })} /></div>
                </div>
              )}
              <input className="w-full h-11 px-4 bg-gray-50 border-2 border-gray-200 rounded-xl text-sm" placeholder="Notes" value={form.notes} onChange={e => setForm({ ...form, notes: e.target.value })} />
            </div>
            <div className="sticky bottom-0 bg-white border-t border-gray-100 px-5 py-4 flex gap-2"><button onClick={() => setModal(false)} className="h-12 px-5 border border-gray-300 rounded-xl text-sm font-semibold text-gray-600">Cancel</button><button onClick={save} className="flex-1 h-12 bg-gray-900 text-white rounded-xl text-sm font-bold">Save</button></div>
          </div>
        </div>
      )}
    </div>
  )
}
