extends "res://tests/generated_dungeons.gd"
const Fixture = preload("res://editor/tests/template_fixture.gd")
func run() -> void:
	var loaded := Templates.read("res://content/templates/cellar_templates.json")
	check(loaded.errors.is_empty(),"Shipped cellar library loads")
	if not loaded.errors.is_empty(): quit(1);return
	var catalog: Dictionary = loaded.catalog
	check(Templates.validate(catalog).is_empty(),"Cellar-unit library validates")
	for recipe in [[42,6],[7,8]]:
		var generated := Generator.new().generate(catalog,recipe[0],recipe[1])
		check(generated.errors.is_empty(),"Cellar-unit recipe generates")
		if generated.has("pack"):
			check(generated.pack.goals.any(func(goal): return goal.room.contains("_cellar_")),"Goal is in instanced cellar")
			replay(generated.pack,generated.proof)
	var nested := Generator.new().generate(Fixture.nested_catalog(),42,6)
	check(nested.errors.is_empty(),"Nested cellar unit generates")
	if nested.has("pack"): replay(nested.pack,nested.proof)
	print("Generated cellar native checks: ","PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
