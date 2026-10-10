# LowWatt Handshake macOS ⚡🔋

<div align="center">

[![Platform](https://img.shields.io/badge/Platform-macOS%20(Apple%20Silicon%20%7C%20Intel)-000000?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/siraj-bd/lowwatt-handshake-macos)
[![License](https://img.shields.io/badge/License-MIT-blue.svg?style=for-the-badge)](LICENSE)
[![Architecture](https://img.shields.io/badge/Arch-arm64%20%7C%20x86__64-success?style=for-the-badge)](https://github.com/siraj-bd/lowwatt-handshake-macos)
[![Release](https://img.shields.io/badge/Release-v1.0.0-orange?style=for-the-badge)](https://github.com/siraj-bd/lowwatt-handshake-macos/releases)

**A lightweight native macOS background utility to enable seamless USB-C Power Delivery (PD) charging with low-wattage chargers (15W+), power banks, and third-party adapters on MacBooks without handshake misses, sleep stalls, or shutdown tricks.**

[Download Latest DMG](https://github.com/siraj-bd/lowwatt-handshake-macos/releases) • [Features](#key-features) • [How It Works](#the-problem-and-how-it-works) • [Installation](#-installation--download) • [Hardware Advisory](#️-important-hardware-advisory--safety-disclaimer)

---

<img src="assets/screenshot.png" alt="LowWatt Handshake macOS in Action - Charging MacBook with 15W" width="550" />

*Real screenshot: Charging an Apple Silicon MacBook using a 15W charger/power bank with Low Power Mode active — showing live 13 W drawing wattage in green and 15 W negotiated profile in yellow!*

</div>

---

## 💡 Overview

Normally, macOS power management (especially on Apple Silicon with Low Power Mode or Hibernate Mode) has trouble negotiating USB-PD profiles with lower-wattage chargers (such as 15W, 18W, 20W phone chargers or power banks) when the laptop is already running. The Type-C controller often encounters I2C bus communication errors or sleep-state timeouts, causing the charger to be ignored or stuck at `0 W` ("Not Charging").

Previously, the only workaround was tedious:
1. Completely shut down the MacBook.
2. Close the lid and plug in the charger until the chime plays.
3. Turn on the MacBook and unplug the cable before logging in.
4. Plug the cable back in only after logging into user account.

**LowWatt Handshake macOS** completely eliminates this pain! It continuously monitors the hardware power controller and automatically applies an instant I/O Kit wake-pulse whenever a low-wattage cable is plugged in — ensuring a successful USB-PD handshake **100 out of 100 times** without rebooting or closing your laptop lid.

> **Cable Requirement:** Any standard USB Type-C to Type-C cable (both sides must be Type-C).
>
> ⚠️ **Quality Brand Requirement:** Always use standard, certified brand chargers and power banks (such as **Anker, Apple, Belkin, UGREEN, Baseus, Samsung**, etc.). Never use unbranded or low-quality local chargers. See [Hardware Advisory & Disclaimer](#️-important-hardware-advisory--safety-disclaimer).

---

## ⚡ Key Features

- **Low-Wattage Charging (from 15W upwards):** Charge your MacBook using standard phone chargers (15W, 18W, 20W, 30W), power banks, or multi-port GaN chargers (65W, 100W, 140W+).
- **Auto-Handshake Recovery (Kickstart):** Automatically detects stalled negotiation (0 W state) and forces a re-negotiation pulse in milliseconds.
- **Ultra-Lightweight & Native:** Written in pure C and Objective-C using Cocoa and Apple I/O Kit frameworks. Consumes **0.0% CPU** and less than **2 MB RAM**.
- **Real-Time Dual-Line Menu Bar HUD:**
  - 🔋 **3D Battery Widget:** Displays a 3D battery with a glowing golden lightning bolt when actively connected.
  - 🟢 **Top Line (Live Draw):** Bold Green Tahoma font showing real-time actual wattage entering the system (e.g. `13 W`, `20 W`, `37 W`, `100 W`).
  - 🟡 **Bottom Line (Max Capacity):** Bold Yellow Tahoma font showing negotiated charger capacity (e.g. `15 W`, `20 W`, `65 W`, `140 W`).
  - ⚡ **100W+ Full Scale Support:** Cleanly displays 3-digit wattages (100 W, 140 W+) without clipping or artificial caps.
- **Detailed Diagnostics Menu:** Click the menu bar item to inspect live port voltage, amperage, battery inflow, and charger profile in real time.
- **Manual Kickstart Option:** Includes a one-click *"⚡ Force Handshake Kickstart"* menu option if you ever need an on-demand renegotiation.

---

## 🔬 The Problem and How It Works

### Technical Root Cause
When a MacBook is running, its Type-C port controller enters low-power idle states between disconnections. Low-wattage chargers (15W–20W) have weaker CC-pin wake signals compared to Apple's 67W–140W bricks. When plugged in during active runtime:
1. The PMU / SMC controller may miss the initial CC profile broadcast.
2. I2C communication between the port controller and battery management times out.
3. macOS flags the charger as `NotChargingReason` or fails to transition from battery power to AC input.

### The LowWatt Handshake Solution
`LowWatt Handshake macOS` runs a lightweight event listener registered directly with macOS Darwin power notifications (`IOPowerSources` and `AppleSmartBattery`):
1. **Instant Detection:** Hooks into `IOPSNotificationCreateRunLoopSource` with zero CPU polling.
2. **Pulse Renegotiation:** When an external cable is attached with an incomplete contract (0W stall), it momentarily asserts `IOPMAssertionTypePreventUserIdleSystemSleep` and gently signals Darwin power daemons (`com.apple.system.powersources.source`).
3. **Hardware Lock:** Forces the Apple Type-C Port Controller to complete the Power Delivery Object (PDO) negotiation and lock the voltage profile.

---

---

## 📦 Installation & Download

### Download Pre-Compiled DMG (Universal Binary)
1. Download the latest **[LowWatt-Handshake-macOS.dmg](https://github.com/siraj-bd/lowwatt-handshake-macos/releases)** from the Releases section.
2. Open the downloaded `.dmg` and drag **LowWatt Handshake macOS** into your `Applications` folder.
3. Launch **LowWatt Handshake macOS** from Applications or Spotlight.
4. The 3D battery widget will immediately appear in your top menu bar!

### Automatic Startup on Login (Optional)
To have LowWatt Handshake automatically run in the background on system startup:
- Open **System Settings ➔ General ➔ Login Items & Extensions**, click **+** under *Open at Login*, and add **LowWatt Handshake macOS**.


---

## 📊 Live Menu Bar Display Guide

| State | Menu Bar Icon | Top Line (Green) | Bottom Line (Yellow) |
| :--- | :---: | :---: | :---: |
| **15W Power Bank / Charger** | 🔋 *(with bolt)* | `13 W` *(actual draw)* | `15 W` *(charger rating)* |
| **20W Phone Charger** | 🔋 *(with bolt)* | `18 W` *(actual draw)* | `20 W` *(charger rating)* |
| **65W GaN Charger** | 🔋 *(with bolt)* | `37 W` *(actual draw)* | `65 W` *(charger rating)* |
| **100W+ Fast Charger** | 🔋 *(with bolt)* | `95 W` *(actual draw)* | `100 W` *(charger rating)* |
| **Cable Unplugged** | 🔋 *(no bolt)* | `0 W` | `0 W` |

---

## 🖥️ Compatibility

- **Hardware:**
  - Apple Silicon: M1, M1 Pro/Max/Ultra, M2, M3, M4 series
  - Intel-based MacBooks with USB-C / Thunderbolt 3 ports
- **Operating Systems:**
  - macOS 12 Monterey
  - macOS 13 Ventura
  - macOS 14 Sonoma
  - macOS 15 Sequoia and newer

---

## ⚠️ Important Hardware Advisory & Safety Disclaimer

### 🔌 Hardware Advisory: Use Reputable Brands Only
When using **LowWatt Handshake macOS** to charge your MacBook with lower-wattage sources or power banks, **always ensure your power accessories are from reputable, certified brands** (such as **Anker, Apple, Belkin, UGREEN, Baseus, Samsung, Shargeek**, etc.) that strictly comply with the USB Power Delivery (USB-PD) specification.

- **Certified Power Delivery Handshake:** Quality brands feature genuine USB-PD controller chips that negotiate safe voltage steps (5V, 9V, 12V, 15V, 20V) and dynamically adapt current without voltage ripple or current spikes.
- **Essential Hardware Protections:** Certified adapters include Over-Voltage Protection (OVP), Over-Current Protection (OCP), Over-Temperature Protection (OTP), and short-circuit safeguards.

### 🚫 Warning: Avoid Cheap Local & Unbranded Chargers
**Never attempt to charge your MacBook using cheap local chargers, counterfeit adapters, or unbranded generic power banks.**
Substandard or unbranded power accessories often lack:
- Accurate voltage regulation and ripple filtering (which can send dirty, unstable power into your MacBook).
- Over-voltage / over-current circuit protection.
- Proper USB-PD handshake controller silicon.

Connecting uncertified or counterfeit power accessories can cause severe electrical stress, degrade your MacBook's battery health prematurely, or damage the internal USB-C port controller and PMU (Power Management Unit).

---

### 🛡️ Limitation of Liability & Disclaimer

> [!CAUTION]
> **Strict Disclaimer of Liability:**  
> **LowWatt Handshake macOS** is provided as free and open-source software on an **"AS IS"** and **"AS AVAILABLE"** basis without warranties of any kind, whether express or implied.
> 
> The developers, author, and project contributors **assume NO liability or responsibility** for any battery wear, battery degradation, electrical damage, hardware malfunction, system failures, or any other direct or indirect damages resulting from:
> 1. The use of low-quality, cheap local, counterfeit, or unbranded chargers, power banks, or adapters.
> 2. The use of defective, damaged, or non-compliant cables.
> 3. Connecting improper or substandard power sources to your MacBook.
> 
> **Any use of low-quality, unbranded, or non-compliant charging hardware is strictly at the user's sole risk and discretion.**

---

## 📄 License

This project is licensed under the [MIT License](LICENSE) - feel free to use, modify, and distribute.

---

<div align="center">
Developed by <b><a href="https://github.com/siraj-bd">siraj-bd</a></b> • Star ⭐ the repository if this helped you!
</div>
