# Bait and the hungry resident

Bait occupies the boomerang's object slot: neither can be used while the other
is active. It sits 16 pixels ahead of Link for 765 simulation ticks, does no
damage, and disappears on expiry or room exit without consuming the inventory
item. Only feeding a resident consumes it.

The source room template determines attraction: Moblins, Goriyas, Octoroks,
Vires, and blue/red Keese redirect their shared chase target toward active bait.
The original random target/reflection logic still runs afterward. This follows
Z_05 WieldFood and Z_07 UpdateBoomerangOrFood; it is not a proximity lure.

Level 7's hungry Goriya finishes his text, then accepts active bait anywhere in
the room. The secret cue plays, text clears, and Link pauses while the resident
flickers for 64 ticks. The resident and bait then disappear, bait leaves the
inventory, and the northward passage opens. The room's taken flag persists
across visits and checkpoints. Saving waits until feeding finishes.
Original dialogue and sprites remain exclusively in ignored imported content.

## Authoring and checking

Run `scenes/bait_lab.tscn` for a standalone lab without imported assets. It grants
bait at Link's starting point after the authored resident finishes speaking.
Use B (the configured item button) to feed the resident.

- `ItemDefinition.use_duration_ticks` sets bait lifetime (default 765).
- `CaveDefinition.accepts_bait`, `feeding_ticks`, `remember`, and
  `text_line_offset` configure the resident. Use `remember = true` to keep the
  resident gone on future visits.
- `RoomDefinition.bait_attraction`: `source` uses the first enemy's NES type;
  `enabled` or `disabled` explicitly controls attraction for authored rooms.

`tests/bait.gd` checks lifetime, shared object slot, attraction and overrides,
feeding timing, passage blocking, inventory, reentry, checkpoint persistence,
and original resident import when present. `tests/test_bait.py` verifies imported
resident data against the local ROM. No emulator frame replay has been done.
