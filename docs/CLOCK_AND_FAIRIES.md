# Magic clock and dropped fairies

A clock is a pickup, not an inventory or B-button item. Its effect lasts until
Link leaves the room, including cave entry; it has no expiry timer. Movement and
attacks stop for affected monsters, while their spawn/death animations and hit
reactions remain possible. Link can move, attack, and use items, and is immune
to damage, capture, and Bubble contact effects. Existing enemy projectiles keep
moving without colliding with him. Fairies also keep flying.

The source checks InvClock in individual monster routines. Default exceptions
are blade traps, Dodongo, Gohma, Manhandla, Gleeok and detached heads, Patra and
children, and Ganon. Aquamentus, Digdogger, Moldorm, and Lanmola do freeze.
Residents and Zelda have no movement effect to freeze. Author-created enemies
can override the default using EnemyDefinition.clock_response: source, freeze,
or immune. Link cycles the four sprite palettes every two frames during the
effect; imported walking and attacking sprites use the source palettes.

Dropped fairies initially face up, accelerate from speed $7F to $A0, then wander
with six-turn phases and $10-tick turn delays. Movement uses the source's masked
speed accumulator and eight directions; room bounds reverse flight, terrain does
not. Their two sprite frames alternate every four frames. A fairy heals three
hearts immediately, capped by Link's heart containers, while preserving fractional
ring damage. It plays the item cue when appearing and when collected.

All original kill-cycle loot rows now retain clock and fairy entries. The
sixteenth kill since damage guarantees a fairy on the next eligible drop, ahead
of the help-drop counter. Monsters configured to drop nothing still drop nothing.
Normal drop pickup delay is 32 ticks and lifetime is 510 ticks. Link, his sword,
boomerang, and arrows can take these rewards.

Clock effects and loose rewards are transient and excluded from native saves.
Loading reconstructs the room without a clock effect. Ladder ownership, other
inventory, and permanent room changes keep their existing save behavior.

## Editable lab

Run scenes/reward_lab.tscn without imported resources. Walk north from the start
to collect the clock and freeze the Octoroks; the fairy continues flying.

RoomDefinition.reward_spawns contains RewardSpawn resources with definition and
position. They are transient and recreated on each visit. RewardDefinition has
editable amount/effect, sprite, fallback color, pickup/appearance cues,
pickup_delay_ticks, lifetime_ticks, frame_ticks, and fairy flight settings.
These are independent of ROM data. All imported sprites, palette variants, and
loot-table rows remain in ignored imported/.

## Checks and remaining fidelity work

Clock/fairy Godot checks cover collection delays, freezing, damage immunity,
source exceptions and custom overrides, death animations, leaving/loading,
flight acceleration, healing/capacity, editable lifetime, weapon collection, and
sixteenth-kill selection. Python checks compare local loot rows, sprite pixels,
and player palette variants against the ROM. Visual previews: reward_lab
(ROM-free) and clock_fairy (local import).

No emulator frame replay has been performed. Clock palette phase is tied to the
native simulation frame rather than the NES invincibility byte. Object timers
and slot scheduling are still approximations. Stationary pond fairies and their
circling-heart refill sequence are a separate overworld feature and remain TODO.
