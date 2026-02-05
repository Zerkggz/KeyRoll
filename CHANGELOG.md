KeyRoll Changelog
Version 3.1.0 (2025-02-05)
New Features

Guild Broadcasting System - KeyRoll now broadcasts keystones to guild and listens for other KeyRoll users

Automatically shares your keystone when you get a new one, log in, join groups, or change zones
Receives keystones from other guild members running KeyRoll
15-second broadcast cooldown prevents spam while maintaining responsiveness


Enhanced Guild Chat Monitoring - Now captures keystones from guild chat and officer chat

Guild member keystones intelligently stored in both Party and Guild tabs when appropriate


GUI Improvements

Key Roller tab now has clean interface (sort controls hidden)
Sort controls properly displayed on My Keys, Party, Friends, and Guild tabs

Technical Changes

Fixed load order: Dungeons.lua → Utils.lua → Comm.lua → Capture.lua
Removed erroneous function export that was overwriting dungeon name lookup
Added sortPipes table to properly manage UI element visibility
Guild broadcasts trigger on: login, bag updates, group changes, zone changes

Bug Fixes

Fixed "attempt to call field 'GetDungeonNameByID' (a nil value)" error
Fixed sort controls visibility on Key Roller tab
Fixed missing sort controls on My Keys tab