"""Builds the 5 policy pages (terms, refund, privacy, shipping, contact) from one template.
Edit the BUSINESS block or the page text below, then run:  python3 tools/make_policies.py
"""
import html, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UPDATED = "16 November 2026"
B = {
    "brand": "Annadata Fresh Mart",
    "owner": "Sitaram Khichar",
    "address": "[FULL ADDRESS WITH PIN CODE], Sikar, Rajasthan",
    "phone": "+91 96360 32956",
    "phone_link": "+919636032956",
    "email": "annadatafreshmart75@gmail.com",
    "grievance": "Devansh Choudhary",
    "site": "https://annadatafreshmart75.github.io/sikar/",
}

PAGES = [
    ("terms.html", "Terms & Conditions", "Terms"),
    ("refund.html", "Refund & Cancellation Policy", "Refunds"),
    ("shipping.html", "Delivery (Shipping) Policy", "Delivery"),
    ("privacy.html", "Privacy Policy", "Privacy"),
    ("contact.html", "Contact Us", "Contact"),
]

CONTACT_BLOCK = f"""<div class="box">
<p><b>{B['brand']}</b><br>Proprietor: {B['owner']}<br>{B['address']}</p>
<p>Phone / WhatsApp: <a href="tel:{B['phone_link']}">{B['phone']}</a><br>Email: <a href="mailto:{B['email']}">{B['email']}</a></p>
</div>"""

BODY = {}

BODY["terms.html"] = f"""
<p class="lead">These terms apply when you use this website or order from {B['brand']}. By placing an order you agree to them.</p>
<h2>Who we are</h2>
<p>{B['brand']} is a vegetable home-delivery business in Sikar, Rajasthan, run by {B['owner']} (proprietor). We sell vegetables grown on our own farm near Piprali, Sikar, and some daily vegetables bought fresh from the local mandi.</p>
<h2>Your account</h2>
<ul><li>You can log in with Google or with a code sent to your email.</li>
<li>Please give a correct name, mobile number and delivery address. We use them only to deliver your orders.</li>
<li>You are responsible for orders placed from your account.</li></ul>
<h2>Orders</h2>
<ul><li>There is no minimum order value.</li>
<li>An order is accepted once we confirm it. You can see its status in <b>My orders</b>.</li>
<li>Vegetables depend on the day's harvest. If an item is not available, we will tell you and either replace it with your OK or refund its price.</li>
<li>We may refuse or cancel an order if the address is outside our delivery area, the details are wrong, or the order looks fraudulent. Any amount you paid for such an order is refunded in full.</li></ul>
<h2>Prices and payment</h2>
<ul><li>Prices are in Indian Rupees and include all taxes that apply. Rates can change daily with the market; the price shown when you place the order is the price you pay.</li>
<li>You can pay online (UPI, cards, net banking or wallets through our payment partner), pay on delivery (cash or UPI), or use your Annadata membership balance.</li>
<li>Online payments are processed by a licensed payment gateway. We never see or store your card details or UPI PIN.</li></ul>
<h2>Delivery</h2>
<p>We deliver within Sikar city in the 6–8 AM and 6–8 PM slots. Delivery charges and timings are explained in our <a href="shipping.html">Delivery Policy</a>.</p>
<h2>Quality</h2>
<p>Our own farm vegetables are grown without chemical sprays, using our own natural khaad. Items marked "Daily Fresh" may come from the local mandi and are cleaned and packed by us. Fresh produce can vary a little in size, colour and weight. If something is not right, our <a href="refund.html">Refund Policy</a> explains what we do.</p>
<h2>Membership</h2>
<p>The Annadata Parivar membership is an advance payment for vegetables, with its own <a href="membership.html">Membership Terms</a>.</p>
<h2>Use of the website</h2>
<p>Please do not misuse the website, try to break it, or copy its content, photos or logo for commercial use without our permission.</p>
<h2>Liability</h2>
<p>Our responsibility for any order is limited to the amount you paid for that order.</p>
<h2>Changes</h2>
<p>We may update these terms. The date at the top shows the latest version.</p>
<h2>Law and disputes</h2>
<p>These terms are governed by the laws of India. Courts in Sikar, Rajasthan have jurisdiction.</p>
<h2>Grievance officer</h2>
<p>For any complaint, contact our grievance officer, <b>{B['grievance']}</b>, at <a href="mailto:{B['email']}">{B['email']}</a> or {B['phone']}. We acknowledge complaints within 48 hours and resolve them within one month.</p>
"""

BODY["refund.html"] = f"""
<p class="lead">We want you to be happy with every order. If something is not right, tell us and we will fix it.</p>
<h2>Cancelling an order</h2>
<ul><li><b>Evening slot (6–8 PM):</b> cancel free until 4 PM the same day.</li>
<li><b>Morning slot (6–8 AM):</b> cancel free until 9 PM the previous day.</li>
<li>To cancel, message us on WhatsApp at {B['phone']}.</li>
<li>After this time the vegetables are already harvested and packed for you, so the order cannot be cancelled.</li></ul>
<h2>Damaged, spoiled or wrong items</h2>
<p>If any item is damaged, spoiled, short in weight or not what you ordered, tell us within <b>6 hours of delivery</b>. Use <b>Report a problem</b> in My orders, or send a photo on WhatsApp. We will either:</p>
<ul><li>replace the item in the next delivery slot, or</li><li>refund the price of that item.</li></ul>
<p>Because vegetables are perishable, we cannot take back items that were delivered correctly and in good condition.</p>
<h2>If we cancel</h2>
<p>If we cannot deliver your order (item out of stock, address outside Sikar, or any problem on our side), we refund the full amount you paid.</p>
<h2>How refunds are paid</h2>
<ul><li><b>Paid online:</b> refunded to the same payment method (UPI, card, net banking or wallet) within 5–7 working days of approval. Your bank may take a few more days to show it.</li>
<li><b>Paid on delivery:</b> refunded to your UPI ID within 5–7 working days.</li>
<li><b>Paid with membership balance:</b> the amount is added back to your balance at once.</li></ul>
<p>Unused membership balance can also be refunded, as explained in the <a href="membership.html">Membership Terms</a>.</p>
"""

BODY["shipping.html"] = f"""
<p class="lead">We deliver fresh vegetables to homes in Sikar city. We do not ship by courier or outside Sikar.</p>
<h2>Where we deliver</h2>
<p>Within Sikar city limits, Rajasthan. If your address is outside our area, we will tell you before confirming the order and refund any amount paid.</p>
<h2>Delivery slots</h2>
<ul><li><b>Evening, 6–8 PM:</b> for orders placed by 4 PM the same day.</li>
<li><b>Morning, 6–8 AM:</b> for orders placed after 4 PM, delivered the next morning.</li></ul>
<p>You choose the slot at checkout. We harvest and pack your order fresh for that slot.</p>
<h2>Charges</h2>
<ul><li>No minimum order.</li><li><b>Welcome offer:</b> your first 2 deliveries are free.</li><li>After that, delivery is free on orders of ₹299 or more.</li><li>Orders below ₹299 have a small delivery charge (currently ₹30), always shown before you pay.</li></ul>
<h2>On the day of delivery</h2>
<ul><li>You can follow your order in <b>My orders</b>: Received → Confirmed → On the way → Delivered.</li>
<li>Our delivery partner calls you from an Annadata company number. Please keep your phone handy.</li>
<li>If we cannot reach you, we try again in the next slot at no extra cost. If we still cannot reach you, the order is cancelled; for orders paid in advance we refund the amount minus the delivery charge.</li></ul>
<h2>Delays</h2>
<p>Rarely, heavy rain or other events outside our control may delay a slot. We will tell you on WhatsApp and deliver as soon as possible, or refund you if you prefer.</p>
"""

BODY["privacy.html"] = f"""
<p class="lead">This policy explains what information {B['brand']} collects, why, and how we keep it safe.</p>
<h2>What we collect</h2>
<ul><li><b>Account details:</b> your name and email (from Google login or email login).</li>
<li><b>Order details:</b> mobile number, delivery address, landmark, items ordered, slot and payment method.</li>
<li><b>Payment details:</b> payment status and transaction ID from our payment partner. We never receive your card number, CVV or UPI PIN.</li>
<li><b>Website use:</b> anonymous counts such as pages visited, items viewed and device type, collected with cookies and similar tools (Google Analytics and Microsoft Clarity). These do not include your name or phone number.</li></ul>
<h2>Why we use it</h2>
<ul><li>To confirm, pack and deliver your orders, and to contact you about them.</li>
<li>To process payments and refunds.</li>
<li>To answer your questions and complaints.</li>
<li>To understand which vegetables people like and improve the website.</li>
<li>With your OK, to send our daily vegetable list on WhatsApp. Reply "STOP" any time to stop it.</li></ul>
<h2>Who can see it</h2>
<ul><li><b>Our team:</b> only the people who handle orders.</li>
<li><b>Delivery partners:</b> see your name, address and phone number only while your order is open. They lose access once it is delivered.</li>
<li><b>Service providers:</b> our payment gateway, Supabase (secure database and login), Google (login and analytics) and Microsoft Clarity (analytics), only as needed to run the service.</li>
<li><b>By law:</b> if a government authority asks for it under law.</li></ul>
<p>We do not sell or rent your information to anyone.</p>
<h2>How long we keep it</h2>
<p>We keep your account and order history while your account is active, and as long as needed for accounts and tax records. You can ask us to delete your account at any time.</p>
<h2>Security</h2>
<p>Your data is stored in a secure database with access controls. Logins use one-time codes or Google, so we never store passwords.</p>
<h2>Your choices</h2>
<p>You can ask to see, correct or delete your information, or withdraw consent for messages, by writing to <a href="mailto:{B['email']}">{B['email']}</a> or on WhatsApp at {B['phone']}.</p>
<h2>Grievance officer</h2>
<p><b>{B['grievance']}</b>, <a href="mailto:{B['email']}">{B['email']}</a>, {B['phone']}. We reply within 48 hours.</p>
"""

BODY["contact.html"] = f"""
<p class="lead">Questions about an order, delivery or payment? We are happy to help.</p>
<h2>Reach us</h2>
<ul><li><b>WhatsApp / phone:</b> <a href="https://wa.me/919636032956">{B['phone']}</a>, 6 AM to 9 PM, all days</li>
<li><b>Email:</b> <a href="mailto:{B['email']}">{B['email']}</a></li>
<li><b>Order problems:</b> open <b>My orders</b> and tap <b>Report a problem</b></li></ul>
<h2>Business details</h2>
<ul><li><b>Business name:</b> {B['brand']}</li>
<li><b>Proprietor:</b> {B['owner']}</li>
<li><b>Address:</b> {B['address']}</li>
<li><b>Farm:</b> near Piprali village, Sikar, Rajasthan</li>
<li><b>Grievance officer:</b> {B['grievance']}</li></ul>
<p>We reply to every message within 24 hours, and resolve complaints within one month.</p>
"""

TEMPLATE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{title} | Annadata Fresh Mart</title>
<meta name="description" content="{title} of Annadata Fresh Mart, farm-fresh vegetable delivery in Sikar.">
<link rel="icon" href="assets/icon-192.png">
<link rel="preload" href="assets/fonts/mukta-latin-400-normal.woff2" as="font" type="font/woff2" crossorigin>
<style>
@font-face{{font-family:Fraunces;font-weight:600;font-display:swap;src:url(assets/fonts/fraunces-latin-600-normal.woff2) format("woff2")}}
@font-face{{font-family:Mukta;font-weight:400;font-display:swap;src:url(assets/fonts/mukta-latin-400-normal.woff2) format("woff2")}}
@font-face{{font-family:Mukta;font-weight:700;font-display:swap;src:url(assets/fonts/mukta-latin-700-normal.woff2) format("woff2")}}
:root{{--forest:#1F4D2B;--gold:#B8862B;--cream:#FBF7EE;--line:#E4DCC8;--ink:#1D2A1F;--muted:#4A5A4C}}
*{{box-sizing:border-box}}
body{{margin:0;background:var(--cream);color:var(--ink);font:17px/1.7 Mukta,system-ui,sans-serif}}
header{{background:var(--forest)}}
header .in{{width:min(100% - 32px,820px);margin:0 auto;display:flex;align-items:center;justify-content:space-between;gap:12px;padding:12px 0}}
header img{{height:40px;background:var(--cream);border-radius:10px;padding:4px 8px;display:block}}
header a.home{{color:#fff;text-decoration:none;font-weight:700;font-size:15px;border:1.5px solid rgba(255,255,255,.5);border-radius:999px;padding:6px 14px;white-space:nowrap}}
nav{{border-bottom:1px solid var(--line);background:#fff}}
nav .in{{width:min(100% - 32px,820px);margin:0 auto;display:flex;gap:6px;overflow-x:auto;padding:10px 0}}
nav a{{white-space:nowrap;text-decoration:none;color:var(--forest);font-weight:700;font-size:15px;padding:6px 14px;border-radius:999px;border:1.5px solid var(--line)}}
nav a[aria-current=page]{{background:var(--forest);border-color:var(--forest);color:#fff}}
main{{width:min(100% - 32px,820px);margin:0 auto;padding:36px 0 64px}}
h1{{font:600 clamp(30px,5vw,42px)/1.15 Fraunces,Georgia,serif;color:var(--forest);margin:0 0 6px;text-wrap:balance}}
.upd{{color:var(--muted);font-size:15px;margin:0 0 22px}}
.lead{{font-size:19px}}
h2{{font-size:21px;color:var(--forest);margin:30px 0 6px;font-weight:700}}
ul{{padding-left:22px;margin:6px 0}}li{{margin:4px 0}}
a{{color:#2F6E35}}
.box{{background:#fff;border:1px solid var(--line);border-left-width:1px;border-radius:14px;padding:6px 20px;margin-top:10px}}
footer{{border-top:1px solid var(--line);color:var(--muted);font-size:15px}}
footer .in{{width:min(100% - 32px,820px);margin:0 auto;padding:20px 0 32px;display:flex;flex-wrap:wrap;gap:8px 18px}}
footer a{{color:var(--forest)}}
</style>
</head>
<body>
<header><div class="in"><a href="./"><img src="assets/logo-h.png" alt="Annadata Fresh Mart home"></a><a class="home" href="./">← Shop</a></div></header>
<nav aria-label="Policies"><div class="in">{nav}</div></nav>
<main>
<h1>{title}</h1>
<p class="upd">Last updated: {updated}</p>
{body}
{contact}
</main>
<footer><div class="in"><span>© 2026 Annadata Fresh Mart, Sikar</span>{links}</div></footer>
</body>
</html>
"""

for fn, title, short in PAGES:
    nav = "".join(f'<a href="{f}"{" aria-current=page" if f == fn else ""}>{s}</a>' for f, _, s in PAGES)
    links = "".join(f'<a href="{f}">{t}</a>' for f, t, _ in PAGES)
    out = TEMPLATE.format(title=html.escape(title), updated=UPDATED, body=BODY[fn].strip(), contact="" if fn == "contact.html" else "<h2>Contact</h2>\n" + CONTACT_BLOCK, nav=nav, links=links)
    open(os.path.join(ROOT, fn), "w").write(out)
    print("wrote", fn)
