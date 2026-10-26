class_name RoomLighting
extends RefCounted
## AnimateWorldFading: normal plus three dark palettes, four writes ten ticks apart.
var stage := 0
var steps: Array[int] = []
var timer := 0
var step_ticks := 10

func fading() -> bool:
	return not steps.is_empty()

func begin(brighten: bool, ticks: int = 10) -> void:
	step_ticks = maxi(1,ticks)
	steps.assign([3,2,1,0] if brighten else [0,1,2,3])
	timer = 0

func tick() -> void:
	if not fading():return
	if timer > 0:timer-=1
	if timer > 0:return
	stage=steps.pop_front()
	timer=step_ticks if fading() else 0

func enter(room: Resource, same_level: bool, previous_stage: int, restoring: bool, cinematic: bool) -> void:
	steps.clear()
	timer=0
	step_ticks=room.light_step_ticks
	if cinematic:
		# Ganon owns the fade timing; its current darkness selects the palette.
		stage=0
	elif restoring:
		stage=3 if room.dark_room else 0
	elif room.dark_room:
		stage=3 if same_level and previous_stage==3 else 0
		if stage==0:begin(false,step_ticks)
	elif same_level and previous_stage>0:
		stage=previous_stage
		begin(true,step_ticks)
	else:stage=0

func candle(room: Resource) -> void:
	if room.dark_room and stage>0 and not fading():begin(true,room.light_step_ticks)
