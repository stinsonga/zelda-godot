extends "res://tests/generated_dungeons.gd"
## A two-floor pack: its witness climbs the stairs natively, and the maps keep
## to the current floor.
const Fixture = preload("res://editor/tests/floors_fixture.gd")
func run() -> void:
	var pack := Fixture.sample()
	var compiled := Adapter.compile(pack)
	check(compiled.errors.is_empty(),"Two-floor pack compiles")
	var floors: Dictionary = {}
	for room in compiled.world.rooms: floors[String(room.id)] = room.map_floor
	check(floors == {"entry":0,"landing":1,"gallery":1},"Rooms carry their floors")
	var proof := Solver.new().solve(pack)
	check(proof.status == "solved","Two-floor pack has a witness")
	if proof.status == "solved": replay(pack,proof)
	print("Authored floor checks: ","PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
