# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Descent is a Godot 4.7 (Forward Plus, Jolt) combat prototype. It's a decision test, not a game: one enemy telegraphs attack A or B, the player counters (SPACE beats A, K beats B) or swings (J), and each phase measures one question about that loop. README.md is the spec, findings.md is the playtest log, and README cites findings by item number ("findings item 8").

## Commands

Run the combat regressions (headless, about 173 checks, exits 1 on any failure):

```powershell
& 'C:/Users/super/Documents/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64_console.exe' --headless --path . --script tools/test_combat.gd
```

There's no single-test flag. To run one test, temporarily comment out the other calls in `_run()` at the bottom of `tools/test_combat.gd`.

Diagnostic trace: set `enemy_hp` to `12` in `tuning.json`, append `-- --diagnostic` to the command above, then put it back to `9`. The diagnostic asserts it loaded 12.

Play: open `project.godot` in the Godot 4.7 editor and press F5. In game, R reloads `tuning.json` live.

Regenerate assets (only needed to change them, outputs are committed):

```
"C:\Program Files\Blender Foundation\Blender 4.5\blender.exe" --background --python tools/gen_assets.py
python tools/gen_audio.py
```

`gen_audio.py` hardcodes the SoX path in a `SOX` variable at the top.

## Architecture

All game code is in `main.gd`. `main.tscn` only attaches the script. `_ready()` builds the whole world, HUD, camera and audio in code. Input comes from raw keycodes in `_unhandled_input`, with no input map. GLBs load through `ResourceLoader`; if one isn't imported, `_model_or_capsule` and `_fallback_arena` substitute primitives of the same shape and color. WAVs load at runtime via `AudioStreamWAV.load_from_file`, so they need no import.

The enemy is a state machine, `enum State { IDLE, WINDUP, STRIKE, RECOVERY, VENGEFUL, ADAPT }`. `_process` drives per-state timing and posing, and the `_enter_*` functions handle transitions. Values that must not change mid-cycle (`eff_telegraph`, `vengeful_cycle`, `eff_guard_time`) are locked when their state is entered.

Three traits sit on that loop:
- Methodical is always on. The A/B order comes from `methodical_sequence`, and `seq_index` advances when a sequence wind-up begins and is never rolled back, so cancelling a wind-up with J burns that step. IDLE is the guard beat before each sequence attack.
- `enemy_constraint` adds exactly one of Vengeful or Adaptive, never both. Only the exact string `"vengeful"` selects Vengeful, and anything else falls through to Adaptive.
- Adaptive buckets each accepted J press into a `Signature` (GUARD, WINDUP, AFTER, or PATIENCE for a cycle with no swing). A press only marks `adapt_seen`. All the weight math runs once per cycle in `_close_cycle()` at recovery exit. `_step_weights` and `_evict_over_capacity` take their arrays as parameters so `_selftest_adaptive()` can check the arithmetic on locals at startup without touching live state.

Reset scopes differ, and that's deliberate. `_reset_fight()` (death or FIGHT WON) refills HP and clears the rage window, but keeps `seq_index` and all Adaptive memory. Only `_load_tuning()` (the R key) restarts the sequence and clears Adaptive.

`_load_tuning()` never crashes. It resets every field to its default, then overlays `tuning.json` through `_num`/`_str`. A missing file, a wrong type or garbage falls back to the default, and values get clamped.

## Changing a tuning value or default

A shipped value lives in several places, and past changes touched all of them together (see commit 5dd8324):
- `tuning.json`
- `main.gd`: the `var` declaration, and the reset block at the top of `_load_tuning()`
- `README.md`: the Tuning key list, the fallback defaults sentence, and any narrative that does arithmetic on the value
- `tools/test_combat.gd`: tests instantiate the real `main.gd`, which reads the real `tuning.json`, so `_test_default_counter_hit` and `_diagnostic` assert the shipped values and fail if `tuning.json` changes

The `var` defaults for `windup_color_amount` and `windup_lean_amount` (1.0) intentionally differ from what `tuning.json` ships (0.0 and 2.0).

## Test harness

`tools/test_combat.gd` extends `SceneTree`. `_fresh()` creates a new `main.gd` node, calls `set_process(false)`, nulls the audio streams and fixes the RNG seed. Tests then advance time by calling `game._process(dt)` directly and inject keys through `_press(KEY_...)`. Helpers `_windup()`, `_counter()` and `_finish_cycle()` step through one cycle. New test functions have to be added to `_run()`.

These tests cover mechanics only. Readability and feel (can the player tell the poses apart, does a beat read as a beat) need a human in the editor. README's Verification section lists those checks per phase. Don't report a visual or behavioral change as verified based on the test run alone.

## Design invariants

These are what the experiments measure. Breaking one invalidates a phase even if every test passes.
- The HUD never shows `methodical_sequence`, the position in it, the next attack, which signatures are adapted, or any weight. Under PATIENCE it shows the tuned `methodical_reset_time`, not the compressed one.
- The A/B letter is revealed only during recovery, never during a wind-up. HIT, WHIFF and FIGHT WON never carry a letter.
- The read has to work from pose alone at `windup_color_amount` 0.0. Each motion owns its own axis: A rears back and tips away, B crouches and squashes, the guard beat rolls, Vengeful rises tall and trembles sideways, and the Adaptive stance shift lifts off the floor. A new cue must not reuse an axis.
- Adaptive never reads, whiffs or changes counters. A swing into an adapted bucket still costs `player_attack_recovery`.
- Audio is one wind-up cue and one hit cue on a loss. A win is silent.

## Repo notes

- GDScript is tab-indented. `.gitattributes` forces LF line endings.
- `agents/` holds identical copies of `.claude/agents/maker.md` and `checker.md` for Codex, which reads `AGENTS.md`. If you edit an agent definition, update both copies.

## Project subagents

These support the maker-checker loop below. They don't replace any step of it.
- `godot-test-runner`: run after the Maker. The Checker can't run commands, so this keeps test results from coming only from the agent that wrote the code.
- `tuning-sync`: run when a change touches a tuning key, a default, a clamp, or a number the README quotes.
- `design-guard`: run alongside the Checker when `main.gd` changes touch the HUD, labels, posing, audio, the state machine, input, or Adaptive.

## Development Workflow — Maker-Checker


Every code change MUST go through this workflow:


1. **Understand** — Read the requirements. Ask clarifying questions if needed.

2. **Make** — Use @maker to implement the changes.

3. **Check** — Use @checker to review what the Maker wrote.

4. **Fix** — If the Checker found Critical or Important issues, use @maker

   to fix them.

5. **Re-check** — Run @checker again after fixes. Repeat until the verdict

   is APPROVE.

6. **Commit** — Only after the Checker approves.


Never skip the Checker step. Never let the Maker review its own code.
