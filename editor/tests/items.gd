extends SceneTree
const Fixture = preload("items_fixture.gd")
const Pack = preload("../shared/room_pack.gd")
const Solver = preload("../shared/progression_solver.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok: failures+=1;push_error(message)
func _initialize() -> void:
	create_timer(60).timeout.connect(func(): push_error("Item test timed out");quit(1))
	call_deferred("run")
func run() -> void:
	var pack := Fixture.sample()
	check(Pack.validate(pack).is_empty(),"Packs accept the wider item list: "+str(Pack.validate(pack)))
	for item in Pack.ITEMS: check(FileAccess.file_exists(ProjectSettings.globalize_path("res://").path_join("../content/items/"+item+".tres")),"Every pack item has a game resource: "+item)
	var broken := pack.duplicate(true);broken.rooms[0].pickups[0].item = "triforce"
	check(not Pack.validate(broken).is_empty(),"Items that end a level are not room pickups")
	var proof := Solver.new().solve(pack)
	check(proof.status == "solved","A red candle opens a blue-candle gate")
	broken = pack.duplicate(true);broken.rooms[0].pickups.remove_at(3)
	check(Solver.new().solve(broken).status == "blocked","Without a candle the gate stays shut")
	broken = pack.duplicate(true);broken.rooms[0].pickups[3].item = "white_sword"
	broken.rooms[0].connections.up.requires = ["wooden_sword"];broken.rooms[1].connections.down.requires = ["wooden_sword"];broken.starting_items = []
	check(Solver.new().solve(broken).status == "solved","A white sword opens a sword gate")
	broken.rooms[0].pickups[3].item = "boomerang"
	check(Solver.new().solve(broken).status == "blocked","Other items do not open gates")
	var state := {"rupees":0,"keys":0,"bombs":0,"items":0}
	var solver := Solver.new();solver.take(state,"five_rupees");solver.take(state,"rupee")
	check(state.rupees == 6,"Five rupees count five")
	print("Item checks: ","PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
