class_name LootTable
extends Resource
## Entries address the global kill cycle. Null entries intentionally drop nothing.
@export_range(0, 256) var chance: int = 128
@export var entries: Array[Resource] = []

func entry(kill_cycle: int) -> Resource:
	if entries.is_empty(): return null
	return entries[posmod(kill_cycle, entries.size())]

func select(kill_cycle: int, roll: int) -> Resource:
	if entries.is_empty() or roll >= chance:
		return null
	return entries[posmod(kill_cycle, entries.size())]
