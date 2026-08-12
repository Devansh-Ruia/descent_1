# Descent - Phase 2: the first trait

Not a game. This is a decision test built on the Phase 0 readability test: a bare
room, one enemy that telegraphs one of two attacks each cycle, two counters, and
now one attack of your own. You read which attack is winding up and press its
counter. You are judging:

1. Can you tell attack **A**'s wind-up from attack **B**'s in time to choose?
2. Does landing the right counter feel like a **read**, not a guess between two
   buttons?
3. Does hitting the enemy feel like it costs you something?

## How to run

1. Open this folder as a project in **Godot 4.7** (Project Manager -> Import ->
   pick `project.godot`). First open imports the `.glb` assets. The `.wav`
   audio now loads at runtime (`AudioStreamWAV.load_from_file`), so it needs no
   import step.
2. Press **F5** (Play). The main scene is `main.tscn`.
3. Controls:
   - **SPACE** - counter attack A. Press it inside the tail of the wind-up.
   - **K** - counter attack B.
   - **J** - attack the enemy.
   - **R** - reload `tuning.json` live (also re-applies the camera distance, the
     seed, and refills the enemy's HP).

   Forced choice: each counter only beats its own attack. Press the wrong one,
   mistime it, or do nothing and the strike lands = LOSE.

The enemy loops forever: it waits, telegraphs one of two wind-ups while a rising
tone plays (the tell), then lunges. Attack A rears back tall and tips away;
attack B crouches low, squashing down in place. Both share the same tone and the
same timing, so the pose is the only thing that says which is coming. Counter the
correct attack during the tell's tail = WIN (flash + label). Wrong counter,
mistimed, or nothing = the strike lands (thud) = LOSE. After each result it
auto-resets and reveals the attack letter (A or B) on the label, so you can
check your read before the next cycle.

## Your attack, and what it costs

**J** lands a hit whenever the enemy is not already mid-strike. During its strike
you whiff, because the strike is committed and moving. Either way the press puts
you in recovery for `player_attack_recovery` seconds, and **SPACE and K do
nothing while that is draining**. A press during your own recovery is not
consumed either, it simply does not happen, so you cannot burn your one counter
attempt by mashing. That is the trade this phase exists to test: every swing you
throw buys damage with defense.

The enemy has `enemy_hp` hits in it (default 3). The last one ends the fight:
the label reads **FIGHT WON**, holds through the usual recovery beat, then the
enemy refills and the loop continues so you can keep testing. FIGHT WON does not
print an A/B letter, because it is not a read on this cycle's attack. You still
die to a single enemy hit. That asymmetry is deliberate.

## Vengeful

The first trait, and the only one. Vengeful is a constraint, not a behaviour
pattern: it does not learn, adapt, or read you.

- **Trigger.** Deterministic. Every landed hit sets `vengeful_left =
  vengeful_duration`. There is no roll and no condition. Hit it, it is vengeful.
- **The tell.** The enemy rises tall and trembles, straight up, no rotation. That
  is on purpose: A rears back and tips away, B crouches low, and Vengeful does
  neither, so it cannot be misread as a wind-up. It snaps into the pose in about
  0.12 s and animates back down over the last 0.2 s of the pose, so both the
  entry and the exit are visible events.
- **The effect.** An attack that *begins* while the rage window is open telegraphs
  at `telegraph_length * vengeful_telegraph_multiplier` (default 0.6, so 1.2 s
  becomes 0.72 s). The **counter window keeps its size**: it is still
  `counter_window` seconds, still anchored to the tail of the wind-up. You get
  less time to read, not less time to press.
- **Cancel.** A hit landed during a wind-up **cancels that attack**. The cue
  stops, no strike commits, and the enemy goes into the vengeful pose instead.
  Punishing a wind-up works, and it is exactly what makes the next one faster.
- **Expiry.** The pose is a short beat. The rage window keeps running underneath
  it and can expire while the enemy is idling, in which case the next attack
  telegraphs at normal length. The HUD prints `VENGEFUL` with the seconds left.

Counters are ignored during the vengeful pose, the same as during idle and
recovery, because nothing is telegraphing.

The wind-up cue scales to the effective telegraph, vengeful or not: the fixed
`windup.wav` is played back stretched (via `pitch_scale`) so the rising tone
spans the whole wind-up and its peak lands on the strike commit at any length. A
vengeful wind-up therefore plays the same cue faster and higher, which is a
second, non-visual signal that the telegraph shortened. Tradeoff:
`pitch_scale` also lowers the pitch at longer telegraphs, so the cue drifts
deeper as `telegraph_length` grows. Switch to in-engine synthesis if that drift
is ever unwanted.

## Tuning

Edit `tuning.json` at the repo root. Nine keys, all numbers, plus one optional
tenth (`seed`):

```json
{
  "telegraph_length": 1.2,
  "counter_window": 0.35,
  "camera_distance": 8.0,
  "windup_color_amount": 0.0,
  "windup_lean_amount": 2.0,
  "enemy_hp": 3,
  "player_attack_recovery": 0.45,
  "vengeful_duration": 2.5,
  "vengeful_telegraph_multiplier": 0.6
}
```

- `telegraph_length` - seconds the wind-up lasts before the strike commits.
- `counter_window` - seconds the counter window stays open, anchored to the
  **tail** of the wind-up. The window is `[telegraph_length - counter_window,
  telegraph_length]` of elapsed wind-up time: it opens `counter_window` seconds
  before the strike and closes when the strike commits. Bigger = opens earlier =
  more forgiving. If `counter_window >= telegraph_length` it is clamped to the
  whole wind-up.
- `camera_distance` - world units from the arena center along the fixed 3/4
  camera direction.
- `windup_color_amount` - float `0.0..1.0`, scales the red->orange color shift
  during the wind-up. `1.0` = the full shift, `0.0` = no color change at all.
  Values outside the range are clamped.
- `windup_lean_amount` - float `>= 0`, multiplies how far the enemy moves during
  the wind-up, for both attacks: A's rear-back-and-tilt and B's crouch (squash,
  forward tip, widen) all scale by it. `1.0` = current, higher = more
  exaggerated, `0.0` = no pose change, which makes both attacks look identical
  and collapses the test. Each strike lunge starts from its scaled wind-up pose,
  so there is no pop when you change it.
- `enemy_hp` - integer `>= 1`, landed hits needed to win the fight. Clamped up to
  1 (a 0-HP enemy would end the fight on the first frame you touched it).
- `player_attack_recovery` - float `>= 0`, seconds each **J** press leaves you
  unable to counter. `0.0` makes attacking free and collapses the experiment.
- `vengeful_duration` - float `>= 0`, seconds the rage window stays open after a
  landed hit. `0.0` turns the trait off apart from the wind-up cancel.
- `vengeful_telegraph_multiplier` - float in `(0.0, 1.0]`, what the telegraph is
  multiplied by while vengeful. `1.0` = no speed-up, `0.6` = the wind-up is 40%
  shorter. Clamped to `0.05` at the bottom, never `0`, because it divides the
  audio `pitch_scale` and anchors the counter window.
- `seed` - **optional**. Integer seed for the RNG that drives the A/B pick each
  cycle and the idle-gap jitter. Leave the key out (or set it `<= 0`) and every
  run randomizes, which is the default. Set it to a positive integer to replay
  the same A/B order and the same timing. Pressing **R** re-applies it, which
  restarts the sequence from the top. Parsed as an integer, a fractional value is
  truncated. The HUD prints `seed: random` when no override is in force.

Save the file, then press **R** in-game to apply them live. The HUD shows the
current values, the enemy's remaining HP, the resolved counter window for both a
normal and a vengeful wind-up, and a `VENGEFUL` readout while the rage window is
open. Missing file or a bad/missing key falls back to sane defaults
(1.2 / 0.35 / 8.0 / 1.0 / 1.0 / 3 / 0.45 / 2.5 / 0.6, seed random) and keeps
running.

Note the interaction between `counter_window` and the vengeful telegraph: the
window is clamped to at most the whole wind-up. If you set `counter_window`
larger than `telegraph_length * vengeful_telegraph_multiplier`, the vengeful
window gets clamped and the window size does shrink. At the shipped values
(0.35 vs 0.72) it does not. The HUD prints both windows side by side so you can
see it.

### Experiment: can you discriminate the two attacks on pose alone?

Both attacks share one color shift and one tone, so with color off the pose is
the whole tell. Set `windup_color_amount` to `0.0` and `windup_lean_amount` to
`2.0`, save, press **R**, and play a session. Judge two things by hand:

1. Can you tell A's wind-up (tall, tips back) from B's (short, squats low) in
   time to choose a counter?
2. When you land the right counter, does it feel like you identified the attack,
   or like you guessed between two buttons?

If the two wind-ups read apart at color `0.0`, the pose is carrying the tell. If
they blur together, the tell was leaning on color.

### Experiment: is "stop attacking" an interesting decision?

This is the question Phase 2 exists to answer. Every hit you land makes the enemy
harder to read for the next few seconds, and every swing you throw leaves you
undefended while you throw it. So there is a case for not attacking: stand off,
counter cleanly, stay alive. And there is a case against it, which is that the
enemy has 3 HP and you cannot win by standing still.

Play a few fights and judge by hand:

1. Do you ever *choose* to hold back, or do you just attack whenever the enemy is
   not striking? If the answer is always attack, the cost is too cheap. Raise
   `player_attack_recovery`, or lower `vengeful_telegraph_multiplier`.
2. Is the shortened telegraph readable at all, or does a vengeful attack feel
   unfair? If it is unreadable, the trait is a punishment rather than a
   constraint. Raise `vengeful_telegraph_multiplier` toward `1.0` until it is
   tight but fair.
3. Does the rise-and-tremble land as a warning, or does it just look like a third
   attack you should be countering? It is meant to say "the next one is fast",
   not "counter me now".
4. Does the wind-up cancel feel good or feel cheap? Punishing a wind-up removes
   an attack and speeds up the next one. Whether that reads as a real trade or as
   a free win is the thing to watch.

The honest failure mode to look for: if the fastest way to win is to press **J**
three times as soon as the fight starts, the decision does not exist yet and the
cost needs to be somewhere else (a per-swing cooldown, or a longer rage window
than the pose).

Every other constant (idle jitter, strike speed, recovery time, the vengeful pose
length and shake, colors, camera angle) is hardcoded in `main.gd`, on purpose.

## Verification

The machine this was written on has no Godot binary, so **everything in Phase 2
is reviewed against Godot 4 conventions and is not runtime-confirmed**. Nothing
below has been seen or heard running. Verify by hand in the editor:

Phase 2 (player offense + Vengeful):

- **J** damages the enemy in idle, wind-up, recovery and vengeful, and whiffs
  only during the strike.
- SPACE and K genuinely do nothing for `player_attack_recovery` seconds after any
  J press, and a press inside that window does not consume the cycle's one
  counter attempt (you can still counter later in the same wind-up).
- Three hits produce **FIGHT WON**, it holds for the recovery beat, and the enemy
  comes back at full HP. The HUD's `left:` count matches what you have landed.
- Hitting the enemy mid-wind-up cancels it: the tone stops, no strike lands, and
  it rises into the vengeful pose.
- The vengeful pose is instantly distinct from both wind-ups. It should never
  bait you into pressing a counter.
- The exit from the pose is animated, not a snap, and no vengeful stretch or
  tremor leaks into idle.
- A wind-up that starts inside the rage window is visibly shorter, and the
  counter still needs the same press timing relative to the commit. Compare the
  two windows printed in the HUD.
- The rage window can expire with no attack, and the next wind-up is back to
  full length.
- No new sound. The only audio is the one wind-up cue and the one hit cue on a
  loss.

Phase 0/1 (should be unchanged):

- The two wind-ups are distinguishable at `windup_color_amount` `0.0`: A is tall
  and tips back, B is short and squats low.
- The correct counter wins and the wrong one loses (SPACE beats A only, K beats
  B only).
- Timing is identical between A and B: same `telegraph_length`, same counter
  window, same strike speed, same commit point. Only the post-commit lunge path
  differs, and that is after the window has closed.
- With no `seed` key the A/B order differs between runs, and adding
  `"seed": 20260726` replays the same order: note the sequence, press **R**, and
  confirm it repeats from the start.
- Audio is unchanged: one wind-up cue for both attacks, the hit cue only on a
  loss, silence on a win.
- The result label reveals the attack letter only during recovery, never during
  the wind-up, so it cannot leak the answer while you are still reading.

## Regenerating assets

All geometry is greybox primitives from Blender; all sound is synthesized with
SoX. Both are committed, so you only need these to change them.

Assets (`assets/player.glb`, `assets/enemy.glb`, `assets/arena.glb`):

```
"C:\Program Files\Blender Foundation\Blender 4.5\blender.exe" --background --python tools/gen_assets.py
```

Audio (`assets/audio/windup.wav`, `assets/audio/hit.wav`):

```
python tools/gen_audio.py
```

The SoX path is a single variable near the top of `tools/gen_audio.py` - edit it
there if SoX lives somewhere else. Current value:
`C:\Users\super\AppData\Local\Microsoft\WinGet\Packages\ChrisBagwell.SoX_Microsoft.Winget.Source_8wekyb3d8bbwe\sox-14.4.2\sox.exe`
