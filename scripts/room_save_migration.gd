extends RefCounted
## Only known room-scoped save fields are rewritten. Global/unknown namespaces
## and local pickup/enemy IDs are opaque. Input snapshots are never modified.
static func room(id: String, aliases: Dictionary) -> String:
	var target: String = aliases.get(id,id)
	return target if not target.is_empty() else id
static func scoped(key: String, aliases: Dictionary) -> String:
	var slash := key.find("/")
	return room(key.left(slash),aliases)+key.substr(slash) if slash>0 else key
static func flag(key: String, aliases: Dictionary) -> String:
	var parts := key.split("/")
	if parts.size()==2 and parts[0] in ["secret","shutters","visited"]: return parts[0]+"/"+room(parts[1],aliases)
	if parts.size()==3 and parts[0]=="door" and parts[2] in ["up","right","down","left"]: return "door/"+room(parts[1],aliases)+"/"+parts[2]
	return key
static func remap(data: Dictionary, aliases: Dictionary) -> Dictionary:
	if aliases.is_empty(): return data
	var output: Dictionary = data.duplicate(true)
	output.room_id = aliases.get(data.room_id,data.room_id)
	for field in ["collected","defeated","flags"]:
		var mapped: Array = [];var seen: Dictionary = {}
		for key in data[field]:
			var value := flag(key,aliases) if field=="flags" else scoped(key,aliases)
			if not seen.has(value): mapped.append(value);seen[value] = true
		output[field] = mapped
	var history: Array = []
	for key in data.room_history: history.append(room(key,aliases))
	var unique: Array = []
	for key in history:
		if key not in unique: unique.append(key)
	if unique.size()!=history.size():
		# A full ring's cursor marks its oldest entry. Retain the most recent
		# occurrence of each identity and return to the normal partial-ring form.
		var ordered := history.slice(int(data.history_cursor))+history.slice(0,int(data.history_cursor)) if history.size()==6 else history
		unique.clear()
		for key in ordered: unique.erase(key);unique.append(key)
		output.room_history = unique;output.history_cursor = unique.size()
	else: output.room_history = history
	output.room_records = {}
	for key in data.room_records:
		var id := room(key,aliases);var record: Dictionary = data.room_records[key]
		if output.room_records.has(id):
			output.room_records[id].kills = maxi(int(output.room_records[id].kills),int(record.kills))
			output.room_records[id].cleared = output.room_records[id].cleared or record.cleared
		else: output.room_records[id] = record.duplicate(true)
	return output
