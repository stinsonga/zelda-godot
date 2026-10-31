# Progression through residents and shops

Progression checking now models hint-room movement barriers, one-time gifts,
rupees and shop purchases. It searches item/ware choices and return visits instead
of treating residents as free pickups or rejecting every resident room. The game
runtime and shared resident data are unchanged.

## Try a certified shop route

Open `content/packs/shop_route.json`, then **Dungeon → Check progression**.
Collect four entrance coins, buy a two-rupee key, leave and return to buy a second
key, then open both north locks and collect the objective. The witness includes
coin collection, purchases, stair returns and key spending. **Play dungeon** uses
the same ordinary authored rooms and native cave-session rules.

The route is not required to be optimal. It proves existence under the report's
model, not recovery from every wrong purchase or spent resource. Structural
validation alone still does not prove completion.

## Modeled state

- Fresh-pack inventory and a zero starting wallet; authored rupee pickups add one.
- Finite keys and bombs, opened door pairs, required items and objective pickups.
- Gift collection remembered separately for each room across all visits.
- A shop permits one purchase per visit. Changing rooms resets its availability;
  merely moving away from a ware does not. Zero-price purchases still consume
  that visit's choice.
- Prices are checked before spending. A route cannot spend the same rupees twice.
- Hint residents remain present. Gifts and purchases remove the resident after
  its native lift/hide sequence. The native directional barrier prevents upward
  movement from Link Y 77 and above while a resident remains.
- Physical stand positions and arrival suppression are retained alongside the
  economy, so spending money cannot reset position across a one-way barrier.

Reports show each purchased/received item, ware slot, price and wallet balance.
Structured witness events record transactions and coin collection positions.
Native regression tests replay these through actual player movement, wait out
text/lifts/rupee counters, and verify the selected ware, wallet coverage, doors,
objectives and completion flag. Gifts can supply the sword before an assumed
combat encounter, or provide a coin that funds a later purchase.

## Conservative routing and bounds

Offers trigger automatically in the game. The certified planner treats their
approach squares as interaction stops and avoids **unchosen** offers, including
those currently unaffordable. It does not promise a route that threads through
an offer without buying it. This restriction prevents extra automatically
collected coins from turning an ignored offer into an unintended purchase.
A BLOCKED report can therefore describe a route outside this model that a human
could still complete; playtesting remains useful.

Dialogue, item lifts and rupee animations are allowed to finish between actions.
Resident rooms have no regular enemies or block secrets under the existing
contract, so waiting there does not require a new combat assumption.

In rooms without residents, reachable finite coins are collected together as one
search event. Those regions have no resident one-way barrier or offer squares;
active stairs remain terminal squares. Collecting finite coins early can only
help within the modeled capacity bounds. Coins inside resident rooms keep
individual stand positions rather than merging paths across the barrier.

The existing limits remain 32 rooms, 48 pickups and 48 door pairs. With no starting
cash or repeatable money offers, at most 48 floor coins plus 32 one-coin gifts
can be supplied, below the native 255-rupee cap. The search stores only as many
useful keys as the dungeon has key locks; this avoids endless free-key shopping
without granting keys the player does not have.

These cases explicitly return **UNSUPPORTED**:

- Shops offering rupees, which could create repeatable income and wallet-capacity
  timing dependencies. They remain authorable and playable.
- A bomb shop combined with starting, floor or gift bomb supplies. Automatic
  pickups near the eight-bomb cap need finer timing before certification.
- Other existing unsupported mechanics, such as enemy-drop
  dependencies. Combat remains the stated sword-vulnerable assumption.

Bomb shops with no other finite bomb supplies are supported, including repeat
purchases and spending bombs on doors. Search/time limits remain inconclusive;
they never count as a successful proof.

## Generation compatibility

Template libraries containing residents use `authored_tree` recipe **version 3**
and a `generated_v3_...` world ID. This separates the newly accepted resident
candidates from worlds an older generator could publish with the same library.
Libraries with bomb/fire secrets use version 4 instead. Other resident-free
format-1/format-2 libraries retain recipe versions 1/2 and their
existing seed identities. The legacy seed-42 checksum remains covered by tests.
No library format or pack schema upgrade is required to check resident routes.
Cave-network template capture is still outside the cellar-only multi-room format.

## Verification

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path editor --script res://tests/resident_progression.gd --log-file /tmp/resident-solver.log
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/resident_routes.gd --log-file /tmp/resident-routes.log
```

Coverage includes repeated paid/free key purchases, a 20-coin budget, one-time
and item-gated gifts, a gift-funded shop, hint/gift barriers, ware choices,
insufficient funds and overspending, shop bombs, explicit unsupported cases,
JSON round trips, limits, and a generated resident-bearing dungeon. Fresh
source-only copies need the normal Godot editor import before native tests.
