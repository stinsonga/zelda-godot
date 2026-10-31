extends "res://tests/generated_dungeons.gd"
## Solver witnesses for ladder crossings and overflowing bomb supplies replay
## in the native game.
const Water = preload("res://editor/tests/water_fixture.gd")
const Bombs = preload("res://editor/tests/bomb_capacity_fixture.gd")
func run() -> void:
	for pack in [Water.sample(), Bombs.sample()]:
		var proof := Solver.new().solve(pack)
		check(proof.status == "solved",pack.id+" has a witness")
		if proof.status == "solved": replay(pack,proof)
	print("Progression route checks: ","PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
