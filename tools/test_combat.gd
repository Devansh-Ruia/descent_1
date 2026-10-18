extends SceneTree
# Deterministic input/state regressions. Run with --headless --path . --script tools/test_combat.gd.
# --diagnostic additionally requires enemy_hp: 12 in tuning.json, loaded by the real scene.

const Combat = preload("res://main.gd")
const S = Combat.State
const B = Combat.Signature
var game
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)


func _fresh() -> void:
	if is_instance_valid(game):
		game.free()
	game = Combat.new()
	root.add_child(game)
	game.set_process(false)
	# Audio playback runs on a separate clock; these synchronous mechanics checks do not.
	game.windup_player.stream = null
	game.hit_player.stream = null
	game.rng.seed = 20260917
	game._enter_idle()


func _press(key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.pressed = true
	game._unhandled_input(event)


func _windup() -> void:
	_check(game.state == S.IDLE, "sequence attack must start with a guard beat")
	game._process(0.05)
	_check(absf(game.enemy_root.rotation.z) > 0.001, "Methodical guard tell actually rolls")
	game._process(game.idle_gap - game.state_time + 0.001)
	_check(game.state == S.WINDUP, "guard hands off to a wind-up")
	_check(is_zero_approx(game.enemy_root.rotation.z), "guard roll ends before wind-up")


func _counter() -> void:
	game._process(game.eff_telegraph - game.counter_window + 0.001 - game.state_time)
	_press(KEY_SPACE if game.attack == Combat.AttackType.A else KEY_K)
	_check(game.state == S.RECOVERY, "correct tail-window counter succeeds")


func _finish_cycle() -> void:
	game._process(game.RECOVERY_TIME - game.state_time + 0.001)
	if game.state == S.ADAPT:
		game._process(game.ADAPT_POSE_TIME + 0.001)
	_check(game.state == S.IDLE, "cycle returns to Methodical guard")


func _test_default_counter_hit() -> void:
	_fresh()
	_check(game.enemy_constraint == "adaptive", "loaded tuning enables Adaptive")
	_check(game.sequence == [0, 0, 1, 0, 1] and game.methodical_resume == "next", "loaded Methodical AABAB / next")
	_check(game.adaptive_capacity == 2 and game.adaptive_threshold == 1, "shipped capacity and threshold")
	_check(game.enemy_hp == 9 and game.counter_damage == 1 and game.attack_damage == 1, "normal HP and damage unchanged")
	# This scenario needs the third counter-then-J to kill before AFTER activates, which the shipped HP no longer does.
	game.enemy_hp = 6
	game.enemy_hp_left = 6
	# It also needs J to land on three cycles before AFTER activates, which the shipped threshold 1 does not allow.
	game.adaptive_threshold = 3
	var attacks: Array[int] = []
	for cycle in range(3):
		_windup()
		attacks.append(game.attack)
		_counter()
		_check(not game.adapt_seen.has(true), "counter is not a discretionary swing")
		_check(game._press_signature() == B.AFTER, "post-counter press uses AFTER")
		_press(KEY_J)
		_check(game.adapt_seen == [false, false, true, false], "post-counter J records only AFTER")
		_check(game.enemy_hp_left == 6 - 2 * (cycle + 1), "cold counter-plus-J deals two HP per cycle")
		_check(game.adapt_weight[B.AFTER] == float(cycle), "damage resolves before cycle learning")
		_check(not game.adapt_active.has(B.AFTER), "threshold does not retroactively block third hit")
		if cycle == 2:
			_check(game.result_text == "FIGHT WON", "third J is the killing swing at normal HP")
			game._process(1.01)
			var seen: Array = game.adapt_seen.duplicate()
			_press(KEY_J)
			_press(KEY_SPACE)
			_press(KEY_K)
			_check(game.adapt_seen == seen and game.player_recovery_left == 0.0, "post-win inputs do not sample or spend recovery")
			game._process(game.RECOVERY_TIME - game.state_time + 0.001)
			_check(game.state == S.IDLE and game.enemy_hp_left == 6, "terminal boundary refills without scheduling a corpse stance")
			_check(game.adapt_weight[B.AFTER] == 3.0 and game.adapt_active == [B.AFTER], "killing cycle counted exactly once at its boundary")
			if game.state == S.ADAPT:
				game._process(game.ADAPT_POSE_TIME + 0.001)
		else:
			_finish_cycle()
	for cycle in range(2):
		_windup()
		attacks.append(game.attack)
		_counter()
		var hp: int = game.enemy_hp_left
		var label: String = game.result_text
		_press(KEY_J)
		_check(game.enemy_hp_left == hp and game.hit_flinch == 0.0, "living post-counter matching J reaches learned whiff")
		_check(game.state == S.RECOVERY and game.result_text == label, "learned recovery response preserves A/B reveal")
		_check(game.player_recovery_left == game.player_attack_recovery, "learned whiff still costs defense")
		_finish_cycle()
	_check(attacks == [0, 0, 1, 0, 1], "actual Adaptive attacks execute AABAB across fight reset")
	_check(game.vengeful_left == 0.0 and not game.vengeful_cycle, "Adaptive never enables Vengeful")
	var hp: int = game.enemy_hp_left
	_press(KEY_J)
	_check(game.enemy_hp_left == hp - 1 and game.adapt_seen[B.GUARD], "unlearned guard timing remains meaningful")
	_check(game.seq_index == 0, "guard swing does not consume the next Methodical step")
	print("TRACE default: counter+J HP 4,2,0; AFTER weights 1,2,3 at recovery exits; next-fight matching J whiffs; attacks AABAB")


func _test_terminal_inputs() -> void:
	_fresh()
	game.enemy_hp_left = 1
	_windup()
	_counter()
	_check(game.result_text == "FIGHT WON", "killing counter retains fight result")
	_press(KEY_J)
	_check(not game.adapt_seen.has(true) and game.player_recovery_left == 0.0, "J after killing counter is rejected before learning")
	_finish_cycle()
	_check(game.adapt_weight[B.PATIENCE] == 1.0 and game.adapt_weight[B.AFTER] == 0.0, "post-win press cannot replace legitimate PATIENCE sample")
	for constraint in ["adaptive", "vengeful"]:
		_fresh()
		game.enemy_constraint = constraint
		_windup()
		game._process(game.eff_telegraph + 0.001)
		game._process(game.STRIKE_DURATION + 0.001)
		_check(game.result_text.begins_with("LOSE"), "missed counter ends the fight")
		var hp: int = game.enemy_hp_left
		_press(KEY_J)
		_press(KEY_SPACE)
		_press(KEY_K)
		_check(game.state == S.RECOVERY and game.enemy_hp_left == hp, "post-loss input cannot hit refilled enemy or schedule retaliation")
		_check(not game.adapt_seen.has(true) and game.player_recovery_left == 0.0 and game.vengeful_left == 0.0, "post-loss inputs cannot sample or arm a response")
		_finish_cycle()
		_check(game.seq_index == 1, "death does not rewind Methodical")
		if constraint == "adaptive":
			_check(game.adapt_weight[B.PATIENCE] == 1.0 and game.adapt_weight[B.AFTER] == 0.0, "loss boundary counts its completed cycle once")


func _test_sampling_and_rejection() -> void:
	_fresh()
	_windup()
	game.player_recovery_left = 0.4
	_press(KEY_J)
	_press(KEY_SPACE)
	_check(not game.adapt_seen.has(true) and not game.counter_spent, "recovery-rejected inputs are not actions")
	_check(game.player_recovery_left == 0.4, "rejected J does not extend recovery")
	game._process(0.4)
	_press(KEY_J)
	_check(game.state == S.RECOVERY and game.adapt_seen == [false, true, false, false], "cancel signature captured before WINDUP changes to RECOVERY")
	_check(game.result_text == "HIT" and game.seq_index == 1, "cancel burns sequence step without revealing attack")
	_finish_cycle()
	_windup()
	_check(game.attack == Combat.AttackType.A and game.seq_index == 2, "next resumes after cancelled first step")
	game._process(game.eff_telegraph + 0.001)
	var hp: int = game.enemy_hp_left
	_press(KEY_J)
	_check(game.state == S.STRIKE and game.enemy_hp_left == hp and game.adapt_seen[B.AFTER], "valid strike whiff still samples AFTER")
	game._process(game.STRIKE_DURATION + 0.001)
	_finish_cycle()
	_check(game.adapt_weight[B.AFTER] == 1.0 and game.adapt_weight[B.WINDUP] == 0.4, "valid whiff counts once and unused bucket decays")


func _test_memory_and_reset() -> void:
	_fresh()
	# At threshold 1 the J into recovery below, counted at the boundary after the death, would adapt AFTER and evict GUARD, failing "death preserves active memory".
	game.adaptive_threshold = 3
	# Exercise the production boundary, including replacement. Arithmetic-only rotation
	# and multi-eviction assertions also run in the existing _selftest_adaptive on _ready.
	for bucket in [B.AFTER, B.GUARD, B.WINDUP]:
		for cycle in range(3):
			game._mark_seen(game.adapt_seen, bucket)
			game._close_cycle()
			_check(game.adapt_active.size() <= game.adaptive_capacity, "memory always stays within capacity")
	_check(game.adapt_active == [B.GUARD, B.WINDUP] and game.adapt_weight[B.AFTER] == 0.0, "third habit evicts oldest and zeroes its weight")
	game._enter_recovery("WIN")
	var hp: int = game.enemy_hp_left
	_press(KEY_J)
	_check(game.enemy_hp_left == hp - 1, "evicted AFTER is usable again")
	game._reset_fight()
	_check(game.adapt_active == [B.GUARD, B.WINDUP], "fight reset preserves specified memory boundary")
	game._lose()
	_finish_cycle()
	_check(game.adapt_active == [B.GUARD, B.WINDUP], "death preserves active memory")
	_press(KEY_R)
	_check(game.adapt_active.is_empty() and game.adapt_weight == [0.0, 0.0, 0.0, 0.0] and not game.adapt_seen.has(true), "R reload clears all memory")
	_check(game.seq_index == 0 and game.enemy_hp_left == game.enemy_hp, "R resets sequence and HP")


func _test_counter_windows_and_vengeful() -> void:
	_fresh()
	_windup()
	game._process(game.eff_telegraph - game.counter_window - 0.01)
	_press(KEY_SPACE)
	_check(game.state == S.WINDUP and game.counter_spent, "early correct counter spends attempt without winning")
	_fresh()
	_windup()
	game._process(game.eff_telegraph - game.counter_window + 0.001)
	_press(KEY_K)
	_check(game.state == S.WINDUP and game.counter_spent, "wrong counter cannot win inside window")
	_fresh()
	_windup()
	game.state_time = game.eff_telegraph
	_press(KEY_SPACE)
	_check(game.state == S.RECOVERY and game.enemy_hp_left == 8, "counter at wind-up tail remains valid")
	_fresh()
	_windup()
	game._process(game.eff_telegraph + 0.001)
	_press(KEY_SPACE)
	_check(game.state == S.STRIKE and game.counter_spent, "counter after strike commit is too late")
	_fresh()
	game.enemy_constraint = "vengeful"
	_windup()
	_counter()
	_check(game.enemy_hp_left == 8 and game.vengeful_left == 0.0, "Vengeful counter damage is intact and never enrages")
	_finish_cycle()
	_windup()
	_press(KEY_J)
	_check(game.state == S.VENGEFUL and game.seq_index == 2, "landed J cancels sequence step and arms Vengeful")
	game._process(game.VENGE_POSE_TIME + 0.001)
	_check(game.state == S.WINDUP and game.vengeful_cycle and game.seq_index == 2, "retaliation starts without guard or sequence advancement")
	_check(is_equal_approx(game.eff_telegraph, 0.72) and game.enemy_root.rotation.z == 0.0, "retaliation timing and guard arbitration unchanged")
	_check(is_equal_approx(game.counter_window, 0.35), "short wind-up retains full counter window")
	game._process(0.11)
	var hp: int = game.enemy_hp_left
	_press(KEY_J)
	_check(game.state == S.WINDUP and game.enemy_hp_left == hp and game.player_recovery_left == 1.0, "J cannot cancel retaliation and still spends recovery")
	_check(not game.adapt_seen.has(true) and game.adapt_active.is_empty(), "Vengeful test never learns Adaptive signatures")
	game._process(game.eff_telegraph + 0.001)
	game._process(game.STRIKE_DURATION + 0.001)
	_finish_cycle()
	_windup()
	_check(game.attack == Combat.AttackType.B and game.seq_index == 3 and not game.vengeful_cycle, "next resumes at B after interrupted A and off-sequence retaliation")
	_fresh()
	game.enemy_constraint = "vengeful"
	_press(KEY_J)
	game._process(game.VENGE_POSE_TIME + 0.001)
	_counter()
	_check(game.enemy_hp_left == 7 and game.seq_index == 0, "retaliation remains counterable at its tail without consuming a sequence step")
	_check(game.vengeful_left < game.vengeful_duration - 1.0, "counter does not refresh the rage window")
	_fresh()
	game.enemy_constraint = "vengeful"
	game.player_attack_recovery = 0.0
	_press(KEY_J)
	game._process(0.2)
	_press(KEY_J)
	_check(game.state == S.VENGEFUL and is_equal_approx(game.state_time, 0.2), "repeat landed J refreshes rage without restarting its pose")


func _diagnostic() -> void:
	_fresh()
	_check(game.enemy_hp == 12, "diagnostic must load temporary enemy_hp 12 from tuning.json")
	_check(game.enemy_constraint == "adaptive" and game.adaptive_threshold == 1 and game.adaptive_capacity == 2, "diagnostic isolates Adaptive at default learning settings")
	# Its trace of three landed J and then whiffs depends on threshold 3, so it runs there.
	game.adaptive_threshold = 3
	var attacks: Array[int] = []
	for cycle in range(6):
		_windup()
		attacks.append(game.attack)
		_counter()
		var hp: int = game.enemy_hp_left
		_press(KEY_J)
		_check(game.enemy_hp_left == hp - (1 if cycle < 3 else 0), "diagnostic matching swing response on cycle %d" % (cycle + 1))
		_check(game.enemy_hp_left > 0 and game.vengeful_left == 0.0, "diagnostic remains alive without Vengeful")
		if cycle == 2:
			_check(not game.adapt_active.has(B.AFTER), "third hit resolves before diagnostic activation")
		_finish_cycle()
		_check(game.adapt_weight[B.AFTER] == float(cycle + 1), "diagnostic repeats the same AFTER signature")
		print("TRACE diagnostic: cycle=%d attack=%s hp=%d AFTER_weight=%.1f learned=%s" % [cycle + 1, "A" if game.attack == 0 else "B", game.enemy_hp_left, game.adapt_weight[B.AFTER], game.adapt_active.has(B.AFTER)])
	_check(attacks == [0, 0, 1, 0, 1, 0], "diagnostic executes Methodical AABABA")


func _run() -> void:
	if "--diagnostic" in OS.get_cmdline_user_args():
		_diagnostic()
	else:
		_test_default_counter_hit()
		_test_terminal_inputs()
		_test_sampling_and_rejection()
		_test_memory_and_reset()
		_test_counter_windows_and_vengeful()
	if is_instance_valid(game):
		game.free()
	print("Combat regressions: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
