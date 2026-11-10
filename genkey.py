#!/usr/bin/env python3
import sys
import os
import random
import sqlite3
import datetime

def generate_key():
    def chunk():
        return "".join(random.choices("0123456789ABCDEF", k=4))
    return f"LW-PRO-{chunk()}-{chunk()}-{chunk()}-{chunk()}"

def main():
    customer = sys.argv[1] if len(sys.argv) > 1 else "Direct Buyer"
    plan = sys.argv[2] if len(sys.argv) > 2 else "Single Lifetime"
    amount = float(sys.argv[3]) if len(sys.argv) > 3 else 19.99

    key = generate_key()
    db_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bot_licensing.db")

    try:
        conn = sqlite3.connect(db_path)
        cur = conn.cursor()
        cur.execute("""
        CREATE TABLE IF NOT EXISTS orders (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER,
            username TEXT,
            plan_id TEXT,
            amount REAL,
            txid TEXT,
            license_key TEXT,
            status TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
        """)
        cur.execute("""
        INSERT INTO orders (user_id, username, plan_id, amount, txid, license_key, status)
        VALUES (0, ?, ?, ?, 'MANUAL_GENERATION', ?, 'ISSUED')
        """, (customer, plan, amount, key))
        conn.commit()
        conn.close()
    except Exception as e:
        pass

    print("=" * 60)
    print("🔑 LowWatt Handshake Pro - Generated License Key")
    print("=" * 60)
    print(f"License Key:  {key}")
    print(f"Customer:     {customer}")
    print(f"Plan:         {plan} (${amount:.2f})")
    print(f"Date:         {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("-" * 60)
    print("📋 READY-TO-SEND CUSTOMER MESSAGE (কাস্টমারকে পাঠানোর মেসেজ):")
    print("-" * 60)
    print(f"""Thank you for purchasing LowWatt Handshake macOS Pro! 🎉

Here is your permanent Pro License Key:
👉  `{key}`

Activation Instructions:
1. Click the LowWatt Handshake battery icon in your Mac menu bar.
2. Select '🔑 Enter License Key...'
3. Paste the key above and click 'Activate License'.

Your Mac will now permanently unlock high-efficiency USB-C PD low-watt handshakes, live telemetry, and charging stabilization!
""")
    print("=" * 60)

if __name__ == "__main__":
    main()
