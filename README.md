# 🗺️ TanaanTracker

**TanaanTracker** is a lightweight **World of Warcraft** client version 7.3.5 (legion) addon that helps you **track, share, and sync rare spawn timers** in **Tanaan Jungle**.  
It automatically logs rare kills, calculates respawn timers, and synchronizes data between guildmates and party members.

Tested Servers: Tauri
---

## 📘 Addon Overview

TanaanTracker keeps your rare data up to date in real time.  
When you kill a rare, it’s automatically recorded and displayed with a countdown until its respawn.  
The addon also syncs your data with others in your guild or group so everyone stays updated effortlessly.

---

## ✨ Key Features

### 🕒 Real-Time Rare Tracking
- Automatically records when you kill each rare.  
- Displays the next estimated respawn time.  
- Works even after relogging — data is saved per realm.

### 🌍 Multi-Realm Support
- Track rares independently on each realm.  
- Quickly switch between realms using the dropdown at the top of the addon window.

### 🔄 Sync With Other Players
- **Automatic guild sync:** Timers are shared automatically between guild members.  
- **Manual sync:** Use `/tsync` to sync with others:
/tsync party → Sync with your party
/tsync raid → Sync with your raid
/tsync <player> → Two-way sync via whisper

- All synced timers are merged intelligently — no duplicates or outdated overwrites.

### 🧭 TomTom Integration
- Each rare row includes two small buttons:
- `>` → Set TomTom waypoint  
- `X` → Clear all TomTom waypoints  
- Works seamlessly with the [TomTom](https://www.curseforge.com/wow/addons/tomtom) addon to show in-game navigation arrows.

### 🔔 Alerts & Reminders
- Receive visual and sound alerts **5 minutes** and **1 minute** before a rare respawns.  
- Alerts are hidden while in combat to avoid distractions.

### 💬 Auto-Announce Kills
- Optionally announces your rare kills to your **guild chat** automatically:
[G] [You]: Terrorfist down — respawn ~60m

- Easily toggle this behavior using the **Auto Announce** checkbox in the top-right corner of the addon window.

### 🧩 ElvUI Integration
- Integrates smoothly with [ElvUI](https://www.tukui.org/) for a consistent visual theme.  
- The dropdown, TomTom buttons, and close button adopt ElvUI’s skin automatically.

### ⚙️ Simple Controls
| Command | Description |
|----------|-------------|
| `/tan` | Toggle the main window |
| `/tan <rare name>` | Show respawn info for a specific rare |
| `/tan <channel>` | Announce all timers to `say`, `yell`, `guild`, `party`, or `raid` |
| `/tan reset` | Wipe all saved timer data (requires confirmation) |
| `/tan ver` or `/tan version` | Show the current addon version |
| `/tan help` | Display a full list of available commands |
| `/tsync ...` | Manually sync timers (see examples above) |

You can also **click the minimap button** to open or close the UI.

---

## 🧱 Requirements

| Addon | Purpose |
|--------|----------|
| **[TomTom](https://www.curseforge.com/wow/addons/tomtom)** | Enables waypoint and navigation arrow support. *(Optional)* |
| **[ElvUI](https://www.tukui.org/)** | Provides visual skin integration. *(Optional)* |

---

## 💡 Additional Notes
- Timers are stored per realm and persist between sessions.
- Only the **kill event** announces to guild chat — loot announcements have been removed for clarity.
- Manual sync (`/tsync`) intelligently merges data between players to prevent spam or loops.
- Addon version can be checked in-game using `/tan ver`.

---

## 📜 License
This addon is distributed freely for personal use.  
Modification and redistribution are allowed provided proper credit is given to the original author.

---

## ❤️ Credits
Created and maintained by **Reg**
Special thanks to Saotomei@Tauri
Contributions, bug reports, and feedback are always welcome!

---


