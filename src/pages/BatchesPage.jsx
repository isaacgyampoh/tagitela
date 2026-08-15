import { useState, useEffect, useMemo } from 'react'
import { useStore } from '../hooks/useStore'
import { getSupabase } from '../lib/supabase'
import { money, num, today } from '../lib/utils'
import toast from 'react-hot-toast'

const daysUntil = (d) => { if (!d) return null; const ms = new Date(d) - new Date(); return Math.ceil(ms / 86400000) }

export default function BatchesPage() {
  const { products, user, refreshProducts } = useStore()
  const sb = getSupabase()
  const [batches, setBatches] = useState([])
  const [loading, setLoading] = useState(true)
  const [filter, setFilter] = useState('all')   // all | expiring | expired | active
  const [query, setQuery] = useState('')
  const [modal, setModal] = useState(false)
  const [form, setForm] = useState({ product_id: '', batch_no: '', expiry_date: '', quantity: '', cost_price: '', supplier: '' })
  const [prodQuery, setProdQuery] = useState('')
  const [showProdList, setShowProdList] = useState(false)

  const load = async () => {
    setLoading(true)
    const { data } = await sb.from('product_batches').select('*').order('expiry_date', { ascending: true, nullsFirst: false }).limit(1000)
    setBatches(data || [])
    setLoading(false)
  }
  useEffect(() => { load() }, []) // eslint-disable-line

  const enriched = useMemo(() => batches.map(b => ({ ...b, days: daysUntil(b.expiry_date) })), [batches])

  const shown = useMemo(() => {
    let list = enriched
    if (filter === 'active') list = list.filter(b => b.status === 'active')
    if (filter === 'expiring') list = list.filter(b => b.status === 'active' && b.days !== null && b.days >= 0 && b.days <= 90)
    if (filter === 'expired') list = list.filter(b => b.status === 'expired' || (b.days !== null && b.days < 0))
    if (query.trim()) { const q = query.toLowerCase(); list = list.filter(b => (b.product_name || '').toLowerCase().includes(q) || (b.batch_no || '').toLowerCase().includes(q)) }
    return list
  }, [enriched, filter, query])

  const stats = useMemo(() => {
    const active = enriched.filter(b => b.status === 'active')
    return {
      expiringSoon: active.filter(b => b.days !== null && b.days >= 0 && b.days <= 90).length,
      expired: enriched.filter(b => b.status === 'expired' || (b.days !== null && b.days < 0 && b.status === 'active')).length,
      totalActive: active.length,
      stockValue: active.reduce((a, b) => a + num(b.quantity) * num(b.cost_price), 0),
    }
  }, [enriched])

  const addBatch = async () => {
    if (!form.product_id) { toast.error('Choose a product'); return }
    if (!form.quantity || num(form.quantity) <= 0) { toast.error('Enter quantity'); return }
    const { data, error } = await sb.rpc('add_batch', {
      p_product_id: form.product_id, p_batch_no: form.batch_no.trim(), p_expiry: form.expiry_date || null,
      p_qty: num(form.quantity), p_cost: num(form.cost_price), p_supplier: form.supplier.trim(), p_by: user?.name || '',
    })
    if (error || !data?.success) { toast.error('Failed: ' + (error?.message || 'run the batch SQL setup')); return }
    toast.success('Batch added & stock updated')
    setModal(false); setForm({ product_id: '', batch_no: '', expiry_date: '', quantity: '', cost_price: '', supplier: '' })
    load(); refreshProducts && refreshProducts()
  }

  const markExpired = async () => {
    const { data, error } = await sb.rpc('mark_expired_batches')
    if (error) { toast.error('Failed: ' + error.message); return }
    toast.success(`${data || 0} batch(es) marked expired`); load(); refreshProducts && refreshProducts()
  }

  const prodMatches = useMemo(() => {
    if (!prodQuery.trim()) return []
    const q = prodQuery.toLowerCase()
    return products.filter(p => p.name.toLowerCase().includes(q)).slice(0, 6)
  }, [prodQuery, products])

  const badge = (b) => {
    if (b.status === 'expired' || (b.days !== null && b.days < 0)) return <span className="text-[10px] font-bold px-2 py-1 rounded bg-red-100 text-red-700">EXPIRED</span>
    if (b.status === 'depleted') return <span className="text-[10px] font-bold px-2 py-1 rounded bg-gray-100 text-gray-500">DEPLETED</span>
    if (b.days !== null && b.days <= 30) return <span className="text-[10px] font-bold px-2 py-1 rounded bg-red-50 text-red-600">{b.days}d left</span>
    if (b.days !== null && b.days <= 90) return <span className="text-[10px] font-bold px-2 py-1 rounded bg-amber-100 text-amber-700">{b.days}d left</span>
    return <span className="text-[10px] font-bold px-2 py-1 rounded bg-green-100 text-green-700">OK</span>
  }

  return (
    <div className="max-w-5xl mx-auto">
      <div className="flex justify-between items-start flex-wrap gap-4 mb-5">
        <div><h1 className="text-[22px] md:text-[26px] font-bold">Batches & Expiry</h1><p className="text-xs text-gray-500 mt-1">Track lot numbers, expiry dates & FEFO stock</p></div>
        <div className="flex gap-2">
          <button onClick={markExpired} className="h-11 px-4 border border-gray-200 rounded-xl text-sm font-semibold text-gray-600">Sweep Expired</button>
          <button onClick={() => setModal(true)} className="h-11 px-5 bg-gray-900 text-white rounded-xl text-sm font-bold">Add Batch</button>
        </div>
      </div>

      {/* Summary strip */}
      <div className="bg-white rounded-xl border border-gray-200/80 mb-5 overflow-hidden">
        <div className="grid grid-cols-2 md:grid-cols-4 divide-x divide-y md:divide-y-0 divide-gray-100">
          <div className="px-5 py-4"><div className="text-[11px] text-gray-400 uppercase tracking-wide">Active Batches</div><div className="text-2xl font-bold tabular-nums">{stats.totalActive}</div></div>
          <div className="px-5 py-4"><div className="text-[11px] text-gray-400 uppercase tracking-wide">Expiring ≤90d</div><div className="text-2xl font-bold tabular-nums text-amber-600">{stats.expiringSoon}</div></div>
          <div className="px-5 py-4"><div className="text-[11px] text-gray-400 uppercase tracking-wide">Expired</div><div className="text-2xl font-bold tabular-nums text-red-500">{stats.expired}</div></div>
          <div className="px-5 py-4"><div className="text-[11px] text-gray-400 uppercase tracking-wide">Stock Value</div><div className="text-2xl font-bold tabular-nums">{money(stats.stockValue)}</div></div>
        </div>
      </div>

      <div className="flex gap-2 mb-4 flex-wrap">
        {['all', 'active', 'expiring', 'expired'].map(f => <button key={f} onClick={() => setFilter(f)} className={`h-9 px-4 rounded-lg text-xs font-semibold capitalize ${filter === f ? 'bg-gray-900 text-white' : 'bg-gray-100 text-gray-500'}`}>{f}</button>)}
        <input className="flex-1 min-w-[140px] h-9 px-4 bg-gray-50 border border-gray-200 rounded-lg text-sm" placeholder="Search product or batch…" value={query} onChange={e => setQuery(e.target.value)} />
      </div>

      {loading ? <p className="text-sm text-gray-400 py-10 text-center">Loading…</p> : (
        <div className="bg-white rounded-xl border border-gray-200/80 overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full min-w-[640px]">
              <thead><tr className="text-[10px] uppercase text-gray-400 bg-gray-50">
                <th className="p-3 text-left">Product</th><th className="p-3 text-left">Batch</th><th className="p-3 text-left">Expiry</th>
                <th className="p-3 text-right">Qty</th><th className="p-3 text-right">Cost</th><th className="p-3 text-left">Supplier</th><th className="p-3 text-center">Status</th>
              </tr></thead>
              <tbody>
                {shown.length === 0 && <tr><td colSpan={7} className="text-center py-12 text-gray-400">No batches</td></tr>}
                {shown.map(b => (
                  <tr key={b.id} className="border-t border-gray-50">
                    <td className="p-3 text-sm font-medium">{b.product_name}</td>
                    <td className="p-3 text-xs text-gray-600">{b.batch_no || '—'}</td>
                    <td className="p-3 text-xs">{b.expiry_date || '—'}</td>
                    <td className="p-3 text-right text-sm tabular-nums font-semibold">{b.quantity}</td>
                    <td className="p-3 text-right text-xs tabular-nums text-gray-500">{money(b.cost_price)}</td>
                    <td className="p-3 text-xs text-gray-500">{b.supplier || '—'}</td>
                    <td className="p-3 text-center">{badge(b)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* Add batch modal */}
      {modal && (
        <div className="fixed inset-0 z-50 bg-black/40 flex items-end md:items-center justify-center p-0 md:p-4" onClick={() => setModal(false)}>
          <div className="bg-white w-full md:max-w-md md:rounded-2xl rounded-t-2xl max-h-[92vh] overflow-y-auto" onClick={e => e.stopPropagation()}>
            <div className="sticky top-0 bg-white border-b border-gray-100 px-5 py-4 flex items-center justify-between"><h2 className="font-bold">Add Batch (Goods Received)</h2><button onClick={() => setModal(false)} className="text-gray-400 text-2xl leading-none">×</button></div>
            <div className="p-5 space-y-3">
              <div className="relative">
                <label className="block text-[11px] font-semibold text-gray-500 mb-1">Product *</label>
                <input className="w-full h-12 px-4 bg-gray-50 border-2 border-gray-200 rounded-xl text-base" placeholder="Search product…"
                  value={prodQuery || (form.product_id ? (products.find(p => p.id === form.product_id)?.name || '') : '')}
                  onChange={e => { setProdQuery(e.target.value); setShowProdList(true); setForm({ ...form, product_id: '' }) }} onFocus={() => setShowProdList(true)} />
                {showProdList && prodMatches.length > 0 && (
                  <div className="absolute z-30 left-0 right-0 mt-1 bg-white border border-gray-200 rounded-xl shadow-lg max-h-48 overflow-y-auto">
                    {prodMatches.map(p => <button key={p.id} onClick={() => { setForm({ ...form, product_id: p.id, cost_price: p.cost_price || p.costPrice || '' }); setProdQuery(''); setShowProdList(false) }} className="w-full text-left px-3 py-2 hover:bg-gray-50 text-sm">{p.name}</button>)}
                  </div>
                )}
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div><label className="block text-[11px] font-semibold text-gray-500 mb-1">Batch / Lot no.</label><input className="w-full h-11 px-3 bg-gray-50 border-2 border-gray-200 rounded-xl text-sm" value={form.batch_no} onChange={e => setForm({ ...form, batch_no: e.target.value })} /></div>
                <div><label className="block text-[11px] font-semibold text-gray-500 mb-1">Expiry date</label><input type="date" className="w-full h-11 px-3 bg-gray-50 border-2 border-gray-200 rounded-xl text-sm" value={form.expiry_date} onChange={e => setForm({ ...form, expiry_date: e.target.value })} /></div>
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div><label className="block text-[11px] font-semibold text-gray-500 mb-1">Quantity *</label><input type="tel" className="w-full h-11 px-3 bg-gray-50 border-2 border-gray-200 rounded-xl text-sm" value={form.quantity} onChange={e => setForm({ ...form, quantity: e.target.value.replace(/\D/g, '') })} /></div>
                <div><label className="block text-[11px] font-semibold text-gray-500 mb-1">Cost price</label><input type="tel" className="w-full h-11 px-3 bg-gray-50 border-2 border-gray-200 rounded-xl text-sm" value={form.cost_price} onChange={e => setForm({ ...form, cost_price: e.target.value.replace(/[^\d.]/g, '') })} /></div>
              </div>
              <div><label className="block text-[11px] font-semibold text-gray-500 mb-1">Supplier</label><input className="w-full h-11 px-3 bg-gray-50 border-2 border-gray-200 rounded-xl text-sm" value={form.supplier} onChange={e => setForm({ ...form, supplier: e.target.value })} /></div>
              <p className="text-[11px] text-gray-400">Adding a batch flags this product for batch tracking and updates its total stock. Sales will then draw from the soonest-expiring batch first (FEFO).</p>
            </div>
            <div className="sticky bottom-0 bg-white border-t border-gray-100 px-5 py-4 flex gap-2"><button onClick={() => setModal(false)} className="h-12 px-5 border border-gray-300 rounded-xl text-sm font-semibold text-gray-600">Cancel</button><button onClick={addBatch} className="flex-1 h-12 bg-gray-900 text-white rounded-xl text-sm font-bold">Add Batch</button></div>
          </div>
        </div>
      )}
    </div>
  )
}
