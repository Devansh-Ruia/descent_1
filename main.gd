extends Node3D
# Descent - Phase 2 decision prototype.
# One enemy loops IDLE -> WINDUP -> STRIKE -> RECOVERY -> IDLE, with a VENGEFUL
# interrupt on top: every hit you land makes it rise tall, tremble, and telegraph
# its next attack shorter (same counter window, less time to read it).
# SPACE counters attack A, K counters attack B, both only inside the TAIL of the
# windup. J attacks, and costs you your counter while the swing recovers. J cancels a
# normal wind-up but WHIFFS on the retaliation: the one you provoked has to be countered.
# R re-reads tuning.json live.
# Whole scene is built in _ready() so there is no editor-authored .tscn to import.

# ---- tuning (hot-reloadable from res://tuning.json) ----
var telegraph_length: float = 1.2
var counter_window: float = 0.35
var camera_distance: float = 8.0
var windup_color_amount: float = 1.0
var windup_lean_amount: float = 1.0
var enemy_hp: int = 3              # HP the enemy starts each fight with
var counter_damage: int = 1        # HP a successful counter takes off (countering never enrages)
var attack_damage: int = 1         # HP one landed J swing takes off
var player_attack_recovery: float = 1.0    # seconds your own swing leaves you unable to counter or swing again
var vengeful_duration: float = 2.5         # how long a hit keeps the enemy vengeful
var vengeful_telegraph_multiplier: float = 0.6   # telegraph scale while vengeful; window size is untouched
var seed_value: int = 0            # RNG seed for the A/B order + idle jitter; <= 0 = random per run

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
const CROUCH_SQUASH := 0.30      # attack B: how far the enemy squashes down during windup
const CROUCH_TIP_FWD := 0.25     # attack B: forward tip (+X rot) as it coils low
const CROUCH_WIDEN := 0.15       # attack B: lateral widen as it squashes (planted, low stance)
const HIT_FLINCH_TIME := 0.18    # brief knock-back so a landed player hit reads (no new audio cue)
const HIT_KNOCK := 0.35
const VENGE_STRETCH := 0.35      # vengeful: rise tall (must not read like A's rear-back or B's crouch)
const VENGE_SHAKE_AMP := 0.14    # vengeful: lateral tremor. 0.06 was ~2px at this camera distance, invisible
const VENGE_SHAKE_HZ := 7.0      # 22 Hz aliased past Nyquist at 30 fps capture and read as static; 7 Hz moves at 30 and 60
const VENGE_POSE_TIME := 0.9     # how long the rise-tall pose is held, capped by vengeful_duration
const VENGE_RAMP_IN := 0.12      # snap up
const VENGE_RAMP_OUT := 0.20     # settle back down, animated so the exit reads as an exit
const COLOR_ENEMY := Color(0.80, 0.15, 0.12)   # red idle
const COLOR_WARN := Color(1.00, 0.82, 0.05)    # warning yellow (telegraph)
const COLOR_STRIKE := Color(0.95, 0.10, 0.05)  # aggressive red on commit
const COLOR_PLAYER := Color(0.15, 0.35, 0.85)  # blue
const COLOR_STAGGER := Color(0.32, 0.30, 0.33) # dimmed on a successful counter

enum State { IDLE, WINDUP, STRIKE, RECOVERY, VENGEFUL }
enum AttackType { A, B }
var state: int = State.IDLE
var attack: int                      # which attack this cycle telegraphs (A rears back, B crouches)
var state_time: float = 0.0
var idle_gap: float = 1.0
var counter_spent: bool = false     # one counter attempt per cycle
var enemy_hp_left: int = 3          # refilled by _reset_fight (reload, FIGHT WON, or your death)
var player_recovery_left: float = 0.0   # your own swing's recovery; blocks SPACE/K while > 0
var hit_flinch: float = 0.0         # knock-back timer for a landed player hit
var vengeful_left: float = 0.0      # rage window: an attack starting while > 0 telegraphs short
var eff_telegraph: float = 1.2      # this cycle's telegraph, locked at _enter_windup so it cannot shift
var vengeful_cycle: bool = false    # is THIS wind-up a retaliation? locked alongside eff_telegraph
var result_text: String = "watching"
var flash: float = 0.0
var rec_start_pos: Vector3 = ENEMY_BASE
var rec_start_rot: float = 0.0
var rec_start_scale: Vector3 = Vector3.ONE
var rng := RandomNumberGenerator.new()   # seeded in _load_tuning -> reproducible A/B order + jitter

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
			_try_counter(AttackType.A)
		elif event.keycode == KEY_K:
			_try_counter(AttackType.B)
		elif event.keycode == KEY_J:
			_player_attack()
		elif event.keycode == KEY_R:
			_load_tuning()
			_apply_camera()
			_update_info_label()


func _player_attack() -> void:
	# Guard FIRST, before the assignment: otherwise mashing J would refresh the lockout
	# forever and you could never counter again.
	if player_recovery_left > 0.0:
		return   # still recovering from your own swing: the input is eaten
	# Attacking always costs defense, hit or whiff: SPACE/K/J are all dead until this drains.
	player_recovery_left = player_attack_recovery
	if state == State.STRIKE:
		return   # the strike is already committed and moving: your swing whiffs
	if state == State.WINDUP and vengeful_cycle:
		return   # you provoked this one: you must counter it, not cancel it
	_hit_enemy()


func _damage_enemy(amount: int, enrage: bool) -> void:
	# One damage path, two verbs. `enrage` is a property of the SOURCE, not of taking damage:
	# swinging arms Vengeful, countering does not. That asymmetry IS the design rule
	# ("countering is safe"), so it has to live at the call site, not in here.
	if enemy_hp_left <= 0:
		return   # already down, holding the FIGHT WON banner: don't re-trigger it
	enemy_hp_left = maxi(0, enemy_hp_left - amount)   # amount 0 is legal: a verb that deals none
	if enemy_hp_left <= 0:
		_win_fight()
		return
	if not enrage:
		return
	# Vengeful: deterministic, every landed swing. No randomness, no pattern reading.
	vengeful_left = vengeful_duration
	if state != State.VENGEFUL:
		_enter_vengeful()
	# else: refresh the rage window but leave the pose running, so repeat hits cannot
	# restart it and hold the enemy in VENGEFUL forever. It escapes on the first hit's clock.


func _hit_enemy() -> void:
	if enemy_hp_left <= 0:
		return   # already down: no flinch either
	hit_flinch = HIT_FLINCH_TIME   # J only; a counter has its own stagger pose to read
	_damage_enemy(attack_damage, true)


func _try_counter(pressed_for: int) -> void:
	if player_recovery_left > 0.0:
		return   # still recovering from your own swing: no counter, and the attempt is NOT spent
	if counter_spent:
		return
	if state == State.WINDUP:
		counter_spent = true
		# window = [eff_telegraph - w, eff_telegraph] of windup-elapsed time. Vengeful shortens
		# eff_telegraph, so the window opens later in wall-clock but keeps its size.
		var w: float = minf(counter_window, eff_telegraph)   # clamp: at most the whole windup
		if pressed_for == attack and state_time >= eff_telegraph - w:
			_win()
		# else: wrong attack OR too early -> attempt spent, the strike commits and lands -> LOSE
	elif state == State.STRIKE:
		counter_spent = true   # too late; the strike is already committed
	# IDLE / RECOVERY / VENGEFUL presses are ignored: nothing has telegraphed yet this cycle.


# ---------- state machine ----------
func _process(delta: float) -> void:
	state_time += delta
	player_recovery_left = maxf(0.0, player_recovery_left - delta)
	vengeful_left = maxf(0.0, vengeful_left - delta)   # runs in every state, so it can expire while idling
	if flash > 0.0:
		flash = max(0.0, flash - delta * 2.5)
		flash_rect.color = Color(0.6, 1.0, 0.7, flash * 0.55)

	match state:
		State.IDLE:
			if state_time >= idle_gap:
				_enter_windup()
		State.WINDUP:
			var p: float = clamp(state_time / eff_telegraph, 0.0, 1.0)
			var lean := windup_lean_amount
			# Pose progress, separate from timing progress. A retaliation is short AND, on a
			# plain ramp, only about half-formed when the counter window opens: less pose and
			# less time at once. Front-load the pose so it is fully formed the moment you can
			# press. Normal cycles keep pose_p == p exactly, and pose_p still reaches 1.0 at
			# the commit, so the STRIKE branch's start pose matches and nothing pops.
			var pose_p: float = p
			if vengeful_cycle:
				# clampf, not minf: a negative counter_window (degenerate, but nothing floors it)
				# would push open_at past eff_telegraph and leave the pose short at the commit.
				var open_at: float = eff_telegraph - clampf(counter_window, 0.0, eff_telegraph)
				if open_at > 0.0:
					pose_p = clamp(state_time / open_at, 0.0, 1.0)
				# open_at <= 0.0 means the window covers the whole wind-up: nothing to
				# front-load onto, so the pose keeps the plain ramp.
			if attack == AttackType.A:
				# A: rear back and tilt away (top tips back), coiling for a lunge.
				enemy_root.scale = Vector3.ONE
				enemy_root.rotation.x = lerp(0.0, WINDUP_LEAN * lean, pose_p)
				enemy_root.position = ENEMY_BASE + Vector3(0.0, 0.0, -WINDUP_STEP_BACK * lean * pose_p)
			else:
				# B: crouch low in place -> squash down, tip forward, widen (feet stay planted at y=0).
				enemy_root.position = ENEMY_BASE
				enemy_root.rotation.x = lerp(0.0, CROUCH_TIP_FWD * lean, pose_p)
				var sy := maxf(0.15, 1.0 - CROUCH_SQUASH * lean * pose_p)
				enemy_root.scale = Vector3(1.0 + CROUCH_WIDEN * lean * pose_p, sy, 1.0 + CROUCH_WIDEN * lean * pose_p)
			enemy_mat.albedo_color = COLOR_ENEMY.lerp(COLOR_WARN, p * windup_color_amount)
			if state_time >= eff_telegraph:
				_enter_strike()
		State.STRIKE:
			var q: float = ease(clamp(state_time / STRIKE_DURATION, 0.0, 1.0), 0.35)
			var lean := windup_lean_amount
			if attack == AttackType.A:
				enemy_root.rotation.x = lerp(WINDUP_LEAN * lean, STRIKE_LEAN, q)
				enemy_root.position = Vector3(0.0, 0.0, lerp(ENEMY_BASE.z - WINDUP_STEP_BACK * lean, LUNGE_Z, q))
				enemy_root.scale = Vector3.ONE
			else:
				# spring up out of the crouch while lunging forward from ENEMY_BASE.
				enemy_root.rotation.x = lerp(CROUCH_TIP_FWD * lean, STRIKE_LEAN, q)
				enemy_root.position = Vector3(0.0, 0.0, lerp(ENEMY_BASE.z, LUNGE_Z, q))
				var sy0 := maxf(0.15, 1.0 - CROUCH_SQUASH * lean)
				var wx := 1.0 + CROUCH_WIDEN * lean
				enemy_root.scale = Vector3(lerp(wx, 1.0, q), lerp(sy0, 1.0, q), lerp(wx, 1.0, q))
			enemy_mat.albedo_color = COLOR_STRIKE
			if state_time >= STRIKE_DURATION:
				_lose()
		State.RECOVERY:
			var r: float = clamp(state_time / RECOVERY_TIME, 0.0, 1.0)
			enemy_root.position = rec_start_pos.lerp(ENEMY_BASE, r)
			enemy_root.rotation.x = lerp(rec_start_rot, 0.0, r)
			enemy_root.scale = rec_start_scale.lerp(Vector3.ONE, r)
			if state_time >= RECOVERY_TIME:
				_enter_idle()
		State.VENGEFUL:
			# rise tall + tremor. Deliberately unlike A (rears back, tips away) and B (crouches
			# low): straight up, no rotation, so it cannot be mistaken for either wind-up.
			var d: float = minf(VENGE_POSE_TIME, vengeful_duration)
			var e: float = clampf(minf(state_time / VENGE_RAMP_IN, (d - state_time) / VENGE_RAMP_OUT), 0.0, 1.0)
			var tall := Vector3(1.0 - 0.10 * e, 1.0 + VENGE_STRETCH * e, 1.0 - 0.10 * e)
			var shake := ENEMY_BASE + Vector3(sin(state_time * TAU * VENGE_SHAKE_HZ) * VENGE_SHAKE_AMP * e, 0.0, 0.0)
			# `back` fades the interrupted pose out over the ramp-IN only, so the ramp-OUT
			# still lands on baseline (tall/shake both decay to ONE/ENEMY_BASE as e -> 0).
			var back: float = clampf(1.0 - state_time / VENGE_RAMP_IN, 0.0, 1.0)
			enemy_root.scale = tall.lerp(rec_start_scale, back)
			enemy_root.position = shake.lerp(rec_start_pos, back)
			enemy_root.rotation.x = lerp(0.0, rec_start_rot, back)
			if state_time >= d:
				# Straight into the wind-up, no idle gap: it rears up and comes back at you.
				# Returning to IDLE made attacking free: IDLE_MIN alone outlasts the player's
				# recovery, so under sustained attack the enemy never got to telegraph once.
				_enter_windup()   # vengeful_left still has time on it, so this one telegraphs short

	# knock-back from a landed player hit, drawn over whatever the state just posed.
	# absolute set (not -=) so it cannot accumulate in IDLE, where nothing else writes position.
	if hit_flinch > 0.0:
		hit_flinch = maxf(0.0, hit_flinch - delta)
		enemy_root.position.z = ENEMY_BASE.z - HIT_KNOCK * (hit_flinch / HIT_FLINCH_TIME)
	_update_info_label()   # ponytail: one format string per frame keeps the HP/state readout live


func _enter_idle() -> void:
	state = State.IDLE
	state_time = 0.0
	idle_gap = rng.randf_range(IDLE_MIN, IDLE_MAX)
	if enemy_hp_left <= 0:
		_reset_fight()   # FIGHT WON held through recovery; refill so the human can keep testing
	result_text = "watching"
	enemy_mat.albedo_color = COLOR_ENEMY
	enemy_root.position = ENEMY_BASE
	enemy_root.rotation.x = 0.0
	enemy_root.scale = Vector3.ONE
	_update_result_label()


func _enter_vengeful() -> void:
	# A hit during a wind-up CANCELS that attack: the cue stops and no strike commits this cycle.
	# From IDLE / RECOVERY this just starts the pose. Same call either way.
	windup_player.stop()
	state = State.VENGEFUL
	state_time = 0.0
	# blend out of whatever pose the hit interrupted (a mid-recovery stagger is far from
	# baseline) instead of snapping. Reuses the recovery capture vars; the two never overlap.
	rec_start_pos = enemy_root.position
	rec_start_rot = enemy_root.rotation.x
	rec_start_scale = enemy_root.scale
	enemy_mat.albedo_color = COLOR_ENEMY   # drop any telegraph tint from the cancelled wind-up
	result_text = "watching"
	_update_result_label()


func _enter_windup() -> void:
	attack = AttackType.A if rng.randf() < 0.5 else AttackType.B
	# One attempt per WIND-UP, reset here rather than in _enter_idle, because a wind-up is
	# what a cycle is and there are now two ways in. Coming out of VENGEFUL the retaliation
	# would otherwise inherit the attempt spent on the wind-up the player just cancelled.
	counter_spent = false
	# Locked once, here: the telegraph this cycle uses cannot shift mid-wind-up even if the
	# rage window expires while the enemy is already coiling. telegraph_length stays the tuning value.
	# vengeful_cycle is locked on the same line of reasoning: J's whiff rule reads it at press
	# time, and testing vengeful_left there would flicker if the window expired mid-wind-up.
	vengeful_cycle = vengeful_left > 0.0
	eff_telegraph = telegraph_length
	if vengeful_cycle:
		eff_telegraph = telegraph_length * vengeful_telegraph_multiplier
	state = State.WINDUP
	state_time = 0.0
	if windup_player.stream != null:
		var base_len: float = windup_player.stream.get_length()
		if base_len > 0.0 and eff_telegraph > 0.0:
			windup_player.pitch_scale = base_len / eff_telegraph
		windup_player.play()


func _enter_strike() -> void:
	windup_player.stop()   # windup.wav is fixed ~1.1s; don't let it bleed into the strike/hit
	state = State.STRIKE
	state_time = 0.0


func _enter_recovery(text: String, reveal: bool = true) -> void:
	state = State.RECOVERY
	state_time = 0.0
	rec_start_pos = enemy_root.position
	rec_start_rot = enemy_root.rotation.x
	rec_start_scale = enemy_root.scale
	# reveal the ground-truth attack letter ONLY now (recovery); idle/windup stay "watching".
	# reveal=false for outcomes that are not a read on this cycle's attack (FIGHT WON).
	if reveal:
		result_text = "%s  (%s)" % [text, ("A" if attack == AttackType.A else "B")]
	else:
		result_text = text
	_update_result_label()


func _win() -> void:
	# Damage lands BEFORE any label or pose work: a counter that kills has to read as
	# FIGHT WON, not as the per-cycle WIN, and _win_fight owns the screen once it fires.
	# enrage = false: countering is the safe verb, it must never arm Vengeful.
	_damage_enemy(counter_damage, false)
	if enemy_hp_left <= 0:
		return   # killing blow: _win_fight already stopped the cue, flashed and set the label
	# Visual feedback only (no third audio cue): flash + label + staggered pose.
	windup_player.stop()   # counter succeeded mid-windup; cut the rising tone
	flash = 1.0
	enemy_mat.albedo_color = COLOR_STAGGER
	enemy_root.rotation.x = -0.9
	enemy_root.position = ENEMY_BASE + Vector3(0.0, 0.0, -0.6)
	_enter_recovery("WIN")


func _reset_fight() -> void:
	# Every path that restores HP goes through here, so the rage window can't survive a
	# reset and hand the player a shortened telegraph on the first cycle of a fresh fight.
	enemy_hp_left = enemy_hp
	vengeful_left = 0.0


func _win_fight() -> void:
	# terminal outcome, distinct from the per-cycle WIN: the last hit landed.
	# reuses the recovery timer as the hold, then _enter_idle refills enemy_hp_left.
	windup_player.stop()
	flash = 1.0
	enemy_mat.albedo_color = COLOR_STAGGER
	_enter_recovery("FIGHT WON", false)


func _lose() -> void:
	if hit_player.stream != null:
		hit_player.play()
	_reset_fight()   # dying resets the fight, so trading your life for a hit buys nothing
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
	enemy_hp = 3
	counter_damage = 1
	attack_damage = 1
	player_attack_recovery = 1.0
	vengeful_duration = 2.5
	vengeful_telegraph_multiplier = 0.6
	seed_value = 0
	_apply_seed()   # same rule on the missing/bad-file fallback path
	_reset_fight()   # R restarts the fight at full HP, same as it restarts the RNG
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
	telegraph_length = maxf(0.05, _num(data, "telegraph_length", telegraph_length))   # never 0: it divides
	counter_window = _num(data, "counter_window", counter_window)
	camera_distance = _num(data, "camera_distance", camera_distance)
	windup_color_amount = clampf(_num(data, "windup_color_amount", windup_color_amount), 0.0, 1.0)
	windup_lean_amount = maxf(0.0, _num(data, "windup_lean_amount", windup_lean_amount))
	enemy_hp = maxi(1, int(_num(data, "enemy_hp", float(enemy_hp))))
	# floored at 0, not 1: "this verb deals no damage" is a legitimate experiment.
	counter_damage = maxi(0, int(_num(data, "counter_damage", float(counter_damage))))
	attack_damage = maxi(0, int(_num(data, "attack_damage", float(attack_damage))))
	player_attack_recovery = maxf(0.0, _num(data, "player_attack_recovery", player_attack_recovery))
	vengeful_duration = maxf(0.0, _num(data, "vengeful_duration", vengeful_duration))
	# never 0: it divides pitch_scale and anchors the counter window.
	vengeful_telegraph_multiplier = clampf(_num(data, "vengeful_telegraph_multiplier", vengeful_telegraph_multiplier), 0.05, 1.0)
	seed_value = int(_num(data, "seed", float(seed_value)))
	_apply_seed()
	_reset_fight()


func _apply_seed() -> void:
	# "seed" is an optional override. Absent or <= 0 = a different A/B order every run.
	if seed_value <= 0:
		rng.randomize()
	else:
		rng.seed = seed_value


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
	# text now carries a "  (A/B)" suffix in recovery, so match on the prefix.
	if result_text.begins_with("WIN") or result_text.begins_with("FIGHT WON"):
		result_label.modulate = Color(0.4, 1.0, 0.5)
	elif result_text.begins_with("LOSE"):
		result_label.modulate = Color(1.0, 0.4, 0.35)
	else:
		result_label.modulate = Color(0.85, 0.85, 0.9)


func _update_info_label() -> void:
	var w: float = minf(counter_window, telegraph_length)
	var opens: float = telegraph_length - w
	# same math on the vengeful telegraph, printed side by side: the window SIZE should match.
	var vt: float = telegraph_length * vengeful_telegraph_multiplier
	var vw: float = minf(counter_window, vt)
	var seed_txt: String = "random" if seed_value <= 0 else str(seed_value)
	var venge_txt: String = (">>> VENGEFUL  %.1f s left <<<" % vengeful_left) if vengeful_left > 0.0 else ""
	info_label.text = "telegraph_length: %.2f s\ncounter_window:  %.2f s\ncamera_distance: %.1f\nwindup_color_amount: %.2f\nwindup_lean_amount:  %.2f\nenemy_hp: %d   (left: %d)\ncounter_damage: %d   attack_damage: %d\nplayer_attack_recovery: %.2f s\nvengeful_duration: %.2f s\nvengeful_telegraph_multiplier: %.2f\nseed: %s\ncounter window: %.2f-%.2f s of windup   (vengeful: %.2f-%.2f)\n%s\nSPACE = counter A   K = counter B   J = attack   R = reload" % [telegraph_length, counter_window, camera_distance, windup_color_amount, windup_lean_amount, enemy_hp, enemy_hp_left, counter_damage, attack_damage, player_attack_recovery, vengeful_duration, vengeful_telegraph_multiplier, seed_txt, opens, telegraph_length, vt - vw, vt, venge_txt]
