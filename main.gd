extends Node3D
# Descent - Phase 0 readability prototype.
# One enemy loops IDLE -> WINDUP -> STRIKE -> RECOVERY -> IDLE.
# Counter with SPACE inside the TAIL of the windup. R re-reads tuning.json live.
# Whole scene is built in _ready() so there is no editor-authored .tscn to import.

# ---- tuning (hot-reloadable from res://tuning.json) ----
var telegraph_length: float = 1.2
var counter_window: float = 0.35
var camera_distance: float = 8.0
var windup_color_amount: float = 1.0
var windup_lean_amount: float = 1.0

# ---- hardcoded knobs (deliberately NOT in tuning.json) ----
const IDLE_MIN := 0.6            # idle-gap jitter range (seconds)
const IDLE_MAX := 1.6
const STRIKE_DURATION := 0.20    # quick lunge
const RECOVERY_TIME := 1.1       # holds the WIN/LOSE label, then auto-resets
const CAM_ELEV_DEG := 30.0       # look-down angle
const CAM_AZIM_DEG := 20.0       # slight side offset for a 3/4 frame
const CAM_FOCUS := Vector3(0.0, 0.8, 0.0)
const ENEMY_BASE := Vector3(0.0, 0.0, -2.5)
const PLAYER_POS := Vector3(0.0, 0.0, 2.5)
const LUNGE_Z := 1.4             # how far forward the strike travels
const WINDUP_STEP_BACK := 0.4    # how far the enemy coils back during the windup
const WINDUP_LEAN := -0.45       # rear back: -X rot tilts the capsule top away from the player
const STRIKE_LEAN := 0.5         # whip forward on the lunge
const COLOR_ENEMY := Color(0.80, 0.15, 0.12)   # red idle
const COLOR_WARN := Color(1.00, 0.82, 0.05)    # warning yellow (telegraph)
const COLOR_STRIKE := Color(0.95, 0.10, 0.05)  # aggressive red on commit
const COLOR_PLAYER := Color(0.15, 0.35, 0.85)  # blue
const COLOR_STAGGER := Color(0.32, 0.30, 0.33) # dimmed on a successful counter

enum State { IDLE, WINDUP, STRIKE, RECOVERY }
var state: int = State.IDLE
var state_time: float = 0.0
var idle_gap: float = 1.0
var counter_spent: bool = false     # one counter attempt per cycle
var result_text: String = "watching"
var flash: float = 0.0
var rec_start_pos: Vector3 = ENEMY_BASE
var rec_start_rot: float = 0.0

var enemy_root: Node3D
var enemy_mat: StandardMaterial3D
var player_root: Node3D
var camera: Camera3D
var windup_player: AudioStreamPlayer
var hit_player: AudioStreamPlayer
var result_label: Label
var info_label: Label
var flash_rect: ColorRect


func _ready() -> void:
	randomize()
	_load_tuning()
	_build_world()
	_build_hud()
	_apply_camera()
	_update_info_label()
	_enter_idle()


# ---------- input (no custom input map needed) ----------
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			_try_counter()
		elif event.keycode == KEY_R:
			_load_tuning()
			_apply_camera()
			_update_info_label()


func _try_counter() -> void:
	if counter_spent:
		return
	if state == State.WINDUP:
		counter_spent = true
		# window = [telegraph_length - w, telegraph_length] of windup-elapsed time.
		var w: float = minf(counter_window, telegraph_length)   # clamp: at most the whole windup
		if state_time >= telegraph_length - w:
			_win()
		# else: too early -> attempt spent, the strike still commits and lands -> LOSE
	elif state == State.STRIKE:
		counter_spent = true   # too late; the strike is already committed
	# IDLE / RECOVERY presses are ignored: nothing has telegraphed yet this cycle.


# ---------- state machine ----------
func _process(delta: float) -> void:
	state_time += delta
	if flash > 0.0:
		flash = max(0.0, flash - delta * 2.5)
		flash_rect.color = Color(0.6, 1.0, 0.7, flash * 0.55)

	match state:
		State.IDLE:
			if state_time >= idle_gap:
				_enter_windup()
		State.WINDUP:
			var p: float = clamp(state_time / telegraph_length, 0.0, 1.0)
			enemy_root.rotation.x = lerp(0.0, WINDUP_LEAN * windup_lean_amount, p)
			enemy_root.position = ENEMY_BASE + Vector3(0.0, 0.0, -WINDUP_STEP_BACK * windup_lean_amount * p)
			enemy_mat.albedo_color = COLOR_ENEMY.lerp(COLOR_WARN, p * windup_color_amount)
			if state_time >= telegraph_length:
				_enter_strike()
		State.STRIKE:
			var q: float = ease(clamp(state_time / STRIKE_DURATION, 0.0, 1.0), 0.35)
			enemy_root.rotation.x = lerp(WINDUP_LEAN * windup_lean_amount, STRIKE_LEAN, q)
			enemy_root.position = Vector3(0.0, 0.0, lerp(ENEMY_BASE.z - WINDUP_STEP_BACK * windup_lean_amount, LUNGE_Z, q))
			enemy_mat.albedo_color = COLOR_STRIKE
			if state_time >= STRIKE_DURATION:
				_lose()
		State.RECOVERY:
			var r: float = clamp(state_time / RECOVERY_TIME, 0.0, 1.0)
			enemy_root.position = rec_start_pos.lerp(ENEMY_BASE, r)
			enemy_root.rotation.x = lerp(rec_start_rot, 0.0, r)
			if state_time >= RECOVERY_TIME:
				_enter_idle()


func _enter_idle() -> void:
	state = State.IDLE
	state_time = 0.0
	idle_gap = randf_range(IDLE_MIN, IDLE_MAX)
	counter_spent = false
	result_text = "watching"
	enemy_mat.albedo_color = COLOR_ENEMY
	enemy_root.position = ENEMY_BASE
	enemy_root.rotation.x = 0.0
	_update_result_label()


func _enter_windup() -> void:
	state = State.WINDUP
	state_time = 0.0
	if windup_player.stream != null:
		var base_len: float = windup_player.stream.get_length()
		if base_len > 0.0 and telegraph_length > 0.0:
			windup_player.pitch_scale = base_len / telegraph_length
		windup_player.play()


func _enter_strike() -> void:
	windup_player.stop()   # windup.wav is fixed ~1.1s; don't let it bleed into the strike/hit
	state = State.STRIKE
	state_time = 0.0


func _enter_recovery(text: String) -> void:
	state = State.RECOVERY
	state_time = 0.0
	rec_start_pos = enemy_root.position
	rec_start_rot = enemy_root.rotation.x
	result_text = text
	_update_result_label()


func _win() -> void:
	# Visual feedback only (no third audio cue): flash + label + staggered pose.
	windup_player.stop()   # counter succeeded mid-windup; cut the rising tone
	flash = 1.0
	enemy_mat.albedo_color = COLOR_STAGGER
	enemy_root.rotation.x = -0.9
	enemy_root.position = ENEMY_BASE + Vector3(0.0, 0.0, -0.6)
	_enter_recovery("WIN")


func _lose() -> void:
	if hit_player.stream != null:
		hit_player.play()
	_enter_recovery("LOSE")


# ---------- camera (fixed 3/4 elevated frame, re-applied on reload) ----------
func _apply_camera() -> void:
	var elev: float = deg_to_rad(CAM_ELEV_DEG)
	var azim: float = deg_to_rad(CAM_AZIM_DEG)
	# behind the player (+Z), up (+Y), slight side offset (+X)
	var dir: Vector3 = Vector3(sin(azim) * cos(elev), sin(elev), cos(azim) * cos(elev))
	camera.position = CAM_FOCUS + dir * camera_distance
	camera.look_at(CAM_FOCUS, Vector3.UP)


# ---------- tuning load (guarded; falls back to defaults, never crashes) ----------
func _load_tuning() -> void:
	telegraph_length = 1.2
	counter_window = 0.35
	camera_distance = 8.0
	windup_color_amount = 1.0
	windup_lean_amount = 1.0
	if not FileAccess.file_exists("res://tuning.json"):
		return
	var f := FileAccess.open("res://tuning.json", FileAccess.READ)
	if f == null:
		return
	var txt := f.get_as_text()
	f.close()
	var data: Variant = JSON.parse_string(txt)
	if typeof(data) != TYPE_DICTIONARY:
		return
	telegraph_length = _num(data, "telegraph_length", telegraph_length)
	counter_window = _num(data, "counter_window", counter_window)
	camera_distance = _num(data, "camera_distance", camera_distance)
	windup_color_amount = clampf(_num(data, "windup_color_amount", windup_color_amount), 0.0, 1.0)
	windup_lean_amount = maxf(0.0, _num(data, "windup_lean_amount", windup_lean_amount))


func _num(d: Dictionary, key: String, fallback: float) -> float:
	if d.has(key) and (typeof(d[key]) == TYPE_FLOAT or typeof(d[key]) == TYPE_INT):
		return float(d[key])
	return fallback


# ---------- world build ----------
func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.06, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.5, 0.55)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(35.0), 0.0)
	sun.light_energy = 1.1
	add_child(sun)

	var arena := _load_model("res://assets/arena.glb")
	if arena == null:
		arena = _fallback_arena()   # ponytail: only used if arena.glb fails to import
	add_child(arena)

	player_root = Node3D.new()
	player_root.add_child(_model_or_capsule("res://assets/player.glb", COLOR_PLAYER, null))
	player_root.position = PLAYER_POS
	add_child(player_root)

	enemy_root = Node3D.new()
	enemy_mat = StandardMaterial3D.new()
	enemy_mat.albedo_color = COLOR_ENEMY
	enemy_root.add_child(_model_or_capsule("res://assets/enemy.glb", COLOR_ENEMY, enemy_mat))
	enemy_root.position = ENEMY_BASE
	add_child(enemy_root)

	camera = Camera3D.new()
	add_child(camera)

	windup_player = AudioStreamPlayer.new()
	windup_player.stream = _load_audio("res://assets/audio/windup.wav")
	add_child(windup_player)
	hit_player = AudioStreamPlayer.new()
	hit_player.stream = _load_audio("res://assets/audio/hit.wav")
	add_child(hit_player)


func _model_or_capsule(path: String, color: Color, mat_override: StandardMaterial3D) -> Node3D:
	var mat := mat_override
	if mat == null:
		mat = StandardMaterial3D.new()
		mat.albedo_color = color
	var scene := _load_model(path)
	if scene != null:
		var mi := _first_mesh_instance(scene)
		if mi != null:
			mi.set_surface_override_material(0, mat)
			return scene
	# ponytail: GLB import can fail (no editor here to import) -> same-shape/color primitive
	var wrap := Node3D.new()
	var cap := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.4
	cm.height = 2.0
	cap.mesh = cm
	cap.position.y = 1.0   # CapsuleMesh is centered at origin; lift so feet touch the ground
	cap.set_surface_override_material(0, mat)
	wrap.add_child(cap)
	return wrap


func _fallback_arena() -> Node3D:
	# ponytail: only used if arena.glb fails to import
	var root := Node3D.new()
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(12, 12)
	ground.mesh = pm
	ground.set_surface_override_material(0, _flat(Color(0.12, 0.12, 0.13)))
	root.add_child(ground)
	var wall_mat := _flat(Color(0.40, 0.40, 0.42))
	var h := 2.5
	var half := 5.0
	var specs := [
		[Vector3(0, h / 2, -half), Vector3(10, h, 0.3)],
		[Vector3(0, h / 2, half), Vector3(10, h, 0.3)],
		[Vector3(-half, h / 2, 0), Vector3(0.3, h, 10)],
		[Vector3(half, h / 2, 0), Vector3(0.3, h, 10)],
	]
	for s in specs:
		var w := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = s[1]
		w.mesh = bm
		w.position = s[0]
		w.set_surface_override_material(0, wall_mat)
		root.add_child(w)
	return root


func _flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m


func _load_model(path: String) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var res := load(path)
	if res is PackedScene:
		return (res as PackedScene).instantiate() as Node3D
	return null


func _first_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for c in node.get_children():
		var r := _first_mesh_instance(c)
		if r != null:
			return r
	return null


func _load_audio(path: String) -> AudioStream:
	if not FileAccess.file_exists(path):
		return null
	return AudioStreamWAV.load_from_file(path)


# ---------- HUD ----------
func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	flash_rect = ColorRect.new()
	flash_rect.color = Color(0.6, 1.0, 0.7, 0.0)
	flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(flash_rect)

	result_label = Label.new()
	result_label.add_theme_font_size_override("font_size", 52)
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	result_label.offset_top = 24
	result_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(result_label)

	info_label = Label.new()
	info_label.add_theme_font_size_override("font_size", 18)
	info_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	info_label.offset_left = 16
	info_label.offset_top = 12
	info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(info_label)

	_update_result_label()


func _update_result_label() -> void:
	result_label.text = result_text
	match result_text:
		"WIN":
			result_label.modulate = Color(0.4, 1.0, 0.5)
		"LOSE":
			result_label.modulate = Color(1.0, 0.4, 0.35)
		_:
			result_label.modulate = Color(0.85, 0.85, 0.9)


func _update_info_label() -> void:
	var w: float = minf(counter_window, telegraph_length)
	var opens: float = telegraph_length - w
	info_label.text = "telegraph_length: %.2f s\ncounter_window:  %.2f s\ncamera_distance: %.1f\nwindup_color_amount: %.2f\nwindup_lean_amount:  %.2f\ncounter window: %.2f-%.2f s of windup\nSPACE = counter    R = reload tuning" % [telegraph_length, counter_window, camera_distance, windup_color_amount, windup_lean_amount, opens, telegraph_length]
