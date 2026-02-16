# KeyRoll Changelog (2026-02-09)

### Cross-Realm Support
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
- **Combat safety**: All potentially tainted functions wrapped in pcall (UnitFullName, GetGuildRosterInfo, BNGetNumFriends, etc.)
- **Weekly reset**: Fixed keystones not clearing after Tuesday reset - now properly detects reset and clears all caches