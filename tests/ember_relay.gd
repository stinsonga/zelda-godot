extends "res://tests/generated_dungeons.gd"
## Replay the GUI-authored example through native movement, items and doors.
## As in the progression model, sword encounters are assumed winnable.
func run() -> void:
	var loaded := Pack.read("res://content/packs/ember_relay.json")
	check(loaded.errors.is_empty(),"GUI-authored Ember Relay loads")
	if not loaded.errors.is_empty(): print(loaded.errors);quit(1);return
	check(loaded.pack.rooms.size()==4 and loaded.pack.id=="ember_relay","Example retains four GUI-authored rooms and its independent identity")
	var proof := Solver.new().solve(loaded.pack)
	check(proof.status=="solved","Example's key, item, encounter and block progression solves")
	if proof.status=="solved":
		check(proof.events.filter(func(event): return event.type=="stairs").size()==2,"Witness enters and returns from cellar")
		check(proof.events.any(func(event): return event.type=="door" and event.kind=="key"),"Witness spends a real key")
		check(proof.events.any(func(event): return event.type=="push"),"Witness pushes the final block")
		replay(loaded.pack,proof)
	print("Ember Relay native playthrough: ","PASS" if failures==0 else "FAIL")
	quit(0 if failures==0 else 1)
