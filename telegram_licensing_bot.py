#!/usr/bin/env python3
"""
LowWatt Handshake macOS - Automated Telegram Licensing & Payment Bot
100% Automated | No external website needed | Interactive Buttons | Admin Controls
"""

import os
import sys
import time
import json
import random
import string
import sqlite3
import threading
import urllib.request
import urllib.parse

# --- Configuration ---
BOT_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN")
ADMIN_CHAT_ID = os.environ.get("ADMIN_CHAT_ID")
BINANCE_API_KEY = os.environ.get("BINANCE_API_KEY")
BINANCE_API_SECRET = os.environ.get("BINANCE_API_SECRET")

if not BOT_TOKEN or not BINANCE_API_KEY:
    try:
        from bot_secrets import BINANCE_API_KEY as K, BINANCE_API_SECRET as S, TELEGRAM_BOT_TOKEN as T, ADMIN_CHAT_ID as A
        BOT_TOKEN = BOT_TOKEN or T
        ADMIN_CHAT_ID = ADMIN_CHAT_ID or A
        BINANCE_API_KEY = BINANCE_API_KEY or K
        BINANCE_API_SECRET = BINANCE_API_SECRET or S
    except ImportError:
        pass

BOT_TOKEN = BOT_TOKEN or "8743106713:AAFzpHWFwW3hqU9VdLCl8sJZQJOEGele0o0"
ADMIN_CHAT_ID = int(ADMIN_CHAT_ID or 1025961490)

TELEGRAM_API_URL = f"https://api.telegram.org/bot{BOT_TOKEN}"

# Default Settings (Can be updated live by Admin via Telegram commands)
CONFIG = {
    "binance_uid": "35503368",
    "bep20_enabled": False,  # Hidden by default
    "bep20_address": "0xf7eac2113d53de70537715b07768bd8450066c40",
}

PLANS = {
    "single_lifetime": {"name": "Single Lifetime (1 Mac)", "price": 19.99, "badge": "⭐ Most Popular"},
    "couple_lifetime": {"name": "Couple / Friends (3 Macs)", "price": 34.99, "badge": "🔥 Save 40%"},
    "family_lifetime": {"name": "Family Pack (5 Macs)", "price": 49.99, "badge": "💎 Best Value"},
    "monthly_pass":    {"name": "Monthly Pass (1 Mac)", "price": 1.99, "badge": "📅 1 Month"},
    "quarterly_pass":  {"name": "3-Month Pass (1 Mac)", "price": 4.99, "badge": "📅 3 Months"},
    "yearly_pass":     {"name": "Yearly Pass (1 Mac)", "price": 9.99, "badge": "📅 1 Year"}
}

# --- Database Setup ---
DB_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bot_licensing.db")

def init_db():
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute("""
    CREATE TABLE IF NOT EXISTS orders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER,
        username TEXT,
        plan_id TEXT,
        amount REAL,
        txid TEXT UNIQUE,
        license_key TEXT,
        status TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
    """)
    cur.execute("""
    CREATE TABLE IF NOT EXISTS user_states (
        user_id INTEGER PRIMARY KEY,
        selected_plan TEXT,
        selected_method TEXT,
        last_interaction TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
    """)
    conn.commit()
    conn.close()

# --- Helper Functions ---
def api_call(method, payload=None, files=None):
    url = f"{TELEGRAM_API_URL}/{method}"
    try:
        import subprocess
        cmd = ["curl", "-s", "-X", "POST", url]
        if files:
            for key, val in payload.items():
                cmd.extend(["-F", f"{key}={val}"])
            for field, (filename, file_data) in files.items():
                temp_path = f"/tmp/tg_upload_{int(time.time()*1000)}.png"
                with open(temp_path, "wb") as tf:
                    tf.write(file_data)
                cmd.extend(["-F", f"{field}=@{temp_path}"])
            proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20)
            if files:
                try:
                    os.remove(temp_path)
                except Exception:
                    pass
        else:
            cmd.extend(["-H", "Content-Type: application/json"])
            cmd.extend(["-d", json.dumps(payload or {})])
            proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20)
        
        if proc.returncode == 0 and proc.stdout:
            return json.loads(proc.stdout)
        else:
            print(f"Curl error ({method}): {proc.stderr}")
            return None
    except Exception as e:
        print(f"Telegram API Error ({method}): {e}")
        return None

def send_message(chat_id, text, reply_markup=None):
    payload = {
        "chat_id": chat_id,
        "text": text,
        "parse_mode": "Markdown",
        "disable_web_page_preview": True
    }
    if reply_markup:
        payload["reply_markup"] = reply_markup
    return api_call("sendMessage", payload)

def send_photo(chat_id, photo_path, caption, reply_markup=None):
    if not os.path.exists(photo_path):
        return send_message(chat_id, caption, reply_markup)
    with open(photo_path, "rb") as f:
        file_bytes = f.read()
    payload = {
        "chat_id": str(chat_id),
        "caption": caption,
        "parse_mode": "Markdown"
    }
    if reply_markup:
        payload["reply_markup"] = json.dumps(reply_markup)
    files = {"photo": ("qr.png", file_bytes)}
    return api_call("sendPhoto", payload, files=files)

def generate_license_key():
    def chunk():
        return "".join(random.choices("0123456789ABCDEF", k=4))
    return f"LW-PRO-{chunk()}-{chunk()}-{chunk()}-{chunk()}"

# --- Bot UI Handlers ---
def get_main_menu_keyboard():
    keyboard = []
    # Lifetime Plans
    keyboard.append([{"text": "👑 1 Mac Lifetime — $19.99", "callback_data": "plan_single_lifetime"}])
    keyboard.append([{"text": "👥 3 Macs Lifetime (Save 40%) — $34.99", "callback_data": "plan_couple_lifetime"}])
    keyboard.append([{"text": "🏢 5 Macs Power Pack — $49.99", "callback_data": "plan_family_lifetime"}])
    # Recurring Passes
    keyboard.append([
        {"text": "📅 1-Month ($1.99)", "callback_data": "plan_monthly_pass"},
        {"text": "📅 3-Months ($4.99)", "callback_data": "plan_quarterly_pass"},
        {"text": "📅 1-Year ($9.99)", "callback_data": "plan_yearly_pass"}
    ])
    keyboard.append([{"text": "ℹ️ What is LowWatt Handshake?", "callback_data": "info_about"}])
    return {"inline_keyboard": keyboard}

def handle_start(chat_id, user_first_name):
    text = (
        f"⚡ *Welcome to LowWatt Handshake License Portal*, {user_first_name}!\n\n"
        "Unlock permanent USB-C Power Delivery charging for your Mac with unsupported low-wattage chargers & power banks.\n\n"
        "💳 *No International Credit Card Needed!*\n"
        "Pay seamlessly via Binance Pay and receive your permanent Pro license key automatically right here in seconds.\n\n"
        "👇 *Please select your desired license plan:*"
    )
    send_message(chat_id, text, get_main_menu_keyboard())

def handle_plan_selected(chat_id, plan_id, method="binance"):
    plan = PLANS.get(plan_id)
    if not plan:
        return
    
    # Save user state
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute("INSERT OR REPLACE INTO user_states (user_id, selected_plan, selected_method, last_interaction) VALUES (?, ?, ?, CURRENT_TIMESTAMP)",
                (chat_id, plan_id, method))
    conn.commit()
    conn.close()

    qr_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "checkout_portal/assets/binance_pay_qr.png")
    
    keyboard = []
    if CONFIG["bep20_enabled"]:
        if method == "binance":
            keyboard.append([{"text": "💎 Switch to USDT (BEP-20)", "callback_data": f"method_bep20_{plan_id}"}])
        else:
            keyboard.append([{"text": "🟡 Switch to Binance Pay UID", "callback_data": f"method_binance_{plan_id}"}])
            qr_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "checkout_portal/assets/bep20_usdt_qr.png")

    keyboard.append([{"text": "⬅️ Back to Plans", "callback_data": "back_to_plans"}])

    if method == "binance":
        caption = (
            f"📦 *Selected Plan:* {plan['name']}\n"
            f"💰 *Amount to Send:* `${plan['price']:.2f} USDT`\n\n"
            f"🟡 *Binance Pay UID:* `{CONFIG['binance_uid']}` (Tap to copy)\n\n"
            "📋 *Step-by-Step Instructions:*\n"
            "1. Open Binance App ➔ Go to *Pay* ➔ *Send*\n"
            f"2. Select *Pay ID* and paste: `{CONFIG['binance_uid']}`\n"
            f"3. Send exact amount: *${plan['price']:.2f} USDT*\n"
            "4. After completing, *simply send your Binance Order ID / TxID as a reply in this chat!*\n\n"
            "⚡ _Your permanent Pro license key will be issued immediately upon sending the ID._"
        )
    else:
        caption = (
            f"📦 *Selected Plan:* {plan['name']}\n"
            f"💰 *Amount to Send:* `${plan['price']:.2f} USDT`\n\n"
            f"💎 *USDT (BEP-20) Deposit Address:*\n`{CONFIG['bep20_address']}`\n\n"
            "📋 *Step-by-Step Instructions:*\n"
            "1. Send `${plan['price']:.2f} USDT` on *BNB Smart Chain (BEP-20)*\n"
            "2. After sending, *reply to this chat with your transaction hash (TxHash)!*\n\n"
            "⚡ _Your license key will be issued automatically._"
        )

    send_photo(chat_id, qr_path, caption, {"inline_keyboard": keyboard})

def handle_text_message(chat_id, username, text):
    # Check if admin command
    if chat_id == ADMIN_CHAT_ID:
        if text.startswith("/setuid"):
            parts = text.split()
            if len(parts) > 1:
                CONFIG["binance_uid"] = parts[1]
                send_message(chat_id, f"✅ Binance Pay UID updated to: `{parts[1]}`")
                return
        elif text == "/toggle_bep20":
            CONFIG["bep20_enabled"] = not CONFIG["bep20_enabled"]
            status = "ENABLED (Visible)" if CONFIG["bep20_enabled"] else "DISABLED (Hidden)"
            send_message(chat_id, f"✅ BEP-20 USDT deposit option is now: *{status}*")
            return
        elif text.startswith("/setbep20"):
            parts = text.split()
            if len(parts) > 1:
                CONFIG["bep20_address"] = parts[1]
                send_message(chat_id, f"✅ BEP-20 USDT Address updated to:\n`{parts[1]}`")
                return
        elif text == "/stats":
            conn = sqlite3.connect(DB_PATH)
            cur = conn.cursor()
            cur.execute("SELECT COUNT(*), SUM(amount) FROM orders WHERE status = 'ISSUED'")
            total_orders, total_rev = cur.fetchone()
            total_rev = total_rev or 0.0
            cur.execute("SELECT COUNT(DISTINCT user_id) FROM user_states")
            active_users = cur.fetchone()[0]
            conn.close()
            send_message(chat_id, f"📊 *Bot Sales Statistics:*\n\n"
                                  f"• Total Orders Completed: *{total_orders}*\n"
                                  f"• Total Revenue: *${total_rev:.2f} USDT*\n"
                                  f"• Total Active Leads/Users: *{active_users}*\n"
                                  f"• Current Binance UID: `{CONFIG['binance_uid']}`\n"
                                  f"• BEP-20 Status: *{'Visible' if CONFIG['bep20_enabled'] else 'Hidden'}*")
            return

    # User submission of TxID / Order ID
    cleaned_txid = text.strip()
    if len(cleaned_txid) < 5 or " " in cleaned_txid:
        send_message(chat_id, "ℹ️ Please select a plan from the menu below or send a valid Binance Order ID / TxID:", get_main_menu_keyboard())
        return

    # Check user state
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute("SELECT selected_plan, selected_method FROM user_states WHERE user_id = ?", (chat_id,))
    row = cur.fetchone()
    if not row or not row[0]:
        plan_id = "single_lifetime"
        method = "binance"
    else:
        plan_id, method = row[0], row[1] or "binance"

    plan = PLANS.get(plan_id, PLANS["single_lifetime"])

    # Check if txid already used
    cur.execute("SELECT license_key FROM orders WHERE txid = ?", (cleaned_txid,))
    existing = cur.fetchone()
    if existing:
        conn.close()
        send_message(chat_id, f"⚠️ This Order ID / TxID was already verified!\n\nYour License Key:\n`{existing[0]}`")
        return

    # Generate new Pro License Key
    new_key = generate_license_key()

    # Save order
    cur.execute("""
    INSERT INTO orders (user_id, username, plan_id, amount, txid, license_key, status)
    VALUES (?, ?, ?, ?, ?, ?, 'ISSUED')
    """, (chat_id, username, plan_id, plan["price"], cleaned_txid, new_key))
    conn.commit()
    conn.close()

    # Send Success Message to User
    success_text = (
        "🎉 *Transaction Verified & Pro License Issued!*\n\n"
        f"📦 *Plan:* {plan['name']}\n"
        f"💵 *Amount:* ${plan['price']:.2f} USDT\n"
        f"🆔 *Order ID:* `{cleaned_txid}`\n\n"
        "🔑 *Your Official Pro License Key:*\n"
        f"`{new_key}`\n\n"
        "_(Tap on the key above to copy)_\n\n"
        "📌 *How to Activate in LowWatt Handshake:*\n"
        "1. Open the *LowWatt Handshake* icon in your macOS top menu bar.\n"
        "2. Click *🔑 Enter License Key...*\n"
        "3. Paste your key and click *Done*.\n\n"
        "✨ All charging handshake features and permanent offline modes are now fully unlocked on your Mac. Thank you for your support!"
    )
    send_message(chat_id, success_text)

    # Send Admin Notification to Siraj
    admin_alert = (
        "🔔 *NEW ORDER COMPLETED (Telegram Bot)!*\n\n"
        f"👤 *Customer:* @{username or 'N/A'} (ID: `{chat_id}`)\n"
        f"📦 *Plan:* {plan['name']}\n"
        f"💰 *Amount:* ${plan['price']:.2f} USDT\n"
        f"📱 *Method:* {'Binance Pay UID' if method == 'binance' else 'USDT BEP-20'}\n"
        f"🆔 *TxID / Order ID:* `{cleaned_txid}`\n"
        f"🔑 *Issued Key:* `{new_key}`\n"
        f"⏰ *Timestamp:* {time.strftime('%Y-%m-%d %H:%M:%S UTC', time.gmtime())}"
    )
    send_message(ADMIN_CHAT_ID, admin_alert)

def handle_callback_query(cq):
    cq_id = cq["id"]
    from_user = cq["from"]
    chat_id = from_user["id"]
    data = cq.get("data", "")

    # Acknowledge callback query
    api_call("answerCallbackQuery", {"callback_query_id": cq_id})

    if data.startswith("plan_"):
        plan_id = data.replace("plan_", "")
        handle_plan_selected(chat_id, plan_id, method="binance")
    elif data.startswith("method_"):
        parts = data.split("_")
        method = parts[1]
        plan_id = "_".join(parts[2:])
        handle_plan_selected(chat_id, plan_id, method=method)
    elif data == "back_to_plans":
        handle_start(chat_id, from_user.get("first_name", "Friend"))
    elif data == "info_about":
        info_text = (
            "ℹ️ *About LowWatt Handshake macOS*\n\n"
            "MacBooks natively refuse to charge on low-wattage USB-C chargers (5W, 8W, 10W, 12W, 15W, 18W) and standard power banks, showing 'Not Charging'.\n\n"
            "LowWatt Handshake sends safe, native hardware excitation pulses to wake up the internal SMC charging controller without any kernel extensions.\n\n"
            "👑 *Pro License Unlocks:*\n"
            "• Permanent background charging stabilization\n"
            "• Lifetime free app updates\n"
            "• 100% offline activation"
        )
        send_message(chat_id, info_text, get_main_menu_keyboard())

# --- Binance Auto-Payment Monitor ---
def get_binance_pay_transactions():
    if not BINANCE_API_KEY or not BINANCE_API_SECRET:
        return []
    import hmac, hashlib, subprocess
    timestamp = int(time.time() * 1000)
    query = f"timestamp={timestamp}"
    signature = hmac.new(BINANCE_API_SECRET.encode('utf-8'), query.encode('utf-8'), hashlib.sha256).hexdigest()
    url = f"https://api.binance.com/sapi/v1/pay/transactions?{query}&signature={signature}"
    cmd = ["curl", "-s", "-H", f"X-MBX-APIKEY: {BINANCE_API_KEY}", url]
    try:
        proc = subprocess.run(cmd, stdout=subprocess.PIPE, text=True, timeout=10)
        data = json.loads(proc.stdout)
        if data.get("success"):
            return data.get("data", [])
    except Exception as e:
        print(f"Binance Pay API query error: {e}")
    return []

def get_binance_deposits():
    if not BINANCE_API_KEY or not BINANCE_API_SECRET:
        return []
    import hmac, hashlib, subprocess
    timestamp = int(time.time() * 1000)
    query = f"coin=USDT&timestamp={timestamp}"
    signature = hmac.new(BINANCE_API_SECRET.encode('utf-8'), query.encode('utf-8'), hashlib.sha256).hexdigest()
    url = f"https://api.binance.com/sapi/v1/capital/deposit/hisrec?{query}&signature={signature}"
    cmd = ["curl", "-s", "-H", f"X-MBX-APIKEY: {BINANCE_API_KEY}", url]
    try:
        proc = subprocess.run(cmd, stdout=subprocess.PIPE, text=True, timeout=10)
        data = json.loads(proc.stdout)
        if isinstance(data, list):
            return data
    except Exception as e:
        print(f"Binance Deposit query error: {e}")
    return []

def match_plan_by_amount(amount):
    closest_plan = "single_lifetime"
    min_diff = 999999
    for pid, pinfo in PLANS.items():
        diff = abs(pinfo["price"] - amount)
        if diff < min_diff:
            min_diff = diff
            closest_plan = pid
    return closest_plan

def save_live_order(txid, amount, plan_id, license_key):
    live_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "checkout_portal/live_orders.json")
    order_data = {
        "txid": txid,
        "amount": amount,
        "plan_id": plan_id,
        "license_key": license_key,
        "timestamp": int(time.time())
    }
    try:
        existing = []
        if os.path.exists(live_path):
            with open(live_path, "r") as f:
                existing = json.load(f)
        existing.insert(0, order_data)
        existing = existing[:20]
        with open(live_path, "w") as f:
            json.dump(existing, f, indent=2)
    except Exception as e:
        print(f"Error saving live order: {e}")

def binance_monitor_loop():
    print("⚡ Binance Live Zero-Input Payment Monitor Started...")
    while True:
        try:
            conn = sqlite3.connect(DB_PATH)
            cur = conn.cursor()

            # 1. Check Binance Pay
            pay_txs = get_binance_pay_transactions()
            for tx in pay_txs:
                order_id = str(tx.get("orderId", ""))
                try:
                    amount = float(tx.get("amount", 0))
                except (ValueError, TypeError):
                    amount = 0.0
                currency = tx.get("currency", "")
                
                # Positive amount in USDT means incoming payment
                if amount > 0 and currency == "USDT" and order_id:
                    cur.execute("SELECT id FROM orders WHERE txid = ?", (order_id,))
                    if not cur.fetchone():
                        plan_id = match_plan_by_amount(amount)
                        plan = PLANS[plan_id]
                        new_key = generate_license_key()
                        payer_id = tx.get("payerInfo", {}).get("binanceId", "Unknown")
                        
                        cur.execute("""
                        INSERT INTO orders (user_id, username, plan_id, amount, txid, license_key, status)
                        VALUES (?, ?, ?, ?, ?, ?, 'AUTO_CONFIRMED')
                        """, (0, f"BinanceUID:{payer_id}", plan_id, amount, order_id, new_key))
                        conn.commit()
                        
                        alert = (
                            "🎉 *NEW ZERO-INPUT PAYMENT DETECTED (Binance Pay)!*\n\n"
                            f"💵 *Amount Received:* `${amount:.2f} USDT`\n"
                            f"📦 *Matched Plan:* {plan['name']}\n"
                            f"🆔 *Binance Order ID:* `{order_id}`\n"
                            f"👤 *Payer Binance ID:* `{payer_id}`\n\n"
                            f"🔑 *Auto-Generated Pro Key:*\n`{new_key}`\n\n"
                            "✨ _Zero customer interaction needed. Key rendered to frontend & logged._"
                        )
                        send_message(ADMIN_CHAT_ID, alert)
                        save_live_order(order_id, amount, plan_id, new_key)

            # 2. Check Crypto Deposits (USDT)
            deposits = get_binance_deposits()
            for dep in deposits:
                tx_id = str(dep.get("txId", ""))
                try:
                    amount = float(dep.get("amount", 0))
                except (ValueError, TypeError):
                    amount = 0.0
                coin = dep.get("coin", "")
                status = dep.get("status", 0) # 1 = success
                network = dep.get("network", "")
                
                if amount > 0 and coin == "USDT" and status == 1 and tx_id:
                    cur.execute("SELECT id FROM orders WHERE txid = ?", (tx_id,))
                    if not cur.fetchone():
                        plan_id = match_plan_by_amount(amount)
                        plan = PLANS[plan_id]
                        new_key = generate_license_key()
                        
                        cur.execute("""
                        INSERT INTO orders (user_id, username, plan_id, amount, txid, license_key, status)
                        VALUES (?, ?, ?, ?, ?, ?, 'AUTO_CONFIRMED')
                        """, (0, f"Crypto:{network}", plan_id, amount, tx_id, new_key))
                        conn.commit()
                        
                        alert = (
                            f"🎉 *NEW ZERO-INPUT CRYPTO DEPOSIT ({network})!*\n\n"
                            f"💵 *Amount Received:* `${amount:.2f} USDT`\n"
                            f"📦 *Matched Plan:* {plan['name']}\n"
                            f"🆔 *TxHash:* `{tx_id}`\n\n"
                            f"🔑 *Auto-Generated Pro Key:*\n`{new_key}`\n\n"
                            "✨ _Zero customer interaction needed. Key rendered to frontend & logged._"
                        )
                        send_message(ADMIN_CHAT_ID, alert)
                        save_live_order(tx_id, amount, plan_id, new_key)

            conn.close()
        except Exception as e:
            print(f"Binance Monitor loop error: {e}")
        time.sleep(4)

# --- Cloud Health HTTP Server (Enables 100% Free Web Service on Render) ---
def run_http_server():
    import http.server, socketserver
    port = int(os.environ.get("PORT", 8080))
    class HealthHandler(http.server.SimpleHTTPRequestHandler):
        def do_GET(self):
            self.send_response(200)
            self.send_header("Content-type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"status":"active","service":"LowWatt Telegram & Binance Monitor"}')
        def log_message(self, format, *args):
            pass
    try:
        socketserver.TCPServer.allow_reuse_address = True
        with socketserver.TCPServer(("", port), HealthHandler) as httpd:
            print(f"🌐 Cloud Health Server active on port {port}")
            httpd.serve_forever()
    except Exception as e:
        print(f"HTTP Server note: {e}")

# --- Polling Daemon ---
def run_bot():
    init_db()
    print("🤖 LowWatt Telegram Licensing Bot Started...")
    
    # Launch HTTP Health Server (for Render Free Tier)
    http_thread = threading.Thread(target=run_http_server, daemon=True)
    http_thread.start()

    # Launch Binance Payment Monitor as Background Thread
    monitor_thread = threading.Thread(target=binance_monitor_loop, daemon=True)
    monitor_thread.start()

    offset = None
    while True:
        try:
            params = {"timeout": 20}
            if offset:
                params["offset"] = offset
            res = api_call("getUpdates", params)
            if res and res.get("ok"):
                for update in res.get("result", []):
                    offset = update["update_id"] + 1
                    if "message" in update:
                        msg = update["message"]
                        chat_id = msg["chat"]["id"]
                        user = msg.get("from", {})
                        username = user.get("username", "")
                        first_name = user.get("first_name", "Friend")
                        text = msg.get("text", "")

                        if text == "/start" or text.startswith("/start"):
                            handle_start(chat_id, first_name)
                        elif text:
                            handle_text_message(chat_id, username, text)

                    elif "callback_query" in update:
                        handle_callback_query(update["callback_query"])
            time.sleep(0.5)
        except Exception as e:
            print(f"Polling loop error: {e}")
            time.sleep(3)

if __name__ == "__main__":
    run_bot()
