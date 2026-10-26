extends SceneTree
const Food = preload("res://scripts/item_object.gd")
const Store = preload("res://scripts/save_store.gd")
var failures := 0
func _initialize() -> void:
 call_deferred("run")
func check(value: bool, message: String) -> void:
 if not value:
  failures += 1
  push_error(message)
func run() -> void:
 var food = Food.bait(Vector2i(64, 80))
 for i in range(764): food.tick()
 check(food.active and food.position == Vector2i(64,80) and not food.hits(food.position), "Bait stays put without damage for 764 ticks")
 food.tick()
 check(not food.active, "Bait expires at 765 ticks")
 food = Food.bait(Vector2i.ZERO, 12)
 for i in range(12): food.tick()
 check(not food.active, "Custom bait lifetime works")
 var world = preload("res://scenes/bait_lab.tscn").instantiate()
 root.add_child(world)
 world.set_physics_process(false)
 world.scroll_transitions = false
 world.save_store = Store.new(OS.get_temp_dir().path_join("zelda-bait-%d" % OS.get_process_id()))
 check(world.room.validation_errors().is_empty(), "Authored bait lab validates")
 for i in range(1000):
  if world.cave_session.phase == "waiting_bait": break
  world.simulate_tick(Vector2i.ZERO)
 check(world.cave_session.phase == "waiting_bait", "Resident finishes dialogue and waits for bait")
 world.simulate_tick(Vector2i.ZERO)
 check(world.state.item_value(&"bait") == 1, "The lab supplies editable bait")
 check(not world.can_enter_segment(Vector2i(120,77),Vector2i.UP), "Hungry resident blocks northward passage")
 world.player.place(Vector2i(64,125))
 world.state.selected_item = &"bait"
 check(world.use_item(), "Bait can be placed away from resident")
 check(world.cave_session.phase == "feeding" and world.cave_session.timer == 64, "Bait anywhere starts the 64-tick feeding sequence immediately")
 check(not world.save_game(), "Checkpoint waits for feeding to finish")
 var at: Vector2i = world.player.pixel_position()
 for i in range(63): world.simulate_tick(Vector2i.RIGHT)
 check(world.cave_session.phase == "feeding" and world.player.pixel_position() == at, "Feeding holds Link for its duration")
 world.simulate_tick(Vector2i.RIGHT)
 check(world.cave_session.phase == "gone" and world.state.item_value(&"bait") == 0 and world.item_objects.is_empty(), "Feeding removes resident and consumes bait")
 check(world.can_enter_segment(Vector2i(120,77),Vector2i.UP), "Feeding opens the northern passage")
 check(world.save_game(), "Completed feeding can be saved")
 check(world.load_game() and world.cave_session.phase == "gone" and world.state.item_value(&"bait") == 0, "Checkpoint retains fed resident and consumed bait")
 world.enter_room(world.room,Vector2i(120,125),Vector2i.UP)
 check(world.cave_session.phase == "gone", "Resident remains gone on reentry")
 world.state.take_item(preload("res://content/items/bait.tres"))
 world.state.selected_item = &"bait"
 check(world.use_item() and not world.use_item(), "Only one bait object may be active")
 world.state.slots[&"boomerang"] = 1
 world.state.selected_item = &"boomerang"
 check(not world.use_item(), "Bait occupies the boomerang slot")
 world.item_objects.clear()
 check(world.use_item(), "Boomerang can fly once bait is gone")
 world.state.selected_item = &"bait"
 check(not world.use_item(), "Flying boomerang prevents bait placement")
 world.item_objects.clear()
 world.item_objects.append(Food.bait(Vector2i(64,80)))
 world.room = world.room.duplicate(true)
 var spawn = preload("res://scripts/enemy_spawn.gd").new()
 spawn.enemy = preload("res://scripts/enemy_definition.gd").new()
 world.room.enemies.assign([spawn])
 world.combat.enemies.clear()
 for kind in [1,3,10,11,0x12,0x1B,0x1C,0x1D]:
  spawn.enemy.nes_type = kind
  world.combat.chase_other = false
  world.combat.chase_timer = 5
  world.combat.tick(world)
  var eligible: bool = kind in [3,10,0x12,0x1B,0x1C]
  check(world.combat.chase_target == (Vector2i(64,80) if eligible else world.player.pixel_position()), "Source bait attraction template %d" % kind)
 for mode in ["enabled","disabled"]:
  world.room.bait_attraction = mode
  world.combat.chase_other = false
  world.combat.chase_timer = 5
  world.combat.tick(world)
  check(world.combat.chase_target == (Vector2i(64,80) if mode == "enabled" else world.player.pixel_position()), "Editable bait attraction " + mode)
 world.enter_room(world.room,Vector2i(120,125),Vector2i.UP)
 check(world.item_objects.is_empty() and world.state.item_value(&"bait") == 1, "Leaving removes placed bait without consuming inventory")
 if ResourceLoader.exists("res://imported/rooms/l7_28.tres"):
  var original = load("res://imported/rooms/l7_28.tres")
  check(original.cave != null and original.cave.accepts_bait and original.cave.remember and original.cave.person_sprite == &"l7_hungry_goriya", "Original hungry Goriya imports as persistent resident with original sprite")
 world.free()
 print("Bait checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
 quit(0 if failures == 0 else 1)
