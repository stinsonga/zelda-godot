extends SceneTree
const Fixture = preload("bomb_capacity_fixture.gd")
const Pack = preload("../shared/room_pack.gd")
const Solver = preload("../shared/progression_solver.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok: failures+=1;push_error(message)
func _initialize() -> void:
	create_timer(60).timeout.connect(func(): push_error("Bomb capacity test timed out");quit(1))
	call_deferred("run")
func run() -> void:
	var pack := Fixture.sample()
	check(Pack.validate(pack).is_empty(),"Bomb corridor validates: "+str(Pack.validate(pack)))
	var proof := Solver.new().solve(pack)
	check(proof.status == "solved","Twelve bombs, refilled late, open nine walls: "+Solver.format_report(proof))
	var overflow := Solver.new().solve(Fixture.sample(0))
	check(overflow.status == "blocked","Bundles taken together overflow the eight-bomb bag: "+Solver.format_report(overflow))
	print("Bomb capacity checks: ","PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
