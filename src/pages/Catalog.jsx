import { useState, useEffect, useMemo } from 'react'
import { getSupabase } from '../lib/supabase'
import { SHOP } from '../lib/utils'

const money = v => 'GHS ' + Number(v || 0).toFixed(2)
const IK_ENDPOINT = 'https://ik.imagekit.io/bqikvsp59'
const thumb = (url, w = 500) => {
  if (!url) return ''
  if (IK_ENDPOINT && url.includes('res.cloudinary.com/')) {
    let path = url.split('res.cloudinary.com/')[1]
    path = path.replace(/(\/upload\/)[^/]*[,_][^/]*\//, '$1')
    return `${IK_ENDPOINT}/${path}?tr=w-${w},q-70,f-auto`
  }
  if (url.includes('cloudinary')) return url.replace('/upload/', `/upload/w_${w},f_auto/`)
  if (url.includes('supabase')) return url + (url.includes('?') ? '&' : '?') + `width=${w}&quality=80`
  return url
}
const WA = '233540732878'
const BLUE = '#2563eb'
const I = ({ d, s = 20, sw = 2, fill = 'none' }) => <svg width={s} height={s} viewBox="0 0 24 24" fill={fill} stroke="currentColor" strokeWidth={sw} strokeLinecap="round" strokeLinejoin="round">{d}</svg>

export default function Catalog() {
  const [products, setProducts] = useState([])
  const [promoMap, setPromoMap] = useState({})
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [cat, setCat] = useState('all')
  const [cart, setCart] = useState([])
  const [showCart, setShowCart] = useState(false)
  const [view, setView] = useState(null)
  const [toast, setToast] = useState('')
  const [faq, setFaq] = useState(null)
  const [ordering, setOrdering] = useState(false)

  useEffect(() => { load(); loadPromos() }, [])
  useEffect(() => { if (!products.length) return; const m = window.location.hash.match(/\/catalog\/(.+)$/); if (m) { const p = products.find(x => x.id === m[1]); if (p) setView(p) } }, [products])

  const open = p => { setView(p); window.location.hash = `/catalog/${p.id}` }
  const close = () => { setView(null); window.location.hash = '/catalog' }
  const flash = (m) => { setToast(m); setTimeout(() => setToast(''), 1800) }
  const share = p => { const l = `${window.location.origin}/#/catalog/${p.id}`; navigator.share ? navigator.share({ title: p.name, url: l }).catch(() => {}) : (navigator.clipboard?.writeText(l), flash('Link copied')) }

  const load = async () => {
    const cached = sessionStorage.getItem('cat_p'), ct = sessionStorage.getItem('cat_t')
    if (cached && ct && Date.now() - Number(ct) < 300000) { setProducts(JSON.parse(cached)); setLoading(false); return }
    const sb = getSupabase(); const { data } = await sb.from('products').select('id,name,category,price,wholesale_price,wholesale_min_qty,quantity,image').order('name')
    const items = (data || []).filter(p => p.quantity > 0); setProducts(items); setLoading(false)
    try { sessionStorage.setItem('cat_p', JSON.stringify(items)); sessionStorage.setItem('cat_t', String(Date.now())) } catch {}
  }
  const loadPromos = async () => {
    const sb = getSupabase(); const { data } = await sb.from('promos').select('id,name,start_date,end_date,items,active').eq('active', true)
    if (!data?.length) return; const now = new Date(), map = {}
    for (const p of data) { if (p.start_date && new Date(p.start_date) > now) continue; if (p.end_date && new Date(p.end_date) < now) continue; let items = p.items; if (typeof items === 'string') { try { items = JSON.parse(items) } catch { continue } }; if (!Array.isArray(items)) continue; for (const it of items) { const pid = it.productId || it.product_id, pp = Number(it.promoPrice || it.promo_price || 0); if (pid && pp > 0 && (!map[pid] || pp < map[pid].price)) map[pid] = { price: pp, name: p.name } } }
    setPromoMap(map)
  }

  const cats = useMemo(() => ['all', ...[...new Set(products.filter(p => p.category).map(p => p.category))].sort()], [products])
  const counts = useMemo(() => { const c = { all: products.length }; products.forEach(p => { if (p.category) c[p.category] = (c[p.category] || 0) + 1 }); return c }, [products])
  const filtered = useMemo(() => { const q = search.toLowerCase(); const items = products.filter(p => (!q || p.name.toLowerCase().includes(q)) && (cat === 'all' || p.category === cat)); return items.sort((a, b) => (a.category || 'ZZZ').localeCompare(b.category || 'ZZZ') || a.name.localeCompare(b.name)) }, [products, search, cat])

  const add = product => {
    setCart(prev => { const ex = prev.find(c => c.id === product.id); if (ex) { const n = ex.qty + 1, wp = Number(product.wholesale_price || 0), wm = Number(product.wholesale_min_qty || 0); return prev.map(c => c.id === product.id ? { ...c, qty: n, price: (wp > 0 && wm > 0 && n >= wm) ? wp : Number(product.price), isW: wp > 0 && wm > 0 && n >= wm } : c) }; return [...prev, { id: product.id, name: product.name, price: Number(product.price), rp: Number(product.price), wp: Number(product.wholesale_price || 0), wm: Number(product.wholesale_min_qty || 0), qty: 1, img: product.image, isW: false }] })
    flash('Added to order')
  }
  const upd = (id, d) => setCart(prev => prev.map(c => { if (c.id !== id) return c; const n = Math.max(0, c.qty + d); if (!n) return { ...c, qty: 0 }; const iw = c.wp > 0 && c.wm > 0 && n >= c.wm; return { ...c, qty: n, price: iw ? c.wp : c.rp, isW: iw } }).filter(c => c.qty > 0))
  const cc = cart.reduce((a, c) => a + c.qty, 0), ct = cart.reduce((a, c) => a + c.price * c.qty, 0)
  const dprice = p => promoMap[p.id]?.price || Number(p.price)

  const order = async () => {
    if (!cart.length || ordering) return
    setOrdering(true)
    const sb = getSupabase()
    const items = cart.map(c => ({ id: c.id, name: c.name, qty: c.qty, price: c.price, line_total: c.price * c.qty }))
    const subtotal = items.reduce((a, i) => a + i.line_total, 0)
    let orderNo = ''
    try { const { data } = await sb.rpc('next_order_no'); orderNo = data || ('WA-' + Date.now().toString().slice(-6)) } catch { orderNo = 'WA-' + Date.now().toString().slice(-6) }
    try { await sb.from('whatsapp_orders').insert({ order_no: orderNo, date: new Date().toISOString(), items: JSON.stringify(items), subtotal, total: subtotal, status: 'Pending', source: 'website', details_filled: false }) } catch {}
    const lines = [`Hi TAGITELA, I'd like to order (Ref ${orderNo}):`, '']
    cart.forEach(c => lines.push(`- ${c.qty}x ${c.name}  —  ${money(c.price * c.qty)}`))
    lines.push('', `Total: ${money(subtotal)}`, '', 'Please confirm availability and delivery. Thank you.')
    const msg = lines.join('\n')
    try { navigator.clipboard.writeText(msg) } catch {}
    if (/Android|iPhone|iPad/i.test(navigator.userAgent)) window.location.href = `whatsapp://send?phone=${WA}&text=${encodeURIComponent(msg)}`
    else window.open(`https://web.whatsapp.com/send?phone=${WA}&text=${encodeURIComponent(msg)}`, '_blank')
    setCart([]); setShowCart(false); setOrdering(false)
    flash('Order saved — check WhatsApp to confirm')
  }

  const phone1 = SHOP.phone.split('/')[0].trim()
  if (loading) return <div className="min-h-screen bg-white flex items-center justify-center" style={{ colorScheme: 'light' }}><div className="w-8 h-8 border-[3px] border-gray-200 border-t-[#2563eb] rounded-full animate-spin" /></div>

  return (
    <div className="min-h-screen bg-white text-gray-900" style={{ colorScheme: 'light' }}>
      {toast && <div className="fixed top-5 left-1/2 -translate-x-1/2 bg-gray-900 text-white px-5 py-2.5 rounded-full text-sm font-medium z-[700] shadow-xl">{toast}</div>}

      <nav className="sticky top-0 z-50 bg-white/85 backdrop-blur-xl border-b border-gray-100">
        <div className="max-w-6xl mx-auto px-5 h-16 flex items-center justify-between">
          <div className="flex items-center gap-2.5">
            <div className="w-9 h-9 rounded-lg flex items-center justify-center text-white font-bold text-lg" style={{ background: BLUE }}>T</div>
            <span className="text-[17px] font-extrabold tracking-tight">TAGITELA</span>
          </div>
          <div className="flex items-center gap-2">
            <a href={`tel:${phone1.replace(/\s/g, '')}`} className="hidden sm:flex items-center gap-2 text-gray-600 hover:text-gray-900 rounded-full px-3.5 py-2 text-sm font-semibold transition">
              <I d={<path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72 12.84 12.84 0 0 0 .7 2.81 2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45 12.84 12.84 0 0 0 2.81.7A2 2 0 0 1 22 16.92z" />} s={16} />
              {phone1}
            </a>
            <button onClick={() => setShowCart(true)} className="relative flex items-center gap-2 text-white rounded-full px-4 py-2 text-sm font-semibold transition hover:opacity-90" style={{ background: BLUE }}>
              <I d={<><circle cx="9" cy="21" r="1" /><circle cx="20" cy="21" r="1" /><path d="M1 1h4l2.68 13.39a2 2 0 0 0 2 1.61h9.72a2 2 0 0 0 2-1.61L23 6H6" /></>} s={16} />
              <span className="hidden sm:inline">Cart</span>
              {cc > 0 && <span className="min-w-[20px] h-5 px-1 bg-white text-[#2563eb] rounded-full text-[11px] font-bold flex items-center justify-center">{cc}</span>}
            </button>
          </div>
        </div>
      </nav>

      <div className="relative overflow-hidden" style={{ background: 'linear-gradient(135deg,#0f172a 0%,#1e293b 55%,#1d3a8a 100%)' }}>
        <div className="absolute -right-20 -top-20 w-80 h-80 rounded-full opacity-20" style={{ background: 'radial-gradient(circle,#3b82f6,transparent 70%)' }} />
        <div className="max-w-6xl mx-auto px-5 py-14 md:py-20 relative">
          <div className="inline-flex items-center gap-2 text-blue-300 text-[11px] font-bold tracking-[0.18em] uppercase mb-4"><span className="w-1.5 h-1.5 rounded-full bg-blue-400" /> Trusted medical supplier · Ghana</div>
          <h1 className="text-white text-4xl md:text-6xl font-extrabold leading-[1.02] tracking-[-0.03em] mb-4 max-w-2xl">Quality medical supplies, delivered.</h1>
          <p className="text-blue-100/70 text-base md:text-lg max-w-xl mb-8">Pharmaceuticals, surgical supplies, consumables and equipment — sourced with care and delivered nationwide.</p>
          <div className="relative max-w-lg">
            <span className="absolute left-4 top-1/2 -translate-y-1/2 text-white/40"><I d={<><circle cx="11" cy="11" r="8" /><path d="m21 21-4.35-4.35" /></>} s={20} /></span>
            <input value={search} onChange={e => { setSearch(e.target.value); if (e.target.value) document.getElementById('shop')?.scrollIntoView({ behavior: 'smooth' }) }} placeholder="Search products…" className="w-full h-14 pl-12 pr-4 bg-white/10 border border-white/15 rounded-2xl text-white text-[15px] placeholder:text-white/40 focus:outline-none focus:border-blue-400/50 focus:bg-white/15 transition" />
          </div>
        </div>
      </div>

      <div className="border-b border-gray-100 bg-gray-50/60">
        <div className="max-w-6xl mx-auto px-5 py-4 grid grid-cols-2 md:grid-cols-4 gap-4">
          {[
            [<><path d="M20 6 9 17l-5-5" /></>, 'Genuine products', 'From trusted suppliers'],
            [<><rect x="1" y="3" width="15" height="13" /><path d="M16 8h4l3 3v5h-7V8z" /><circle cx="5.5" cy="18.5" r="2.5" /><circle cx="18.5" cy="18.5" r="2.5" /></>, 'Nationwide delivery', 'Fast dispatch in Ghana'],
            [<path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" />, 'Order on WhatsApp', 'Simple, personal service'],
            [<><path d="M12 2 2 7l10 5 10-5-10-5z" /><path d="m2 17 10 5 10-5M2 12l10 5 10-5" /></>, 'Bulk & wholesale', 'Better prices on quantity'],
          ].map(([ic, t, s], i) => (
            <div key={i} className="flex items-start gap-3">
              <span className="w-9 h-9 rounded-lg bg-white border border-gray-200 flex items-center justify-center text-[#2563eb] flex-shrink-0"><I d={ic} s={18} /></span>
              <div><div className="text-[13px] font-bold text-gray-900 leading-tight">{t}</div><div className="text-[11px] text-gray-500 mt-0.5">{s}</div></div>
            </div>
          ))}
        </div>
      </div>

      <div id="shop" className="max-w-6xl mx-auto px-5 py-10">
        <div className="flex items-center gap-2 overflow-x-auto pb-3 mb-6 scrollbar-hide -mx-1 px-1">
          {cats.map(c => <button key={c} onClick={() => setCat(c)} className={`h-9 px-4 rounded-full text-[13px] font-semibold whitespace-nowrap flex-shrink-0 transition border ${cat === c ? 'text-white border-transparent' : 'bg-white text-gray-600 border-gray-200 hover:border-gray-300'}`} style={cat === c ? { background: BLUE } : {}}>{c === 'all' ? 'All Products' : c}<span className="ml-1.5 opacity-60">{counts[c] || 0}</span></button>)}
        </div>
        <div className="flex items-baseline justify-between mb-5">
          <h2 className="text-xl font-extrabold tracking-tight">{cat === 'all' ? 'All Products' : cat}</h2>
          <span className="text-sm text-gray-400">{filtered.length} item{filtered.length !== 1 ? 's' : ''}</span>
        </div>
        {filtered.length === 0 ? (
          <div className="text-center py-20 text-gray-400"><p className="text-sm">No products found{search ? ` for "${search}"` : ''}.</p></div>
        ) : (
          <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4">
            {filtered.map(p => {
              const promo = promoMap[p.id], dp = dprice(p)
              return (
                <div key={p.id} className="group bg-white border border-gray-200 rounded-2xl overflow-hidden hover:shadow-lg hover:border-gray-300 transition-all">
                  <div className="relative aspect-square bg-gray-50 overflow-hidden cursor-pointer" onClick={() => open(p)}>
                    {p.image ? <img src={thumb(p.image, 500)} alt={p.name} loading="lazy" className="w-full h-full object-cover group-hover:scale-[1.04] transition-transform duration-300" /> : <div className="w-full h-full flex items-center justify-center text-gray-300"><I d={<path d="M3 9l1-5h16l1 5M4 9v10a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1V9M3 9h18" />} s={40} /></div>}
                    {promo && <span className="absolute top-2 left-2 bg-red-500 text-white text-[10px] font-bold px-2 py-1 rounded-full">OFFER</span>}
                    {p.wholesale_price > 0 && p.wholesale_min_qty > 0 && <span className="absolute top-2 right-2 bg-white/90 text-gray-700 text-[10px] font-bold px-2 py-1 rounded-full">Bulk deal</span>}
                  </div>
                  <div className="p-3.5">
                    {p.category && <div className="text-[10px] font-bold text-[#2563eb] uppercase tracking-wide mb-1">{p.category}</div>}
                    <p className="text-[13px] font-semibold text-gray-900 leading-snug mb-2 line-clamp-2 min-h-[2.4em] cursor-pointer" onClick={() => open(p)}>{p.name}</p>
                    <div className="flex items-baseline gap-1.5 mb-2.5"><span className="text-[15px] font-extrabold text-gray-900">{money(dp)}</span>{promo && <span className="text-xs text-gray-400 line-through">{money(p.price)}</span>}</div>
                    <button onClick={() => add({ ...p, price: dp })} className="w-full h-9 text-white rounded-xl text-xs font-bold transition hover:opacity-90" style={{ background: BLUE }}>Add to Order</button>
                  </div>
                </div>
              )
            })}
          </div>
        )}
      </div>

      <div className="bg-gray-50 border-y border-gray-100">
        <div className="max-w-6xl mx-auto px-5 py-12">
          <h2 className="text-2xl font-extrabold tracking-tight text-center mb-2">Why choose TAGITELA</h2>
          <p className="text-gray-500 text-sm text-center mb-8 max-w-md mx-auto">Serving clinics, pharmacies and individuals with dependable medical supply.</p>
          <div className="grid md:grid-cols-3 gap-5">
            {[['Reliable stock', 'We keep the supplies you need in stock, with fast restocking and honest availability.'], ['Fair pricing', 'Competitive retail prices and real wholesale rates for bulk and institutional buyers.'], ['Personal service', 'Order and get support directly on WhatsApp — no call centres, no runaround.']].map(([t, d], i) => (
              <div key={i} className="bg-white border border-gray-200 rounded-2xl p-6">
                <div className="w-10 h-10 rounded-xl flex items-center justify-center text-white font-bold mb-4" style={{ background: BLUE }}>{i + 1}</div>
                <h3 className="font-bold text-gray-900 mb-1.5">{t}</h3>
                <p className="text-sm text-gray-500 leading-relaxed">{d}</p>
              </div>
            ))}
          </div>
        </div>
      </div>

      <div className="max-w-2xl mx-auto px-5 py-12">
        <h2 className="text-2xl font-extrabold tracking-tight text-center mb-8">Frequently asked</h2>
        {[
          ['How do I place an order?', 'Browse our products and tap "Add to Order". Open the cart and tap "Order on WhatsApp" — this opens our official WhatsApp with your order ready to send. We confirm availability, share payment details, and arrange delivery.'],
          ['What payment methods do you accept?', 'We accept Mobile Money (MTN, Telecel, AirtelTigo) and bank transfer. Payment details are shared on WhatsApp when we confirm your order.'],
          ['Do you offer delivery?', 'Yes. We deliver nationwide across Ghana. Delivery fees depend on your location and are confirmed after your order.'],
          ['Do you sell wholesale?', 'Yes. Many products have bulk pricing that applies automatically when you add enough quantity. For large institutional orders, message us on WhatsApp.'],
        ].map(([q, a], i) => (
          <div key={i} onClick={() => setFaq(faq === i ? null : i)} className={`mb-2.5 rounded-2xl cursor-pointer transition-all border ${faq === i ? 'bg-blue-50/50 border-blue-100' : 'bg-white border-gray-200 hover:border-gray-300'}`}>
            <div className="flex items-center justify-between px-5 py-4"><span className="text-sm font-semibold text-gray-900 pr-4">{q}</span><span className={`text-xl text-gray-400 transition-transform flex-shrink-0 ${faq === i ? 'rotate-45' : ''}`}>+</span></div>
            {faq === i && <p className="px-5 pb-4 text-sm text-gray-500 leading-relaxed -mt-1">{a}</p>}
          </div>
        ))}
      </div>

      <footer className="bg-[#0f172a] text-white">
        <div className="max-w-6xl mx-auto px-5 py-12">
          <div className="grid md:grid-cols-3 gap-8 mb-10">
            <div>
              <div className="flex items-center gap-2.5 mb-3"><div className="w-9 h-9 rounded-lg flex items-center justify-center text-white font-bold text-lg" style={{ background: BLUE }}>T</div><span className="text-[17px] font-extrabold">TAGITELA</span></div>
              <p className="text-sm text-white/50 leading-relaxed max-w-xs">Your trusted partner for quality medical supplies, delivered nationwide across Ghana.</p>
            </div>
            <div>
              <h4 className="text-[11px] font-bold uppercase tracking-wider text-white/40 mb-3">Contact</h4>
              <ul className="space-y-2 text-sm text-white/70">
                <li><a href={`tel:${phone1.replace(/\s/g, '')}`} className="hover:text-white transition">{SHOP.phone}</a></li>
                {SHOP.address && <li>{SHOP.address}</li>}
                {SHOP.mapsUrl && <li><a href={SHOP.mapsUrl} target="_blank" rel="noopener" className="text-blue-400 hover:text-blue-300 transition">View on map →</a></li>}
              </ul>
            </div>
            <div>
              <h4 className="text-[11px] font-bold uppercase tracking-wider text-white/40 mb-3">Order</h4>
              <a href={`https://wa.me/${WA}`} target="_blank" rel="noopener" className="inline-flex items-center gap-2 text-white rounded-xl px-4 py-2.5 text-sm font-semibold transition hover:opacity-90" style={{ background: BLUE }}>
                <I d={<path d="M17.5 14.4c-.3-.1-1.7-.9-2-1-.3-.1-.5-.1-.6.1-.2.3-.7 1-.9 1.1-.2.2-.3.2-.6.1-.3-.1-1.2-.5-2.3-1.4-.9-.8-1.4-1.7-1.6-2-.2-.3 0-.5.1-.6l.5-.5c.1-.2.2-.3.2-.5.1-.2 0-.4 0-.5s-.6-1.5-.9-2c-.2-.5-.4-.4-.6-.4h-.5c-.2 0-.5.1-.7.3-.3.3-1 .9-1 2.3s1 2.7 1.1 2.9c.1.2 2 3.1 4.9 4.3 2.9 1.2 2.9.8 3.4.8.5 0 1.7-.7 1.9-1.4.2-.7.2-1.2.2-1.4-.1-.1-.3-.2-.6-.3z" />} s={17} fill="currentColor" />
                Chat on WhatsApp
              </a>
            </div>
          </div>
          <div className="border-t border-white/10 pt-6 flex flex-col md:flex-row items-center justify-between gap-2 text-xs text-white/40">
            <span>© {new Date().getFullYear()} TAGITELA. All rights reserved.</span>
            <span>{SHOP.website || 'tagitela.com'}</span>
          </div>
        </div>
      </footer>

      {cc > 0 && !showCart && <button onClick={() => setShowCart(true)} className="md:hidden fixed bottom-5 left-1/2 -translate-x-1/2 z-[400] text-white rounded-full px-6 py-3.5 font-bold shadow-xl flex items-center gap-3" style={{ background: BLUE }}><span>{cc} item{cc !== 1 ? 's' : ''}</span><span className="opacity-60">·</span><span>{money(ct)}</span></button>}

      {showCart && <div className="fixed inset-0 z-[600] flex justify-end" style={{ colorScheme: 'light' }}>
        <div className="absolute inset-0 bg-black/40" onClick={() => setShowCart(false)} />
        <div className="relative bg-white w-full max-w-md flex flex-col h-full shadow-2xl">
          <div className="flex items-center justify-between px-5 py-4 border-b border-gray-100"><h3 className="text-base font-bold">Your Order <span className="text-gray-400 font-normal text-sm">({cc})</span></h3><button onClick={() => setShowCart(false)} className="text-gray-400 text-2xl leading-none">×</button></div>
          <div className="flex-1 overflow-y-auto p-5">
            {cart.length === 0 ? <div className="text-center py-20 text-gray-400 text-sm">Your order is empty.</div> : cart.map(c => (
              <div key={c.id} className="flex gap-3 items-center py-3 border-b border-gray-50 last:border-0">
                <div className="w-14 h-14 rounded-xl bg-gray-50 overflow-hidden flex-shrink-0">{c.img ? <img src={thumb(c.img, 120)} alt="" className="w-full h-full object-cover" /> : <div className="w-full h-full flex items-center justify-center text-gray-300"><I d={<path d="M3 9l1-5h16l1 5M4 9v10a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1V9" />} s={20} /></div>}</div>
                <div className="flex-1 min-w-0"><p className="text-[13px] font-semibold text-gray-900 leading-tight line-clamp-2">{c.name}</p><div className="text-[13px] font-bold text-gray-900 mt-0.5">{money(c.price)} {c.isW && <span className="text-[10px] text-[#2563eb] font-bold">WHOLESALE</span>}</div></div>
                <div className="flex items-center gap-2 flex-shrink-0"><button onClick={() => upd(c.id, -1)} className="w-7 h-7 border border-gray-200 rounded-lg text-sm font-bold flex items-center justify-center hover:bg-gray-50">−</button><span className="w-6 text-center text-sm font-bold">{c.qty}</span><button onClick={() => upd(c.id, 1)} className="w-7 h-7 border border-gray-200 rounded-lg text-sm font-bold flex items-center justify-center hover:bg-gray-50">+</button></div>
              </div>
            ))}
          </div>
          {cart.length > 0 && <div className="p-5 border-t border-gray-100">
            <div className="flex justify-between items-center mb-4"><span className="text-sm text-gray-400">{cc} item{cc !== 1 ? 's' : ''}</span><span className="text-xl font-extrabold">{money(ct)}</span></div>
            <button onClick={order} disabled={ordering} className="w-full h-14 text-white rounded-2xl font-bold flex items-center justify-center gap-2.5 transition hover:opacity-90 disabled:opacity-60" style={{ background: BLUE }}>
              <I d={<path d="M17.5 14.4c-.3-.1-1.7-.9-2-1-.3-.1-.5-.1-.6.1-.2.3-.7 1-.9 1.1-.2.2-.3.2-.6.1-.3-.1-1.2-.5-2.3-1.4-.9-.8-1.4-1.7-1.6-2-.2-.3 0-.5.1-.6l.5-.5c.1-.2.2-.3.2-.5.1-.2 0-.4 0-.5s-.6-1.5-.9-2c-.2-.5-.4-.4-.6-.4h-.5c-.2 0-.5.1-.7.3-.3.3-1 .9-1 2.3s1 2.7 1.1 2.9c.1.2 2 3.1 4.9 4.3 2.9 1.2 2.9.8 3.4.8.5 0 1.7-.7 1.9-1.4.2-.7.2-1.2.2-1.4-.1-.1-.3-.2-.6-.3z" />} s={20} fill="currentColor" />
              {ordering ? 'Sending…' : 'Order on WhatsApp'}
            </button>
            <p className="text-[11px] text-gray-400 text-center mt-3">We'll confirm availability, price and delivery on WhatsApp.</p>
          </div>}
        </div>
      </div>}

      {view && <div className="fixed inset-0 z-[600] flex items-end md:items-center justify-center p-0 md:p-6" style={{ colorScheme: 'light' }}>
        <div className="absolute inset-0 bg-black/50" onClick={close} />
        <div className="relative bg-white w-full max-w-lg md:rounded-3xl rounded-t-3xl max-h-[92vh] overflow-y-auto">
          <button onClick={close} className="absolute top-4 right-4 z-10 w-9 h-9 bg-white/90 rounded-full flex items-center justify-center text-gray-500 text-xl shadow">×</button>
          <div className="aspect-square bg-gray-50">{view.image ? <img src={thumb(view.image, 800)} alt={view.name} className="w-full h-full object-cover" /> : <div className="w-full h-full flex items-center justify-center text-gray-300"><I d={<path d="M3 9l1-5h16l1 5M4 9v10a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1V9" />} s={56} /></div>}</div>
          <div className="p-6">
            {view.category && <div className="text-[11px] font-bold text-[#2563eb] uppercase tracking-wide mb-1.5">{view.category}</div>}
            <h2 className="text-xl font-extrabold text-gray-900 mb-2">{view.name}</h2>
            <div className="flex items-baseline gap-2 mb-1"><span className="text-2xl font-extrabold">{money(dprice(view))}</span>{promoMap[view.id] && <span className="text-base text-gray-400 line-through">{money(view.price)}</span>}</div>
            {view.wholesale_price > 0 && view.wholesale_min_qty > 0 && <p className="text-[13px] text-[#2563eb] font-semibold mb-4">Buy {view.wholesale_min_qty}+ at {money(view.wholesale_price)} each</p>}
            <div className="flex gap-2 mt-4">
              <button onClick={() => { add({ ...view, price: dprice(view) }); close() }} className="flex-1 h-12 text-white rounded-xl text-sm font-bold transition hover:opacity-90" style={{ background: BLUE }}>Add to Order</button>
              <button onClick={() => share(view)} className="h-12 px-4 border border-gray-200 rounded-xl text-gray-600 hover:bg-gray-50 transition"><I d={<><circle cx="18" cy="5" r="3" /><circle cx="6" cy="12" r="3" /><circle cx="18" cy="19" r="3" /><path d="m8.59 13.51 6.83 3.98M15.41 6.51l-6.82 3.98" /></>} s={18} /></button>
            </div>
          </div>
        </div>
      </div>}
    </div>
  )
}
