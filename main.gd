extends Node3D
# Descent - Phase 4 decision prototype.
# One enemy loops IDLE -> WINDUP -> STRIKE -> RECOVERY -> IDLE, carrying exactly ONE of
# two constraints, picked by `enemy_constraint`. Never both: an enemy that learns AND
# retaliates is two experiments running at once and measures neither.
# VENGEFUL: every hit you land makes it rise tall, tremble, and telegraph its next
# attack shorter (same counter window, less time to read it).
# ADAPTIVE: it counts WHICH PART OF THE CYCLE you swing in and learns the part you keep
# repeating. Swing there again and the swing passes through for nothing. Never swinging
# is a habit too, and it answers that one by compressing the guard beat.
# Methodical: the A/B order is a fixed repeating sequence, not a coin flip, and every
# sequence attack is preceded by a visible guard beat (the enemy squares up in IDLE).
# The retaliation is OFF-sequence - a coin flip out of the vengeful pose with no guard
# beat - so swinging costs you the read as well as your defense.
# SPACE counters attack A, K counters attack B, both only inside the TAIL of the
# windup. J attacks, and costs you your counter while the swing recovers. J cancels a
# normal wind-up under either constraint, but WHIFFS on a vengeful retaliation: the one
# you provoked has to be countered.
# R re-reads tuning.json live, and clears everything Adaptive has learned.
# Whole scene is built in _ready() so there is no editor-authored .tscn to import.

# ---- tuning (hot-reloadable from res://tuning.json) ----
var telegraph_length: float = 1.2
var counter_window: float = 0.35
var camera_distance: float = 8.0
var windup_color_amount: float = 1.0
var windup_lean_amount: float = 1.0
var enemy_hp: int = 9              # HP the enemy starts each fight with
var counter_damage: int = 1        # HP a successful counter takes off (countering never enrages)
var attack_damage: int = 1         # HP one landed J swing takes off
var player_attack_recovery: float = 1.0    # seconds your own swing leaves you unable to counter or swing again
var vengeful_duration: float = 2.5         # how long a hit keeps the enemy vengeful
var vengeful_telegraph_multiplier: float = 0.6   # telegraph scale while vengeful; window size is untouched
var methodical_reset_time: float = 0.55    # length of the guard beat that precedes every sequence attack
var methodical_resume: String = "next"     # where the sequence picks up after a retaliation: "next" | "restart"
var enemy_constraint: String = "adaptive"  # which constraint this enemy carries: "adaptive" | "vengeful". Never both.
var adaptive_threshold: int = 3            # weight one signature must reach before it adapts; = that many consecutive cycles out of a cold bucket, see _close_cycle
var adaptive_capacity: int = 2             # how many adaptations can be live at once; a new one evicts the oldest
var adaptive_patience_guard_multiplier: float = 0.5   # guard-beat length while PATIENCE is adapted; 1.0 = no punishment
const SEQUENCE_DEFAULT := "AABAB"          # parsed when the key is missing, or when it parses to nothing
var sequence: Array[int] = []      # methodical_sequence as AttackType values; NEVER empty at runtime
var seed_value: int = 0            # RNG seed for the A/B order + idle jitter; <= 0 = random per run

# ---- hardcoded knobs (deliberately NOT in tuning.json) ----
const IDLE_MIN := 0.0            # idle-gap jitter ON TOP of the guard beat (seconds)
const IDLE_MAX := 0.20           # small: the reset is a beat, not a wait, but never metronomic
const GUARD_ROLL := 0.12         # guard beat: peak roll in radians of the square-up
const GUARD_DAMP_HZ := 2.2       # guard beat: wobble rate. It and the exp(-3t) envelope both read BEAT PROGRESS in units of an uncompressed beat, not wall clock
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
# Adaptive. The decay is per CYCLE, applied to every bucket the player did not use, so a
# habit of period p settles at 1 / (1 - ADAPT_DECAY^(p-1)): repeating every cycle grows
# without bound, strict alternation tops out at 1.67, a three-way rotation at 1.19. 0.4 and
# not 0.5 on purpose - at 0.5 the alternation ceiling is exactly 2.0, which a threshold of 2
# reaches by float accumulation after ~53 cycles. At 0.4 the knob is honest across its range.
const ADAPT_DECAY := 0.4
const ADAPT_LIFT := 0.35         # stance shift: how far the enemy rises OFF THE FLOOR (position.y)
const ADAPT_POSE_TIME := 0.45    # how long the lift is held before it hands back to IDLE
const ADAPT_RAMP := 0.12         # in and out on one value, so the settle reads as an exit
const COLOR_ENEMY := Color(0.80, 0.15, 0.12)   # red idle
const COLOR_WARN := Color(1.00, 0.82, 0.05)    # warning yellow (telegraph)
const COLOR_STRIKE := Color(0.95, 0.10, 0.05)  # aggressive red on commit
const COLOR_PLAYER := Color(0.15, 0.35, 0.85)  # blue
const COLOR_STAGGER := Color(0.32, 0.30, 0.33) # dimmed on a successful counter

enum State { IDLE, WINDUP, STRIKE, RECOVERY, VENGEFUL, ADAPT }
enum AttackType { A, B }
# Adaptive's four signatures, in fixed order, read from the enemy's state at the moment of an
# accepted J press. A signature is the player's only DISCRETIONARY choice in this build:
# whether to swing, and when. The counter is dictated by the enemy's attack, so it carries no
# repetition to punish. STRIKE, RECOVERY and ADAPT all collapse into AFTER because a press
# belonging to no bucket would silently suppress PATIENCE. STRIKE and RECOVERY really are the
# tail of the cycle that just telegraphed. ADAPT is NOT: it is entered after _close_cycle()
# has already run, so a press during the lift is attributed to the FOLLOWING cycle. AFTER is
# still its bucket, because a press has to have one and this is the nearest neighbour.
# PATIENCE - no accepted swing anywhere in the cycle - is a signature too, and it is the whole
# reason pure defense is no longer free.
enum Signature { GUARD, WINDUP, AFTER, PATIENCE }
var state: int = State.IDLE
var attack: int                      # which attack this cycle telegraphs (A rears back, B crouches)
var seq_index: int = 0               # position in `sequence`; advances when a SEQUENCE wind-up begins
var state_time: float = 0.0
var idle_gap: float = 1.0
var eff_guard_time: float = 0.55    # this cycle's guard beat, locked at _enter_idle like eff_telegraph
var guard_beat_factor: float = 1.0  # 1.0 / this cycle's guard scale, locked with eff_guard_time; see the IDLE branch
var counter_spent: bool = false     # one counter attempt per cycle
var enemy_hp_left: int = 9          # refilled by _reset_fight (reload, FIGHT WON, or your death)
var fight_over: bool = false        # terminal result hold; LOSE already refills HP, so HP alone cannot gate input
var player_recovery_left: float = 0.0   # your own swing's recovery; blocks SPACE/K while > 0
var hit_flinch: float = 0.0         # knock-back timer for a landed player hit
var vengeful_left: float = 0.0      # rage window: an attack starting while > 0 telegraphs short
var eff_telegraph: float = 1.2      # this cycle's telegraph, locked at _enter_windup so it cannot shift
var vengeful_cycle: bool = false    # is THIS wind-up a retaliation? locked alongside eff_telegraph
# Adaptive's whole memory, one entry per Signature. Cleared by _load_tuning (R), and
# DELIBERATELY not by _reset_fight: see _clear_adaptation.
var adapt_weight: Array[float] = [0.0, 0.0, 0.0, 0.0]   # recency-weighted count of cycles per signature
var adapt_seen: Array[bool] = [false, false, false, false]   # THIS cycle's seen-set; a press only sets a flag
var adapt_active: Array[int] = []   # adapted signatures, oldest FIRST (ties inside one cycle break in enum order, not press order), so pop_front evicts the oldest
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
	_selftest_adaptive()   # pure arithmetic on locals, so it can run before anything exists
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
	if fight_over or player_recovery_left > 0.0:
		return   # terminal hold or your own recovery: the input is not a swing
	# Attacking always costs defense, hit or whiff: SPACE/K/J are all dead until this drains.
	player_recovery_left = player_attack_recovery
	# Adaptive records the PRESS, not its outcome, so this sits above both whiff returns below:
	# a swing that hits nothing was still a choice about when to swing. Only accepted presses
	# get here, so an input eaten by the lockout above records nothing and is not an action.
	if enemy_constraint == "adaptive":
		var sig: int = _press_signature()
		_mark_seen(adapt_seen, sig)
		if adapt_active.has(sig):
			# It has learned this timing. The swing passes through: no damage, no flinch, no
			# cancel, and the lockout above is still spent.
			# The label is only written where nothing else owns it. RECOVERY and ADAPT are
			# both still holding the A/B reveal _enter_recovery printed, and that letter is the
			# player's only ground truth on the sequence, so a whiff there stays silent instead
			# of erasing it. Nothing is lost: the discrimination holds on the other two
			# channels, since a landed recovery hit gives a flinch and an HP tick while a whiff
			# gives neither. A landed recovery hit already leaves the label alone for exactly
			# the same reason (_damage_enemy returns without touching it), so this is also what
			# makes the two consistent.
			if state != State.RECOVERY and state != State.ADAPT:
				result_text = "WHIFF"
				_update_result_label()
			return
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
	if enemy_constraint == "adaptive":
		# Adaptive keeps Vengeful's cancel and drops its retaliation. The cancel was never a
		# separate path - it was a side effect of switching state in _enter_vengeful - so with
		# that branch gone it has to be done here, or a landed J would leave the wind-up
		# running to the strike with state_time untouched.
		# RECOVERY, not IDLE, for two reasons. It already lerps the captured coil back to
		# baseline over RECOVERY_TIME, so "it uncoils" needs no new animation. And RECOVERY
		# carries the one cycle boundary: routing to IDLE would skip the boundary for exactly
		# the cycle the player just acted in, losing the swing that caused the cancel, so the
		# WINDUP bucket could never adapt.
		if state == State.WINDUP:
			windup_player.stop()   # same reason as _enter_vengeful: the rising tone must not outlive the attack
			# and the same reason once more: a cancelled wind-up must not hold its telegraph
			# tint through the whole recovery, which would read as "still coiling".
			enemy_mat.albedo_color = COLOR_ENEMY
			# reveal = false: printing the letter of a wind-up that never landed would hand back
			# the sequence step the swing was supposed to cost.
			_enter_recovery("HIT", false)
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
	if fight_over or player_recovery_left > 0.0:
		return   # no counter during a terminal hold or your own recovery; attempt is NOT spent
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
			# Guard beat: square up on the ROLL axis and settle level, a damped wobble over
			# methodical_reset_time. rotation.z is used by nothing else (A and B drive
			# rotation.x, Vengeful an x tremor), so it reads as its own event - the enemy
			# planting its feet - and can never be confused for a wind-up.
			# eff_guard_time, not methodical_reset_time: an adapted PATIENCE compresses the beat,
			# and the pose has to compress with the gap or the two come apart.
			if state_time < eff_guard_time:
				# Beat PROGRESS, not wall clock. Both the envelope and the cosine were written in
				# absolute seconds, so on a compressed beat they TRUNCATED instead of compressing:
				# at the shipped 0.5 multiplier the wobble got 0.60 of a cycle and was cut at
				# -2.4 degrees before snapping to level, which is not a square-up-and-settle.
				# Scaling the clock by the compression factor keeps the shape and the near-zero
				# landing residual the same at any beat length. The factor is LOCKED next to
				# eff_guard_time rather than divided out here, and for the same reason the beat
				# itself is locked: computing it per frame would read a live methodical_reset_time
				# against a locked eff_guard_time, so an R press mid-beat would hold the window
				# fixed while the shape inside it jumped. It also keeps a divide off the per-frame
				# path. _guard_scale() returns literal 1.0 whenever nothing is compressed, so the
				# locked factor is exactly 1.0 and this stays bit-for-bit the old expression on an
				# unadapted beat and under "vengeful".
				var bt: float = state_time * guard_beat_factor
				enemy_root.rotation.z = GUARD_ROLL * exp(-3.0 * bt) * cos(bt * TAU * GUARD_DAMP_HZ)
			else:
				enemy_root.rotation.z = 0.0   # exactly level, not a residual fraction
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
				enemy_root.rotation.z = 0.0   # the guard beat's roll must not leak into the coil
				enemy_root.scale = Vector3.ONE
				enemy_root.rotation.x = lerp(0.0, WINDUP_LEAN * lean, pose_p)
				enemy_root.position = ENEMY_BASE + Vector3(0.0, 0.0, -WINDUP_STEP_BACK * lean * pose_p)
			else:
				# B: crouch low in place -> squash down, tip forward, widen (feet stay planted at y=0).
				enemy_root.rotation.z = 0.0   # the guard beat's roll must not leak into the coil
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
				# The cycle boundary. What the code guarantees is once per RECOVERY, on every
				# path: RECOVERY has this one exit, and a loss, a win, FIGHT WON, a death, the
				# cancelled wind-up and a mid-recovery R press all arrive through it exactly
				# once. Under "adaptive" the VENGEFUL -> WINDUP edge and the _enter_vengeful
				# call are both dead, so nothing reaches a wind-up without passing here first.
				# Not once per TELEGRAPH: two cycles contain no telegraph at all, a killing J
				# during the guard beat (IDLE -> _win_fight -> _enter_recovery) and a killing J
				# during the lift (ADAPT -> the same), and each still takes a full weight step.
				# Harmless, and neither can hand PATIENCE a free step, because both of them
				# need a J press that has already marked a bucket.
				# Inside _enter_idle instead it would also fire once at startup from _ready,
				# before any cycle existed.
				var formed: bool = false
				if enemy_constraint == "adaptive":
					formed = _close_cycle()
				# The completed cycle (including a killing J) still learns once. A terminal
				# hold cannot schedule a stance on the defeated actor; the next fight inherits
				# the learned response under the existing R-only memory reset rule.
				if formed and not fight_over:
					_enter_adapt()   # the stance shift stands in for this cycle's idle entry and hands back to it
				else:
					_enter_idle()
		State.ADAPT:
			# It just learned one of your habits. The pose is a LIFT on position.y: the enemy
			# rises off the floor and settles, feet leaving the ground. Every other axis is
			# spoken for - A rears back and B tips forward on rotation.x, the guard beat rolls
			# on rotation.z, Vengeful stretches scale.y and tremors on position.x - so the lift
			# is the only motion that cannot be misread as one of them.
			# Not rotation.y, which only looks free: CapsuleMesh is a solid of revolution about
			# Y, so yaw is a visual no-op on the GLB-import fallback, and nothing in this file
			# ever zeroes rotation.y, so any residual would be permanent and would change how
			# A's and B's poses project at the fixed 3/4 camera.
			var a: float = clampf(minf(state_time / ADAPT_RAMP, (ADAPT_POSE_TIME - state_time) / ADAPT_RAMP), 0.0, 1.0)
			enemy_root.position = ENEMY_BASE + Vector3(0.0, ADAPT_LIFT * a, 0.0)
			if state_time >= ADAPT_POSE_TIME:
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
				# Straight into the wind-up, no idle gap and so NO GUARD BEAT: it rears up and
				# comes back at you. That absence is the visible handoff - a sequence attack
				# is always preceded by the square-up, a retaliation never is. Routing this
				# through IDLE would both add the beat and, back when the gap was 0.6-1.6 s,
				# outlast the player's recovery so the enemy never got to telegraph at all.
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
	fight_over = false
	# The guard beat IS the idle gap, so a wind-up can never start before the square-up
	# finishes. The jitter on top keeps the rhythm off a metronome without hiding the beat.
	# Both are locked here for the same reason eff_telegraph is locked at _enter_windup: an R
	# press mid-beat must not move the finish line the IDLE branch is already animating toward.
	# The jitter is scaled by the SAME factor as the beat. Compressing only one of the two is
	# the trap: shortening the pose alone leaves dead air where the beat was, and shortening
	# the gap alone leaves an unscaled IDLE_MAX at 73% of a 0.28 s beat, one-sided at that: 0
	# to +0.20 and never minus, because IDLE_MIN is 0. Both together raise the tempo,
	# which is what "the safe opening compresses" has to mean for a player who never swings.
	var gs: float = _guard_scale()
	eff_guard_time = methodical_reset_time * gs
	guard_beat_factor = 1.0 / gs   # the wobble's clock scale, locked here for the same reason
	idle_gap = eff_guard_time + rng.randf_range(IDLE_MIN, IDLE_MAX) * gs
	if enemy_hp_left <= 0:
		_reset_fight()   # FIGHT WON held through recovery; refill so the human can keep testing
	result_text = "watching"
	enemy_mat.albedo_color = COLOR_ENEMY
	enemy_root.position = ENEMY_BASE
	enemy_root.rotation.x = 0.0
	enemy_root.rotation.z = 0.0
	enemy_root.scale = Vector3.ONE
	_update_result_label()


func _enter_adapt() -> void:
	# Entered at the cycle boundary INSTEAD of _enter_idle, on any cycle where an adaptation
	# formed during a living fight, and it calls _enter_idle when the pose is done, so the guard beat still
	# precedes the next attack. Pose only, no color: the lift has to carry the read, and a
	# fourth tint would compete with the telegraph.
	state = State.ADAPT
	state_time = 0.0
	enemy_mat.albedo_color = COLOR_ENEMY
	# No zeroing here. RECOVERY is the only way in and its lerp has just landed rotation.x and
	# scale exactly on baseline; _enter_recovery already dropped rotation.z. The ADAPT branch
	# then writes the whole position absolutely every frame. And on the way out, ENEMY_BASE.y
	# is 0 and every existing path re-zeroes position.y anyway (_enter_idle, both _enter_windup
	# branches, RECOVERY's lerp), so a kill landed during the lift unwinds it for free.


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
	enemy_root.rotation.z = 0.0   # J landed during the guard beat: drop the roll, do not pose with it
	enemy_mat.albedo_color = COLOR_ENEMY   # drop any telegraph tint from the cancelled wind-up
	result_text = "watching"
	_update_result_label()


func _enter_windup() -> void:
	# Locked FIRST, before the attack pick, because the pick now branches on it. It is a pure
	# read of vengeful_left, so hoisting it above the pick cannot change what it holds. It is
	# locked rather than re-tested because J's whiff rule reads it at press time, and testing
	# vengeful_left there would flicker if the rage window expired mid-wind-up.
	vengeful_cycle = vengeful_left > 0.0
	# Locked on the same reasoning: the telegraph this cycle uses cannot shift mid-wind-up even
	# if the rage window expires while the enemy is already coiling. telegraph_length stays the
	# tuning value.
	eff_telegraph = telegraph_length
	if vengeful_cycle:
		eff_telegraph = telegraph_length * vengeful_telegraph_multiplier
		# The retaliation is OFF-sequence: a fresh coin flip, and it never advances seq_index.
		# You provoked this one, so it is not a step of the pattern you were tracking, and it
		# must not be predictable from that pattern either.
		attack = AttackType.A if rng.randf() < 0.5 else AttackType.B
		if methodical_resume == "restart":
			# The harsh arbitration: enraging it throws away all positional knowledge, so the
			# sequence resumes from the top instead of from where you interrupted it.
			seq_index = 0
	else:
		# Methodical: the order is fixed and it is the whole read. seq_index advances the
		# moment a sequence wind-up BEGINS and is never rolled back, so cancelling this one
		# with J still burns the step - swinging costs you a step of the pattern as well as
		# your defense. `sequence` is never empty (see _load_tuning), so both the index and
		# the modulo are safe for any sequence length.
		attack = sequence[seq_index]
		seq_index = (seq_index + 1) % sequence.size()
	# One attempt per WIND-UP, reset here rather than in _enter_idle, because a wind-up is
	# what a cycle is and there are now two ways in. Coming out of VENGEFUL the retaliation
	# would otherwise inherit the attempt spent on the wind-up the player just cancelled.
	counter_spent = false
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
	enemy_root.rotation.z = 0.0   # FIGHT WON can fire from the guard beat; do not hold the roll
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
	# Adaptive's weights and active list are DELIBERATELY not touched: learning survives a
	# death and a FIGHT WON. At enemy_hp 9 and threshold 3 the counter-plus-recovery-poke line
	# takes two HP a cycle and has the enemy at 3 HP when AFTER adapts, so the adaptation
	# bites inside the fight that taught it. Persistence still matters: clearing it here
	# would make dying buy a clean slate. Same rule the sequence already follows: dying does
	# not re-sync what you are being read on.
	enemy_hp_left = enemy_hp
	vengeful_left = 0.0
	fight_over = false


func _win_fight() -> void:
	# terminal outcome, distinct from the per-cycle WIN: the last hit landed.
	# reuses the recovery timer as the hold, then _enter_idle refills enemy_hp_left.
	fight_over = true
	windup_player.stop()
	flash = 1.0
	enemy_mat.albedo_color = COLOR_STAGGER
	_enter_recovery("FIGHT WON", false)


func _lose() -> void:
	if hit_player.stream != null:
		hit_player.play()
	_reset_fight()   # dying resets the fight, so trading your life for a hit buys nothing
	fight_over = true
	_enter_recovery("LOSE")


# ---------- adaptive (the enemy reads your habits; only live under "adaptive") ----------
func _press_signature() -> int:
	# Which bucket an accepted J press falls in, read off the enemy's state at press time.
	# A press during STRIKE has never been able to deal damage (it returns before _hit_enemy),
	# so AFTER is in practice the recovery bucket.
	if state == State.IDLE:
		return Signature.GUARD
	if state == State.WINDUP:
		return Signature.WINDUP
	return Signature.AFTER   # STRIKE and RECOVERY are this cycle's tail; ADAPT is past the boundary, so it lands in the next one (see the enum)


func _guard_scale() -> float:
	# The one effect PATIENCE has. Countering costs nothing up front, so the only price that
	# can be put on never swinging is tempo: the safe opening between attacks gets shorter.
	if enemy_constraint == "adaptive" and adapt_active.has(Signature.PATIENCE):
		return adaptive_patience_guard_multiplier
	return 1.0


func _close_cycle() -> bool:
	# Called once per cycle from the RECOVERY exit. Returns true if an adaptation formed, which
	# earns the stance shift unless the fight has ended.
	# Counting is a per-cycle SEEN-SET, not a per-press counter. Increment per press with decay
	# per cycle would run the count and the decay on different clocks while the property is
	# stated in cycles: RECOVERY_TIME 1.1 s is longer than the 1.0 s lockout, so two AFTER
	# presses fit in one cycle, and under a per-press increment that bucket would reach 4 in
	# two cycles and trip a threshold of 3 early. The seen-set makes a cycle worth at most +1
	# to any one bucket, which is what "recency-weighted count of a habit" has to mean.
	_derive_patience(adapt_seen)
	_step_weights(adapt_weight, adapt_seen)
	for b in range(adapt_seen.size()):
		adapt_seen[b] = false   # the set is per cycle: clear it the moment it has been spent
	var formed: bool = false
	for b in range(adapt_weight.size()):
		# >=, and the test is on the WEIGHT, not on a fresh run of cycles. So a threshold of N
		# means N consecutive cycles out of a COLD bucket, and fewer out of one still warm from
		# a recent partial habit: k consecutive cycles cross once k >= N - 0.4 * w_prev. A duty
		# cycle above one-in-p is therefore caught as well. "Swing twice, rest once" in GUARD
		# runs 1, 2, 0.8, 1.8, 2.8, 1.12, 2.12, 3.12 and adapts off TWO consecutive cycles at a
		# threshold of 3. That is wanted, it is still a habit. The 1 / (1 - 0.4^(p-1)) ceiling
		# describes STRICT period-p rotation only: it bounds the rotations and says nothing
		# about a fatter duty cycle.
		if adapt_weight[b] >= float(adaptive_threshold) and not adapt_active.has(b):
			adapt_active.append(b)   # PATIENCE takes a slot in the same list under the same rule
			formed = true
	_evict_over_capacity(adapt_weight, adapt_active, adaptive_capacity)
	return formed


func _mark_seen(seen: Array[bool], sig: int) -> void:
	# A flag, never a count: the arithmetic is at the cycle boundary. One line, but a function
	# so the self-test can call it twice on one bucket and prove the second press is worth
	# nothing. Turn this into an increment and that assert fails.
	seen[sig] = true


func _derive_patience(seen: Array[bool]) -> void:
	# PATIENCE is derived, never pressed: the cycle went by with no accepted swing in any of
	# the three press buckets. Takes its array as a parameter for the same reason _step_weights
	# does, so the self-test can exercise it without being able to write a live flag.
	seen[Signature.PATIENCE] = not (seen[Signature.GUARD] or seen[Signature.WINDUP] or seen[Signature.AFTER])


func _step_weights(weights: Array[float], seen: Array[bool]) -> void:
	# The entire learning rule: +1 for a signature used this cycle, decay for one that was not.
	# Takes its arrays as parameters so _selftest_adaptive can exercise it on locals and can
	# never write live weights.
	for b in range(weights.size()):
		if seen[b]:
			weights[b] += 1.0
		else:
			weights[b] *= ADAPT_DECAY


func _evict_over_capacity(weights: Array[float], active: Array[int], cap: int) -> void:
	# A new adaptation evicts the OLDEST, and zeroes that bucket's weight so it cannot
	# immediately re-cross on the next press there. An active adaptation never expires on its
	# own: decay alone does not flush it, only a newer one evicting it does. That asymmetry is
	# the whole reason varying your timing beats Adaptive while no single habit does.
	# A `while`, not an `if`: three buckets can cross in one cycle, since up to three presses
	# fit in a ~3 s cycle at a 1 s lockout.
	while active.size() > cap:
		var evicted: int = int(active.pop_front())   # pop_front returns Variant; cast, do not trust it
		weights[evicted] = 0.0


func _clear_adaptation() -> void:
	# R only. R re-reads adaptive_threshold, and a weight of 2.5 carried across a change from
	# 3 to 2 would form an adaptation out of nothing, with no press - the same class of bug the
	# stale-seq_index guard in _load_tuning already covers. R is also the only way to switch
	# enemy_constraint, and a live adaptation must not survive into a Vengeful fight.
	for b in range(adapt_weight.size()):
		adapt_weight[b] = 0.0
		adapt_seen[b] = false
	adapt_active.clear()


func _selftest_adaptive() -> void:
	# The one runnable check for the only non-trivial arithmetic here. Godot strips assert()
	# from release builds, so a shipped build just walks a few hundred loop iterations once at
	# startup and checks nothing. It runs on LOCAL arrays only: it must never be able to write a live
	# weight, which is why _step_weights and _evict_over_capacity take theirs as parameters.
	var s: Array[bool] = [false, false, false, false]
	# p = 1, the same signature every cycle: 1, 2, 3. Out of a COLD bucket a threshold of N
	# trips at exactly cycle N. A warm bucket crosses sooner, which is the bound written out in
	# _close_cycle.
	var w: Array[float] = [0.0, 0.0, 0.0, 0.0]
	for i in range(3):
		_mark_seen(s, Signature.GUARD)
		_step_weights(w, s)
		s[Signature.GUARD] = false
	assert(is_equal_approx(w[Signature.GUARD], 3.0), "3 consecutive cycles of one signature out of a cold bucket must land on exactly 3.0")
	assert(w[Signature.WINDUP] == 0.0, "a signature never used must stay at 0")

	# Two presses in one cycle in one bucket are worth exactly one. Both marks go through the
	# same helper _player_attack uses, so this is the row that fails if the mark ever becomes
	# an increment. Assigning the flag twice inline could not fail for any implementation.
	var w2: Array[float] = [0.0, 0.0, 0.0, 0.0]
	for i in range(3):
		_mark_seen(s, Signature.GUARD)
		_mark_seen(s, Signature.GUARD)   # a second accepted press, same cycle, same bucket
		_step_weights(w2, s)
		s[Signature.GUARD] = false
	assert(is_equal_approx(w2[Signature.GUARD], w[Signature.GUARD]), "a second press in one cycle must not count twice")

	# PATIENCE is derived from the other three, so it is the one flag no press ever sets.
	var ps: Array[bool] = [false, false, false, false]
	_derive_patience(ps)
	assert(ps[Signature.PATIENCE], "a cycle with no accepted swing anywhere must set PATIENCE")
	# Literal, not range(Signature.PATIENCE): that range goes vacuous and this row silently
	# stops checking anything if PATIENCE ever moves off the end of the enum.
	for pb: int in [Signature.GUARD, Signature.WINDUP, Signature.AFTER]:   # the three press buckets
		for c in range(ps.size()):
			ps[c] = false
		_mark_seen(ps, pb)
		_derive_patience(ps)
		assert(not ps[Signature.PATIENCE], "one accepted swing anywhere must clear PATIENCE")

	# p = 2, strict alternation: ceiling 1 / (1 - 0.4) = 1.67, so it never reaches a threshold
	# of 2, let alone the shipped 3. 40 cycles is far past convergence. Ends on WINDUP.
	var alt: Array[float] = [0.0, 0.0, 0.0, 0.0]
	for i in range(40):
		var b: int = Signature.GUARD if i % 2 == 0 else Signature.WINDUP
		s[b] = true
		_step_weights(alt, s)
		s[b] = false
	assert(alt[Signature.WINDUP] < 1.7, "alternation must stay bounded near its 1.67 ceiling")
	assert(alt[Signature.WINDUP] < 2.0 and alt[Signature.GUARD] < 2.0, "alternation must never reach a threshold of 2")

	# p = 3, a three-way rotation: ceiling 1 / (1 - 0.4^2) = 1.19, strictly under alternation.
	# More rotation must mean a lower ceiling, or "vary your timing" would not be the answer.
	var rot: Array[float] = [0.0, 0.0, 0.0, 0.0]
	for i in range(45):
		var b: int = i % 3   # GUARD, WINDUP, AFTER in enum order; ends on AFTER
		s[b] = true
		_step_weights(rot, s)
		s[b] = false
	assert(rot[Signature.AFTER] < 1.2, "a 3-way rotation must stay bounded near its 1.19 ceiling")
	assert(rot[Signature.AFTER] < alt[Signature.WINDUP], "more rotation must mean a lower ceiling")

	# Eviction: at capacity 2 a third adaptation pops the oldest and zeroes its weight.
	var ew: Array[float] = [3.0, 3.0, 3.0, 0.0]
	var ea: Array[int] = [Signature.GUARD, Signature.WINDUP, Signature.AFTER]
	_evict_over_capacity(ew, ea, 2)
	assert(ea.size() == 2 and ea[0] == Signature.WINDUP, "eviction must drop the oldest entry, not the newest")
	assert(ew[Signature.GUARD] == 0.0, "an evicted signature's weight must be zeroed")
	assert(ew[Signature.WINDUP] == 3.0, "eviction must not touch the surviving signatures")

	# Multi-pop: the same three entries against a cap of 1 need TWO pops, which is what the
	# `while` is for and what the capacity-2 row above cannot reach.
	var mw: Array[float] = [3.0, 3.0, 3.0, 0.0]
	var ma: Array[int] = [Signature.GUARD, Signature.WINDUP, Signature.AFTER]
	_evict_over_capacity(mw, ma, 1)
	assert(ma.size() == 1 and ma[0] == Signature.AFTER, "eviction must keep popping until the list fits the cap")
	assert(mw[Signature.GUARD] == 0.0 and mw[Signature.WINDUP] == 0.0, "every evicted signature's weight must be zeroed, not just the first")


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
	enemy_hp = 9   # must track the declaration: this block overwrites it before anything reads it
	counter_damage = 1
	attack_damage = 1
	player_attack_recovery = 1.0
	vengeful_duration = 2.5
	vengeful_telegraph_multiplier = 0.6
	methodical_reset_time = 0.55
	methodical_resume = "next"
	enemy_constraint = "adaptive"
	adaptive_threshold = 3
	adaptive_capacity = 2
	adaptive_patience_guard_multiplier = 0.5
	sequence = _parse_sequence(SEQUENCE_DEFAULT)
	seq_index = 0
	_clear_adaptation()
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
	methodical_reset_time = maxf(0.0, _num(data, "methodical_reset_time", methodical_reset_time))
	# Only "restart" opts into the harsh rule; a typo or a bad type lands on the default.
	methodical_resume = "restart" if _str(data, "methodical_resume", methodical_resume) == "restart" else "next"
	# Same gate shape: only the exact non-default string opts out, so a typo, a number or a
	# missing key lands on "adaptive". The two constraints never run together.
	enemy_constraint = "vengeful" if _str(data, "enemy_constraint", enemy_constraint) == "vengeful" else "adaptive"
	# floored at 1: threshold 1 adapts off a single cycle, which is a degenerate setting but a
	# legitimate one for checking that the whiff and the stance shift read at all.
	adaptive_threshold = maxi(1, int(_num(data, "adaptive_threshold", float(adaptive_threshold))))
	# floored at 1, not 0: a capacity of 0 would evict every adaptation on the boundary that
	# formed it, so the trait would be a no-op with a stance shift on top of it.
	adaptive_capacity = maxi(1, int(_num(data, "adaptive_capacity", float(adaptive_capacity))))
	# never 0: it multiplies the guard beat, and a 0-length beat would delete the punctuation
	# the sequence is counted against. 1.0 = adapted PATIENCE costs nothing.
	adaptive_patience_guard_multiplier = clampf(_num(data, "adaptive_patience_guard_multiplier", adaptive_patience_guard_multiplier), 0.05, 1.0)
	sequence = _parse_sequence(_str(data, "methodical_sequence", SEQUENCE_DEFAULT))
	if sequence.is_empty():
		sequence = _parse_sequence(SEQUENCE_DEFAULT)   # a sequence of no attacks is not a pattern
	seq_index = 0   # a shorter sequence must never be indexed with a stale position
	_clear_adaptation()   # and a weight must never be carried across a threshold change
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


func _str(d: Dictionary, key: String, fallback: String) -> String:
	# _num's sibling: same guard shape, for the keys that are text.
	if d.has(key) and typeof(d[key]) == TYPE_STRING:
		return String(d[key])
	return fallback


func _parse_sequence(s: String) -> Array[int]:
	# A/B case-insensitive, every other character ignored, so "aabab" and "A-A-B-A-B" both
	# parse. Runs once at load, never per cycle. Callers must handle the empty result.
	var out: Array[int] = []
	for ch in s.to_upper():
		if ch == "A":
			out.append(AttackType.A)
		elif ch == "B":
			out.append(AttackType.B)
	return out


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
	elif result_text == "HIT":
		# Player blue, lifted for legibility on the dark background: this outcome is YOURS and
		# not a read on the enemy's attack, so it takes neither the win green nor the loss red.
		# == and not begins_with, because both adaptive labels are exact and can never carry an
		# A/B suffix, so neither can collide with the WIN prefix above.
		result_label.modulate = Color(0.45, 0.75, 1.0)
	elif result_text == "WHIFF":
		result_label.modulate = Color(0.62, 0.58, 0.50)   # duller and dimmer than the watching gray: a swing that bought nothing
	else:
		result_label.modulate = Color(0.85, 0.85, 0.9)


func _update_info_label() -> void:
	var w: float = minf(counter_window, telegraph_length)
	var opens: float = telegraph_length - w
	var seed_txt: String = "random" if seed_value <= 0 else str(seed_value)
	var window_txt: String = "counter window: %.2f-%.2f s of windup" % [opens, telegraph_length]
	var venge_txt: String = ""
	var constraint_txt: String = ""
	# Only the live constraint's keys are printed. The two are mutually exclusive, so the HUD
	# stays the same height either way and never shows a number that cannot do anything.
	if enemy_constraint == "adaptive":
		# `active` is a bare COUNT. Which signatures are adapted, and every weight, are
		# DELIBERATELY absent for the same reason as the sequence below: working out which
		# habit it learned is exactly what the whiff, the label and the stance shift exist to
		# make you do. A count leaks no habit and still warns you an eviction is one away.
		# methodical_reset_time keeps printing its TUNED value, never eff_guard_time, which
		# would leak that PATIENCE is adapted.
		constraint_txt = "adaptive_threshold: %d   adaptive_capacity: %d   active: %d/%d\nadaptive_patience_guard_multiplier: %.2f" % [adaptive_threshold, adaptive_capacity, adapt_active.size(), adaptive_capacity, adaptive_patience_guard_multiplier]
	else:
		# same math on the vengeful telegraph, printed side by side: the window SIZE should match.
		var vt: float = telegraph_length * vengeful_telegraph_multiplier
		var vw: float = minf(counter_window, vt)
		constraint_txt = "vengeful_duration: %.2f s\nvengeful_telegraph_multiplier: %.2f" % [vengeful_duration, vengeful_telegraph_multiplier]
		window_txt += "   (vengeful: %.2f-%.2f)" % [vt - vw, vt]
		venge_txt = (">>> VENGEFUL  %.1f s left <<<" % vengeful_left) if vengeful_left > 0.0 else ""
	# `methodical_sequence`, `sequence` and `seq_index` are DELIBERATELY absent. Printing any
	# of them would hand back the lookup table this whole trait exists to make you earn by
	# watching. The post-cycle A/B reveal on the result label is the only ground truth.
	info_label.text = "telegraph_length: %.2f s\ncounter_window:  %.2f s\ncamera_distance: %.1f\nwindup_color_amount: %.2f\nwindup_lean_amount:  %.2f\nenemy_hp: %d   (left: %d)\ncounter_damage: %d   attack_damage: %d\nplayer_attack_recovery: %.2f s\nenemy_constraint: %s\n%s\nmethodical_reset_time: %.2f s   methodical_resume: %s\nseed: %s\n%s\n%s\nSPACE = counter A   K = counter B   J = attack   R = reload" % [telegraph_length, counter_window, camera_distance, windup_color_amount, windup_lean_amount, enemy_hp, enemy_hp_left, counter_damage, attack_damage, player_attack_recovery, enemy_constraint, constraint_txt, methodical_reset_time, methodical_resume, seed_txt, window_txt, venge_txt]
