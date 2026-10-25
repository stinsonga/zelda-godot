extends SceneTree
## Ganon (Z_04 InitGanon, UpdateGanon) and Zelda (InitZelda, UpdateZelda). The
## native fixtures need no ROM; the imported checks run with a local import.
const Fight = preload("res://scripts/ganon.gd")
const ItemObject = preload("res://scripts/item_object.gd")
var failures := 0

func _initialize() -> void:
	create_timer(90).timeout.connect(func() -> void: push_error("Ganon suite timed out"); quit(1))
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func fixture_room(world: Node, id: StringName, spawns: Array) -> Resource:
	var room: Resource = world.room.duplicate()
	room.id = id
	room.enemy_persistence = "overworld"
	var list: Array[Resource] = []
	for i in range(spawns.size()):
		var spawn = preload("res://scripts/enemy_spawn.gd").new()
		spawn.id = StringName("slot_%d" % i)
		spawn.enemy = spawns[i][0]
		spawn.position = spawns[i][1]
		list.append(spawn)
	room.enemies.assign(list)
	world.rooms[room.id] = room
	return room

func tick(world: Node, direction := Vector2i.ZERO) -> void:
	world.combat.player_invulnerability = 100000
	world.simulate_tick(direction)

func run() -> void:
	var world = preload("res://scenes/combat_lab.tscn").instantiate()
	root.add_child(world)
	world.set_physics_process(false)
	check_intro_and_fight(world)
	check_brown_recovery(world)
	check_zelda(world)
	world.free()
	check_imported()
	print("Ganon checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)

func enter_ganon(world: Node) -> RefCounted:
	var room := fixture_room(world, &"ganon_fixture", [[preload("res://content/enemies/ganon.tres"), Vector2i(112, 40)]])
	world.state.room_records.clear()
	world.combat.encounter_room = null
	world.enter_room(room, Vector2i(120, 125), Vector2i.UP)
	return world.combat.enemies[0]

## Run the intro to the start of the fight; returns the frames it took.
func finish_intro(world: Node, fight: RefCounted) -> int:
	var frames := 0
	while fight.scene < 2 and frames < 1000:
		tick(world)
		frames += 1
	return frames

func check_intro_and_fight(world: Node) -> void:
	var ganon: RefCounted = enter_ganon(world)
	var fight: RefCounted = ganon.family.ganon
	check(fight is Fight and world.combat.holds_player() and world.combat.darkness() == 4, "Ganon's room starts dark with Link held")
	check(not ganon.body_visible() and not ganon.targetable() and not ganon.can_touch_player(), "Ganon is unseen in the dark and neither fights nor collides during the intro")
	var start: Vector2i = world.player.pixel_position()
	for i in range(0x40): tick(world, Vector2i.LEFT)
	check(world.player.pixel_position() == start and fight.scene == 0 and world.combat.darkness() == 4, "Link stays put for $40 frames in the dark")
	check(ganon.body_visible() and fight.animation == 0, "Ganon appears in pose 0 as the room brightens")
	var lit := 0
	while fight.scene == 0 and lit < 200:
		tick(world)
		lit += 1
	check(world.combat.darkness() == 0 and lit == 31, "The room brightens in four steps ten frames apart (%d)" % lit)
	var hold := finish_intro(world, fight)
	check(hold == 0xC0 and not world.combat.holds_player(), "Link holds the Triforce $C0 frames more (%d)" % hold)
	check(not ganon.body_visible() and ganon.can_touch_player() and ganon.targetable(), "Ganon vanishes and can be struck while unseen")
	# He idles until the turn counter reaches $40, then moves a pixel a frame.
	var before: Vector2i = ganon.position()
	for i in range(62): tick(world)
	check(ganon.position() == before, "Ganon does not move before his first turn")
	var shots := 0
	for i in range(0x80):
		var count: int = world.combat.rocks.size()
		tick(world)
		if world.combat.rocks.size() > count: shots += 1
	check(ganon.position() != before and fight.direction != Vector2i.ZERO, "Ganon moves after the first turn")
	check(shots == 2, "Ganon shoots every $40 frames (%d)" % shots)
	check(world.combat.rocks.all(func(r: RefCounted) -> bool: return r.kind == "fireball" and not r.magic_blockable), "His shots are unblockable fireballs")
	# Sword only, while unseen; a hit shows him for $40 frames without recoil.
	check(not ganon.receive_hit(1, Vector2i.UP, "beam") and not ganon.parried_hit, "Beams pass through Ganon")
	check(ganon.receive_hit(1, Vector2i.UP, "sword") and ganon.health == 2 and ganon.invulnerability == 0 and ganon.shove_remaining == 0, "The sword hurts Ganon without recoil")
	check(ganon.body_visible() and not ganon.targetable() and not ganon.receive_hit(1, Vector2i.UP, "sword"), "A struck Ganon is shown and cannot be hit again")
	for i in range(0x3F): tick(world)
	var spots: Array = Array(ganon.definition.ganon_spots).map(func(v: Vector2) -> Vector2i: return Vector2i(v))
	check(ganon.position() in spots and fight.timer == 1, "When shown long enough he reappears at one of two spots (%s)" % ganon.position())
	tick(world)
	check(not ganon.body_visible(), "Then he vanishes again")
	# Lethal damage turns him brown with fresh HP.
	ganon.receive_hit(ganon.health, Vector2i.UP, "sword")
	check(fight.state == 0xFF and fight.palette == "brown" and ganon.health == ganon.definition.ganon_brown_health, "Lethal sword damage turns Ganon brown instead of killing him")
	check(ganon.sprite_name() == StringName("lab_shadow_boss_brown_%d" % fight.animation), "Brown sprite name")
	var brown_at: Vector2i = ganon.position()
	# An ordinary arrow passes through; a silver arrow starts his death.
	world.state.slots[&"arrows"] = 1
	var arrow = ItemObject.arrow(ganon.hit_position() + Vector2i(0, 20), Vector2i.UP, 2)
	world.item_objects.append(arrow)
	for i in range(8): tick(world)
	check(fight.dying == 0 and arrow.stage == 1, "Wooden arrows pass through brown Ganon")
	world.item_objects.clear()
	world.state.slots[&"arrows"] = 2
	arrow = ItemObject.arrow(ganon.hit_position() + Vector2i(0, 20), Vector2i.UP, 2)
	world.item_objects.append(arrow)
	for i in range(8): tick(world)
	check(fight.dying > 0 and arrow.stage == 2, "A silver arrow strikes brown Ganon")
	while fight.dying < 0x50: tick(world)
	check(ganon.position() == brown_at + Vector2i(8, 8) and fight.palette == "triforce" and fight.rays.size() == 8, "At $50 the ashes land 8 right and 8 down and the burst begins")
	# The setup frame also runs Ganon_DrawBurst, so cardinal rays have moved once.
	check(fight.rays[0] == ganon.position() + Vector2i(5, 4) and fight.rays[5] == ganon.position() + Vector2i(4, 3), "Rays start at the ashes' centre")
	for i in range(16): tick(world)
	var diagonal: int = fight.rays[3].x - ganon.position().x - 4
	check(fight.rays[0] == ganon.position() + Vector2i(21, 4) and diagonal >= 12 and diagonal <= 13, "Cardinal rays move every frame, diagonal ones three in four (%d)" % diagonal)
	check(fight.cloud_distance < 8, "The clouds close in")
	check(not world.room_clear(), "The room stays shut until the item appears")
	while fight.dying < 0xA0: tick(world)
	tick(world)
	check(ganon.health == 0 and world.combat.room_item_position == ganon.position() and world.room_clear(), "At $A0 the room item appears on the ashes and the room is clear")
	check(world.combat.encounter_kills == 1, "Ganon counts once for the room")

func check_brown_recovery(world: Node) -> void:
	var ganon: RefCounted = enter_ganon(world)
	var fight: RefCounted = ganon.family.ganon
	finish_intro(world, fight)
	ganon.receive_hit(ganon.health, Vector2i.UP, "sword")
	var frames := 0
	while fight.state != 0 and frames < 1000:
		tick(world)
		frames += 1
		if fight.state == 0x2F: check(not ganon.body_visible() or ganon.animation_ticks & 1 == 1, "Below $30 the brown body flickers")
	check(frames >= 0x1FC and frames <= 0x1FF, "Brown lasts $FF steps every other frame (%d)" % frames)
	var spots: Array = Array(ganon.definition.ganon_spots).map(func(v: Vector2) -> Vector2i: return Vector2i(v))
	check(fight.palette == "blue" and ganon.position() in spots and ganon.health == ganon.definition.ganon_brown_health, "Then he is blue again at a spot, keeping the restored HP")
	check(not world.combat.ganon_arrow_hit(ganon, true), "Silver arrows do nothing while he is blue")

func check_zelda(world: Node) -> void:
	var spawns := [[preload("res://content/enemies/zelda.tres"), Vector2i(0x78, 0x88 - 64)]]
	for spot in [Vector2i(0x60, 0xB5), Vector2i(0x70, 0x9D), Vector2i(0x80, 0x9D), Vector2i(0x90, 0xB5)]:
		spawns.append([preload("res://content/enemies/guard_fire.tres"), spot - Vector2i(0, 64)])
	var room := fixture_room(world, &"zelda_fixture", spawns)
	world.state.room_records.clear()
	world.combat.encounter_room = null
	world.enter_room(room, Vector2i(0x78, 0x95 - 64 + 16), Vector2i.UP)
	var zelda: RefCounted = world.combat.enemies[0]
	check(not zelda.targetable() and not zelda.can_touch_player(), "Zelda neither collides nor takes hits")
	check(world.combat.enemies.slice(1).all(func(f: RefCounted) -> bool: return f.targetable() and f.can_touch_player()), "Guard fires burn and can be struck")
	tick(world)
	check(zelda.family.zelda_state == 0 and not world.combat.holds_player(), "Nothing happens until Link reaches her")
	world.player.place(Vector2i(0x78, 0x95 - 64))
	tick(world)
	check(zelda.family.zelda_state == 1 and world.combat.holds_player(), "At Y $95 between X $70 and $80 Link is halted")
	check(world.player.pixel_position() == Vector2i(0x88, 0x88 - 64) and world.player.facing == Vector2i.LEFT, "Link is placed at ($88, $88) facing left")
	for i in range(0x7F): tick(world)
	check(not world.combat.ending, "The fanfare runs $80 frames")
	tick(world)
	check(world.combat.ending and world.state.flags.get("zelda_rescued", false), "Then the ending begins")
	var at: Vector2i = world.player.pixel_position()
	tick(world, Vector2i.DOWN)
	check(world.player.pixel_position() == at, "Play stops for the ending")

func check_imported() -> void:
	if not ResourceLoader.exists("res://imported/enemies/ganon.tres"): return
	var world = preload("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_physics_process(false)
	var room: Resource = world.rooms[&"l9_42"]
	world.enter_room(room, Vector2i(120, 125), Vector2i.UP)
	var ganon: RefCounted = world.combat.enemies[0]
	check(ganon.definition.behavior == "ganon" and world.combat.darkness() == 4, "Imported Ganon's room starts dark")
	check(ganon.definition.ganon_spots == PackedVector2Array([Vector2(0x30, 0xA0 - 64), Vector2(0xB0, 0xA0 - 64)]), "Ganon reappears at ($30, $A0) or ($B0, $A0)")
	var pickup: Resource = room.pickups[0]
	check(pickup.item.id == &"triforce_of_power" and pickup.requires_clear, "The Triforce of Power waits for Ganon")
	var fight: RefCounted = ganon.family.ganon
	finish_intro(world, fight)
	fight.state = 0xFF
	world.combat.ganon_arrow_hit(ganon, true)
	while ganon.health > 0: tick(world)
	check(world.pickup_position(pickup) == ganon.position(), "The Triforce of Power appears on the ashes")
	world.enter_room(world.rooms[&"l9_32"], Vector2i(120, 125), Vector2i.UP)
	var kinds: Array = world.combat.enemies.map(func(a: RefCounted) -> String: return a.definition.behavior)
	check(kinds == ["zelda", "guard_fire", "guard_fire", "guard_fire", "guard_fire"], "Zelda's room holds Zelda and four guard fires (%s)" % [kinds])
	check(world.combat.enemies[0].position() == Vector2i(0x78, 0x88 - 64) and world.combat.enemies[1].position() == Vector2i(0x60, 0xB5 - 64), "InitZelda positions")
	world.free()
