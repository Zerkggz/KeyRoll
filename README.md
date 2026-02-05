## KeyRoll

Automatically track keystones from party, guild, and friends, then roll to decide which key your group should run.

Designed for World of Warcraft: Midnight and later.

## Features

### Automatic Keystone Detection
* **Bag Scanning** - Detects your keystone on login and when you get a new one
* **Party Chat** - Captures keystones when players shift-click them in chat
* **Friend Login** - Automatically requests keystones when Battle.net friends come online
* **Addon Communication** - Listens for keystones from 10+ popular addons:
  * Astral Keys
  * BigWigs / BigWigsKey
  * DBM / DBM-Key
  * AngryKeystones
  * MDT (Mythic Dungeon Tools)
  * LibKS
  * Keystone Roll-Call (KCLib)
  * Open Raid Library (Details!)
  * Keystone Manager
  * Keystone Announce
* **Post-Dungeon Updates** - Automatically refreshes keystones 30 seconds after completing a dungeon
* **Smart Cache** - Removes keys when players leave party, clears on weekly reset

### GUI Window (`/kr or /keyroll`)
* **My Keys Tab** - View keystones from all your characters (account-wide)
* **Party Tab** - Current party members' keystones
* **Friends Tab** - Keystones from all Battle.net friends
* **Guild Tab** - Keystones from guild members
* **Key Roller Tab** - Interactive roll button with flavor text
* **Sorting** - Sort by Level, Character, or Dungeon
* **Refresh Button** - Manually update the display

### Roll System
* `/keyroll roll` or `/kr roll` - Rolls a random keystone from the party
* Flavor text for dramatic effect
* Results announced in party chat
* Can also roll from the GUI window

### Commands
* `/keyroll` or `/kr` - Open the keystones window
* `/kr roll` - Roll for a random party keystone
* `/kr list` - List all party keystones in chat
* `/kr capture` - Manually request keystones from party
* `/kr clear` - Clear all cached keystones
* `/kr help` - Show all commands
* `/kr debug` - Toggle debug mode (shows detailed logging)
* `/kr debug seed` - Add test keystones for solo testing
* `/kr debug clear` - Remove test keystones
* `/kr debug friends` - Show friend keystones cache
* `/kr debug guild` - Show guild keystones cache
* `/kr debug globaldb` - Show all cached keystones

## Installation

1. Download the addon
2. Extract to `World of Warcraft/_retail_/Interface/AddOns/`
3. Restart WoW or `/reload`

## Usage

**The addon works automatically** once installed:
- Scans your bags for your keystone
- Listens for party/friend/guild keystones via addons
- Tracks keystones across all your characters
- Ready to roll or view at any time

**Best Practice:** Have party members shift-click their keystones in party chat for instant, reliable tracking.

## Technical Details

* **Party-Only Rolling**: Only works in 5-man parties (not raids, not solo)
* **Modern API**: Uses C_Container API for bag scanning
* **Expansion-Proof**: Detects keystones by text, not item ID
* **Account-Wide**: Tracks your alts' keystones via SavedVariables
* **Smart Friend System**: Requests keystones only from friends playing WoW
* **Guild Integration**: Friends who are guild members appear in both tabs
* **Weekly Reset**: Automatically clears guild/friend caches on reset
