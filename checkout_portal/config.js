/**
 * Central Configuration for LowWatt Handshake Direct Payment Portal
 * 
 * You can easily change Binance UID, toggle BEP-20 USDT on/off,
 * or update Telegram settings anytime here.
 */
const CHECKOUT_CONFIG = {
  // Merchant Display
  MERCHANT_NAME: "Siraj Tech",

  // 1. Binance Pay UID Settings (Currently ACTIVE)
  BINANCE_PAY: {
    ENABLED: true,
    PAY_UID: "35503368",
    QR_IMAGE: "assets/binance_pay_qr.png",
    LABEL: "Binance Pay UID",
    INSTRUCTIONS: "Open Binance App ➔ Pay ➔ Send to Pay UID ➔ Enter exact amount"
  },

  // 2. On-Chain USDT BEP-20 Settings (Currently HIDDEN - toggle ENABLED to true anytime to unhide)
  BEP20_USDT: {
    ENABLED: false, // <-- Change to true anytime to show BEP-20 tab
    NETWORK: "BNB Smart Chain (BEP-20)",
    CONTRACT: "0x55d398326f99059fF775485246999027B3197955",
    ADDRESS: "0xf7eac2113d53de70537715b07768bd8450066c40",
    QR_IMAGE: "assets/bep20_usdt_qr.png",
    INSTRUCTIONS: "Send USDT (BEP-20 network only) to the deposit address below"
  },

  // 3. Telegram Instant Alert Bot Settings
  TELEGRAM: {
    BOT_TOKEN: "8743106713:AAFzpHWFwW3hqU9VdLCl8sJZQJOEGele0o0",
    BOT_USERNAME: "@Binance_Payment_Receiver_Bot",
    CHAT_ID: "1025961490" // Connected to Siraj Shahjahan (@siraj687)
  },

  // 4. Pricing Plans
  PLANS: [
    { id: "single_lifetime", name: "Single Lifetime (1 Mac)", price: 19.99, badge: "Most Popular", seats: "1 Mac" },
    { id: "couple_lifetime", name: "Couple / Friends (3 Macs)", price: 34.99, badge: "Save 40%", seats: "3 Macs" },
    { id: "family_lifetime", name: "Family / Power Pack (5 Macs)", price: 49.99, badge: "Best Value", seats: "5 Macs" },
    { id: "monthly_pass", name: "Single Monthly Pass", price: 1.99, badge: "Monthly", seats: "1 Mac" },
    { id: "quarterly_pass", name: "Single 3-Month Pass", price: 4.99, badge: "3 Months", seats: "1 Mac" },
    { id: "yearly_pass", name: "Single Yearly Pass", price: 9.99, badge: "Yearly", seats: "1 Mac" }
  ]
};
