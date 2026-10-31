extends SceneTree
const Fixture = preload("water_fixture.gd")
const Pack = preload("../shared/room_pack.gd")
const Solver = preload("../shared/progression_solver.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok: failures+=1;push_error(message)
func _initialize() -> void:
	create_timer(30).timeout.connect(func(): push_error("Water solver test timed out");quit(1))
	call_deferred("run")
func run() -> void:
	var pack := Fixture.sample()
	check(Pack.validate(pack).is_empty(),"Water fixture validates: "+str(Pack.validate(pack)))
	var proof := Solver.new().solve(pack)
	check(proof.status == "solved","Ladder crosses one-tile water: "+Solver.format_report(proof))
	var crossings: Array = proof.events.filter(func(e): return e.type == "ladder")
	check(crossings.size() == 2 and crossings[0].direction == "up" and crossings[1].direction == "right","Witness crosses the river up and the stream right")
	check(Solver.new().solve(Fixture.sample(1,false)).status == "blocked","Water is solid without the ladder")
	check(Solver.new().solve(Fixture.sample(2)).status == "blocked","The ladder spans only one tile")
	print("Water solver checks: ","PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
