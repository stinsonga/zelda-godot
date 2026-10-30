extends RefCounted
## Data-only clip selection shared by editor previews and game actors.
static func select(clips: Dictionary, wanted: String) -> String:
	if clips.has(wanted): return wanted
	for fallback in ["walk","idle"]:
		if clips.has(fallback): return fallback
	return ""
static func frame(clips: Dictionary, wanted: String, ticks: int, count: int, frame_ticks: int) -> int:
	var selected := select(clips,wanted)
	if selected.is_empty(): return posmod(int(ticks/maxi(1,frame_ticks)),maxi(1,count))
	var clip: Dictionary = clips[selected]
	var index := maxi(0,int(ticks/int(clip.frame_ticks)))
	index = index%clip.frames.size() if clip.loop else mini(index,clip.frames.size()-1)
	return int(clip.frames[index])
static func duration(clips: Dictionary, wanted: String) -> int:
	if not clips.has(wanted): return 0
	return clips[wanted].frames.size()*int(clips[wanted].frame_ticks)
