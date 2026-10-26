# Stepladder

The ladder is passive equipment. Walking toward eligible water deploys it
automatically; it does not occupy a B-item selection. Cross on its original axis
or retreat to the starting shore. Sideways movement while over water is blocked.
At the center, continuing forward requires a walkable far bank: the ladder cannot
chain across a lake. It disappears after Link steps off or enters another room.
Attacks and other items remain available while standing on it.

The source is Z_07 Link_EndMoveAndAnimate (deployment) and Z_05 CheckLadder
(movement). Horizontal/downward placement is sixteen pixels ahead; upward
placement is eight pixels ahead. The drawn ladder is three pixels below that
logical anchor. Upward center checks probe an additional eight pixels ahead,
matching the source's special handling of Link's top half.

Imports preserve the original overworld permission list (rooms $17, $18, $19,
$27, $4F, $5F), water tiles $8D..$98, and dungeon water tile $F4. Ordinary walls,
bushes, and statues never count as water. Water eligibility is separate from
collision and graphics, so replacing the art does not affect crossing behavior.
The deployed sprite is exported separately with the source's palette attribute
zero; all ROM-derived masks and art remain in ignored imported content.

Native checkpoints retain ladder ownership. Saving waits until a deployed ladder
is put away, so loading cannot strand Link over water without a crossing object.
Loading an earlier checkpoint or entering a room clears deployment.

## Editable rooms

Run the ROM-free `scenes/ladder_lab.tscn`: collect the ladder at the starting
position, then walk north to cross the river. A narrower pool supports horizontal
crossings; the larger pool tests the limit on crossing deep water.

- `~` in `RoomDefinition.tiles` is solid ladder-eligible water, drawn blue by
  the native fallback renderer. `#` is an ordinary solid wall; `.` is floor.
- `ladder_allowed` enables deployment in that room (default true).
- For eight-pixel layouts, supply `ladder_water`, a 704-entry mask in row-major
  order, matching `collision_tiles`. Mark eligible water with 1. Supply collision
  separately; the mask does not make water solid by itself.
- Give Link `content/items/ladder.tres` through any normal pickup or cave gift.

`tests/ladder.gd` checks crossings in all directions, retreat, perpendicular input,
pausing, deep-water rejection, ordinary walls, room permissions, mask validation,
room entry, and checkpoint ownership. Python import checks compare every
first-quest overworld and dungeon water mask against ROM layouts.

The actor budget check approximates the source's need for a free monster slot;
the project does not yet implement a unified NES object-slot allocator. No
emulator frame-by-frame comparison has been performed.
