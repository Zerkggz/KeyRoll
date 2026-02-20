# KeyRoll Changelog

### Code Cleanup & Bug Fixes (2026-02-20)

- **pcall audit**: Removed 8 unnecessary pcalls that were hiding errors instead of handling them. `UnitFullName()`, `BNGetNumFriends()`, `GetGuildRosterInfo()`, and `Ambiguate()` are all safe in their calling contexts and now use direct calls with nil-checks instead
- **Kept justified pcalls**: `C_ChatInfo.SendAddonMessage` (prefix may not be registered), `BNSendGameData` (friend can disconnect mid-send), `SendChatMessage` (guild chat can fail during loading)
- **Fixed duplicate UI code**: Removed roll button hide logic in `Refresh()`
- **Fixed `_noguild_` persistence**: Guildless characters no longer write an empty `_noguild_` entry to SavedVariables — uses a local table instead
- **Fixed friend request iteration**: `RequestFriendKeystones()` was calling `BNGetNumFriends()` twice and using the wrong return value for its loop counter
- **Deduplicated bag scanning**: Extracted `GetCurrentKeystoneFromBags()` helper in Comm.lua, replacing 3 identical bag scan loops across broadcast functions
- **Removed duplicate exports**: `IsDebug` and `DebugPrint` were exported to `KeyRoll` twice in Utils.lua
- **Comment cleanup**: Removed ~400 lines of redundant section dividers and comments that restated what the code does

### Cross-Realm Support (2026-02-09)
- **Realm display**: Cross-realm characters now show their realm name in gray next to their name
- **All tabs supported**: Realm names display in My Keys, Party, Friends, and Guild tabs
- **Smart detection**: Only shows realm when different from your current character's realm

### Offline Indicators
- **Visual dimming**: Offline characters now display at 40% opacity
- **Smart detection**: 
  - Guild tab: Uses Battle.net friends first (more reliable), then falls back to guild roster
  - Friends tab: Uses Battle.net friend status
  - Party tab: Shows party members as online
  - My Keys: Current character always online, alts shown as offline

### Broadcasting System
- **Multi-channel broadcasts**: KeyRoll now broadcasts to Guild, Party, and Friends simultaneously
- **Smart throttling**:
  - Guild broadcasts: 15-second cooldown
  - Party broadcasts: 5-second cooldown  
  - Friend broadcasts: 30-second cooldown
- **Message format**: `UPDATE:CharName-Realm:CLASS:mapID:level` (includes realm information)

### Friend Tab Improvements
- **Guild-Friend sync**: Guild members who are also Battle.net friends now appear in both Guild and Friends tabs

### Bug Fixes
- **Combat safety**: Taint-prone API calls now use direct calls with nil-check fallbacks instead of blanket pcalls
- **Weekly reset**: Fixed keystones not clearing after Tuesday reset - now properly detects reset and clears all caches