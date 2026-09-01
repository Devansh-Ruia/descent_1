## 1. Pose carries the read, color was training wheels.
Tested at `windup_color_amount` 0.0 with `windup_lean_amount` 2.0 (test_6), color shift fully off.
Wins landed from the start of the session, earlier than the color-on run (test_5) where wins only clustered in the back third.
Conclusion: the lean/pose carries the tell, color was redundant.

## 2. Two tells discriminate under forced choice.
Two attacks (A rears back, B crouches low), SPACE/K forced choice, 0.35 s window at color 0 (test_7).
Player converted on BOTH attack types after early misses, not just one key.
Conclusion: the read discriminates between tells, it is not a two-button coin flip.

## 3. Vengeful as built made aggression strictly dominant.
Phase 2 first play (test_8): 3 fights, 3 FIGHT WONs, 0 deaths, never struck after the opening cycle.
HP fell exactly 1/second (= `player_attack_recovery` 1.0), every J swing landed inside the retaliation wind-up and cancelled it.
Conclusion: "stop attacking" had no answer but no, so the decision under test did not exist.

## 4. After both fixes, the aggressive line is untested, not balanced.
Phase 2.1 (test_9): J was never pressed once, VENGEFUL never lit across all 56 sampled seconds. Counter-only: 6 deaths, 2 fight wins.
The counter lane is not the "near-zero risk" the model predicted, deaths came from misreading A vs B, not from mistiming.
Open: deaths-per-win for the aggressive line is UNMEASURED, the only aggressive data (test_8, 0 deaths : 3 wins) is from the pre-fix build and measures the exploit, not the game. One session opening with J is required before any tuning decision.

## 5. Arbitration: the retaliation is off-sequence and the sequence never rewinds.
Phase 3 shipped Methodical (fixed `"AABAB"` order, 0.55 s guard beat in IDLE) with the rule that Vengeful's retaliation is a coin flip that never advances the position, while `seq_index` advances the instant a sequence wind-up begins and is never rolled back, so cancelling one with J burns that step permanently.
`"restart"` (zero the position at the retaliation) ships as a tuning alternative, not the default: charging the whole pattern for one swing is a bigger tax than the phase is trying to measure, and `"next"` already makes swinging cost a step.
Open: whether the player ever holds back a swing SPECIFICALLY to keep tracking the sequence is UNMEASURED. Reviewed against Godot 4 conventions only, no Godot binary on this machine, so the guard beat and the handoff have not been seen running.
