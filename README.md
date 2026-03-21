# SuperTotem

A totem and shield manager for Shaman on vanilla WoW 1.12 (interface 11200). Designed for use with [SuperWoW](https://github.com/balakethelock/SuperWoW), though it falls back to buff-based detection without it.

---

## Changelog

### v1.0.4.4
- **Weapon imbue tracking** — A 5th icon appears on the totem bar showing your current mainhand weapon imbue. The icon accurately reflects whatever imbue is applied to your weapon at all times, including pre-enchanted weapons you equip mid-session. Hover to open a flyout for manual selection; left-click to recast the configured imbue.
- **Auto weapon imbue** — New `W` toggle in the settings row. When enabled, the addon automatically reapplies your configured imbue when it expires (same pattern as auto shield). The configured imbue is selected via a flyout on the `W` toggle.
- **Missing imbue glow** — When auto imbue is enabled and no imbue is detected on your mainhand, the imbue icon displays an animated glow (via DoiteGlow) matching the visual style used by ShamanWeaponEnchant.
- **Tick bar** — Periodic totems (Tremor, Earthbind, Magma, Healing Stream, Mana Spring, Poison Cleansing, Disease Cleansing, Stoneclaw) now show a thin sweep bar at the bottom of their icon indicating time until the next pulse.
- **Spellbook index cache** (`BuildSpellIndex`) — The spellbook is now scanned once at load and on `SPELLS_CHANGED`, building O(1) lookup tables for all totem and imbue spells. Eliminates repeated per-frame and per-cast spellbook scans from `IsOnCooldown`, `ShowCooldownOnMain`, `GetTotemDuration`, and `ShowSpellTip`.
- **Pending cast queue** (`pendingCastByElement`) — Totem spawn detection now uses an element-keyed pending cast table written at every `BPCast` and `OnExternalTotemCast` site. `UNIT_MODEL_CHANGED` matches the spawning unit against the pending entry rather than scanning for any unverified slot, eliminating ambiguous matches when two totems spawn close together.
- **Weapon imbue identification** — Imbue spells are identified by icon texture rather than spell name, making detection server-name-agnostic (`"Windfury 4"`, `"Windfury Weapon"`, etc. all resolve correctly). `GetWeaponEnchantInfo("player")` is used for live icon updates; a pre-seeded ranked-name map covers all known server variants.
- **DoiteGlow bundled** — `libs/DoiteGlow.lua` is now shipped with SuperTotem. Place `IconAlert.tga` and `IconAlertAnts.tga` in the `Textures/` folder.
- **`GetSpellDuration` removed** — On some server builds this API returns remaining buff time rather than base spell duration, causing wildly incorrect timer values. Duration is now sourced entirely from the internal `TOTEM_DURATIONS` table, consistent with SNS.

---

## Requirements

- Vanilla WoW 1.12 client
- **SuperWoW** (strongly recommended) — enables GUID-based totem confirmation, position tracking, range checking, and instant destruction detection. Without it the addon falls back to buff polling, which cannot detect totems that don't apply a buff (e.g. Grounding, Fire Nova, Earthbind).

---

## Installation

Place the `SuperTotem` folder in `Interface/AddOns/`. The folder structure should be:

```
SuperTotem/
  SuperTotem.toc
  SuperTotem.lua
  libs/
    DoiteGlow.lua
  Textures/
    IconAlert.tga
    IconAlertAnts.tga
```

---

## The Totem Bar

Open and close the bar with `/stmenu`. The bar is hidden by default.

**Moving the bar:** Hold Shift and drag any part of the bar.

### Main Icons

Four totem slot icons are shown left to right: Water, Earth, Air, Fire. A fifth icon to the right displays your current mainhand weapon imbue.

| Interaction | Action |
|---|---|
| Left-click | Cast the configured totem for that element |
| Right-click | Cycle between the two quick-toggle totems for that element, or open the flyout if neither is selected |
| Hover | Open the totem selection flyout |

### Weapon Imbue Icon

| Interaction | Action |
|---|---|
| Left-click | Recast the configured imbue |
| Hover | Open the imbue selection flyout and show spell tooltip |

The icon always reflects the imbue actually applied to your mainhand weapon, updated every 0.5 seconds. If auto imbue is enabled and no imbue is detected, an animated glow indicates the missing enchant.

### Flyout Menu

Hovering or right-clicking a main icon opens a flyout listing all available totems for that element plus a **none** option to disable that slot.

- **Left-click** a totem to set it as the primary for that slot.
- **Right-click** a totem to set it as the [fallback totem](#fallback-totems) — only available when the current primary is a cooldown totem (Grounding, Fire Nova, or Earthbind). Eligible totems show a hint in their tooltip.

### Timer Display

When a totem is active a countdown timer appears on its icon. Colour indicates remaining duration:

- **White** — more than 50% remaining
- **Orange** — under 50% remaining
- **Red** — under 10 seconds

If a totem that differs from the currently configured one is active (e.g. a fallback totem is running), it appears in a smaller icon below the main bar with its own timer. Clicking this icon recasts it manually.

When a cooldown totem's primary is on cooldown, its icon shows the cooldown remaining in **grey**.

Periodic totems show a thin sweep bar at the bottom of their icon that fills left to right once per pulse interval.

### Settings Row

A row of small toggle buttons appears below the main icons when the bar is hovered.

| Button | Setting | Description |
|---|---|---|
| `*` | Strict mode | When on, manually dropped totems that differ from your configured selection will be replaced on the next `/stbuff`. When off, manual drops are left alone. |
| `P` | Anti-Poison mode | Continuously re-drops Poison Cleansing Totem in the Water slot. Mutually exclusive with Anti-Disease mode. |
| `D` | Anti-Disease mode | Continuously re-drops Disease Cleansing Totem in the Water slot. Mutually exclusive with Anti-Poison mode. |
| `S` | Auto Shield | Automatically casts your configured shield when it falls off. Clicking opens a small flyout to choose Water, Lightning, or Earth Shield. |
| `W` | Auto Weapon Imbue | Automatically reapplies your configured imbue when it expires. Clicking opens a flyout to choose the imbue type. |

### Range Slider

A horizontal slider to the right of the toggle buttons sets the **global range threshold** (10–40 yards, default 30y). Totems beyond this distance from you will be flagged as out of range and re-dropped on the next `/stbuff`. Requires SuperWoW.

A second **fire range slider** appears below when Searing Totem or Magma Totem is selected, allowing a separate shorter range override for those totems.

---

## Fallback Totems

Grounding Totem, Fire Nova Totem, and Earthbind Totem all have cooldowns that either exceed their active lifetime or are totems prone to early destruction. When one of these is configured as your primary, the addon supports an automatic **fallback totem** that drops in its place while the primary is on cooldown.

**How it works:**

1. When you switch *to* a cooldown totem, the previous non-cooldown totem for that element is automatically saved as the fallback.
2. You can also manually set the fallback via **right-click** in the flyout menu.
3. While the primary is on cooldown, the fallback totem drops instead. Its icon and timer appear in the active totem slot below the main bar.
4. Once the primary comes off cooldown it drops automatically on the next `/stbuff` and the fallback disappears.

The fallback setting is visible as a small **corner badge icon** on the bottom-right of the relevant main totem icon.

All fallback settings are saved between sessions.

---

## Slash Commands

### Core

| Command | Description |
|---|---|
| `/st` or `/supertotem` | Print usage help |
| `/stmenu` | Toggle the totem bar |
| `/stbuff` | Drop all configured totems (main macro to bind) |
| `/stfirebuff` | Drop only the fire totem |
| `/streport` | Report current totem status to party chat |

### Toggles

| Command | Description |
|---|---|
| `/stdebug` | Toggle debug mode (verbose chat output) |
| `/stf` | Toggle follow functionality |
| `/stchainheal` | Toggle Chain Heal preference |
| `/stantidisease` | Toggle Anti-Disease (Stratholme) mode |
| `/stantipoison` | Toggle Anti-Poison (ZG) mode |
| `/sthybrid` | Toggle Hybrid mode (melee assist + Chain Lightning) |
| `/stpets` | Toggle pet healing |
| `/stauto` | Toggle Auto Shield mode |

### Shield Selection

| Command | Aliases | Description |
|---|---|---|
| `/stwatershield` | `/stws` | Set Water Shield |
| `/stlightningshield` | `/stls` | Set Lightning Shield |
| `/stearthshield` | `/stes` | Set Earth Shield |

### Totem Selection — Earth

| Command | Totem |
|---|---|
| `/stsoe` | Strength of Earth Totem |
| `/stss` | Stoneskin Totem |
| `/sttremor` | Tremor Totem |
| `/ststoneclaw` | Stoneclaw Totem |
| `/stearthbind` | Earthbind Totem |

### Totem Selection — Fire

| Command | Totem |
|---|---|
| `/stft` | Flametongue Totem |
| `/stfrr` | Frost Resistance Totem |
| `/stfirenova` | Fire Nova Totem |
| `/stsearing` | Searing Totem |
| `/stmagma` | Magma Totem |

### Totem Selection — Air

| Command | Totem |
|---|---|
| `/stwf` | Windfury Totem |
| `/stgoa` | Grace of Air Totem |
| `/stnr` | Nature Resistance Totem |
| `/stgrounding` | Grounding Totem |
| `/stsentry` | Sentry Totem |
| `/stwindwall` | Windwall Totem |
| `/sttranquil` | Tranquil Air Totem |

### Totem Selection — Water

| Command | Totem |
|---|---|
| `/stms` | Mana Spring Totem |
| `/sths` | Healing Stream Totem |
| `/stfr` | Fire Resistance Totem |
| `/stpoison` | Poison Cleansing Totem |
| `/stdisease` | Disease Cleansing Totem |

### Diagnostics

| Command | Description |
|---|---|
| `/stchecksw` | Check SuperWoW availability and version |
| `/sttotempos` | Print current tracked totem positions |
| `/stcheckbuffs` | Print active totem buff status |
| `/stl [name]` | Set follow target by name |
| `/stdelay [value]` | Set the cast delay between totem drops (seconds) |

---

## Supported Totems

**Earth:** Strength of Earth, Stoneskin, Tremor, Stoneclaw, Earthbind

**Fire:** Flametongue, Frost Resistance, Fire Nova, Searing, Magma

**Air:** Windfury, Grace of Air, Nature Resistance, Grounding, Sentry, Windwall, Tranquil Air

**Water:** Mana Spring, Healing Stream, Fire Resistance, Poison Cleansing, Disease Cleansing

---

## Notes

- Settings are saved per-character in `SuperTotemDB` via the WoW SavedVariables system.
- The addon hooks `CastSpellByName`, `CastSpell`, and `UseAction` globally to detect totem and imbue casts made outside the addon (keybinds, macros, other addons).
- With SuperWoW, totem destruction is detected via `UnitExists` polling (up to 2 second latency). The bar timer clears as soon as destruction is detected.
- Totems with cooldowns (Grounding, Fire Nova, Earthbind) are skipped during drops if on cooldown, allowing the remaining elements to drop without waiting.
