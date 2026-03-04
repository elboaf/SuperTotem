# SuperTotem

A Shaman totem and shield manager for Turtle WoW (vanilla 1.12). Designed for use with [SuperWoW](https://github.com/balakethelock/SuperWoW), which enables GUID-based totem tracking for reliable state detection. Falls back to buff-based detection without it.

## Features

- **Totem bar GUI** — displays active totems with countdown timers, element-coloured icons, and a per-element totem selector flyout
- **Auto-drop** — `/stbuff` drops all missing totems in sequence, one per call, respecting cast delay
- **Strict mode** — when enabled, `/stbuff` replaces manually dropped totems with your configured loadout
- **External cast detection** — tracks totems dropped via macros, keybinds, action bars, or spellbook clicks
- **Anti-Poison / Anti-Disease modes** — recasts the cleansing totem on every `/stbuff` invocation to trigger the on-use dispel effect
- **Auto Shield** — automatically casts your configured shield when it is not active
- **Range checking** — detects when totems have moved out of range and flags them for re-drop (requires SuperWoW)
- **Fire totem automation** — `/stfirebuff` handles fire totems separately with configurable range override

## Requirements

- Turtle WoW (1.12 client)
- [SuperWoW](https://github.com/balakethelock/SuperWoW) — strongly recommended for GUID-based totem verification and range checking

## Installation

1. Copy the `SuperTotem` folder into your `Interface/AddOns/` directory
2. Reload or log in

## GUI

The totem bar appears at the bottom of the screen and fades in on mouseover. It shows one icon per element (Air, Fire, Earth, Water) with a live countdown timer. Click an icon to open a flyout and select a different totem for that slot.

The toggle buttons above the bar (left to right):

| Button | Function |
|--------|----------|
| `*` | Strict mode — `/stbuff` replaces manual drops with your loadout |
| `P` | Anti-Poison — spams Poison Cleansing Totem for on-use dispel |
| `D` | Anti-Disease — spams Disease Cleansing Totem for on-use dispel |
| `S` | Auto Shield — automatically casts your configured shield |

The range slider sets the totem re-drop distance threshold.

## Core Commands

| Command | Description |
|---------|-------------|
| `/stbuff` | Drop all missing totems |
| `/stfirebuff` | Drop fire totem only |
| `/st` or `/supertotem` | Show all commands |
| `/stdebug` | Toggle verbose debug output |

## Totem Configuration

**Earth**
| Command | Totem |
|---------|-------|
| `/stsoe` | Strength of Earth |
| `/stss` | Stoneskin |
| `/sttremor` | Tremor |
| `/ststoneclaw` | Stoneclaw |
| `/stearthbind` | Earthbind |

**Fire**
| Command | Totem |
|---------|-------|
| `/stft` | Flametongue |
| `/stfrr` | Frost Resistance |
| `/stfirenova` | Fire Nova |
| `/stsearing` | Searing |
| `/stmagma` | Magma |

**Air**
| Command | Totem |
|---------|-------|
| `/stwf` | Windfury |
| `/stgoa` | Grace of Air |
| `/stnr` | Nature Resistance |
| `/stgrounding` | Grounding |
| `/stsentry` | Sentry |
| `/stwindwall` | Windwall |
| `/sttranquil` | Tranquil Air |

**Water**
| Command | Totem |
|---------|-------|
| `/stms` | Mana Spring |
| `/sths` | Healing Stream |
| `/stfr` | Fire Resistance |
| `/stpoison` | Poison Cleansing |
| `/stdisease` | Disease Cleansing |

## Shield Configuration

| Command | Shield |
|---------|--------|
| `/stws` | Water Shield |
| `/stls` | Lightning Shield |
| `/stes` | Earth Shield |

## Mode Commands

| Command | Description |
|---------|-------------|
| `/stantipoison` | Toggle Anti-Poison mode |
| `/stantidisease` | Toggle Anti-Disease mode |
| `/sthybrid` | Toggle Hybrid mode (adjusted healing threshold) |
| `/stauto` | Toggle Auto Shield |
| `/stpets` | Toggle pet healing |
| `/stdelay <seconds>` | Set cast delay between totems |

## Utility

| Command | Description |
|---------|-------------|
| `/streport` | Announce current totem loadout to party |
| `/stmenu` | Open the totem bar GUI |
| `/stchecksw` | Display SuperWoW detection status and totem GUIDs |
| `/sttotempos` | Display current totem positions and distances |
| `/stcheckbuffs` | List all active player buffs with spell IDs |

## Macro Tips

SuperTotem detects casts from macros automatically. You can combine a cast with a loadout switch in a single macro:

```
/cast Magma Totem
/stmagma
```

The `/stmagma` call sets Magma Totem as your configured fire totem. Because strict mode checks happen at cast time, the manual cast and the config update are treated as the same intent — no redundant re-drop will occur.

For Anti-Poison/Disease situations, simply enable the mode from the GUI or via `/stantipoison` and then use `/stbuff` normally — it will recast the cleansing totem each time to trigger the dispel.
