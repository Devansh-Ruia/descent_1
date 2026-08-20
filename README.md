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
you in recovery for `player_attack_recovery` seconds, and while that is draining
**SPACE, K and J all do nothing**. A blocked counter is not consumed, it simply
does not happen, so you cannot burn your one counter attempt by mashing. A
blocked J is eaten outright and does not refresh the lockout, so mashing cannot
trap you in permanent recovery either. That is the trade this phase exists to
test: every swing you throw buys damage with a full second of no defense.

The enemy has `enemy_hp` hits in it (default 3). The last one ends the fight:
the label reads **FIGHT WON**, holds through the usual recovery beat, then the
enemy refills and the loop continues so you can keep testing. FIGHT WON does not
print an A/B letter, because it is not a read on this cycle's attack.

You still die to a single enemy hit, and **dying resets the fight**: the enemy
comes back at full HP and no longer vengeful. Otherwise trading your life for one
hit would be strictly profitable, and the fastest route to FIGHT WON would be to
die twice on purpose. That asymmetry is deliberate: the enemy needs three of
yours, you need one of its. FIGHT WON and **R** reset the same way, so a fresh
fight never starts with a rage window still running.

## Vengeful

The first trait, and the only one. Vengeful is a constraint, not a behaviour
pattern: it does not learn, adapt, or read you.

- **Trigger.** Deterministic. Every landed hit sets `vengeful_left =
  vengeful_duration`. There is no roll and no condition. Hit it, it is vengeful.
  A hit landed while it is *already* in the pose refreshes the rage window but
  does not restart the pose, so repeat hits cannot pin it there.
- **The tell.** The enemy rises tall and trembles, straight up, no rotation. That
  is on purpose: A rears back and tips away, B crouches low, and Vengeful does
  neither, so it cannot be misread as a wind-up. It snaps into the pose in about
  0.12 s and animates back down over the last 0.2 s of the pose, so both the
  entry and the exit are visible events.
- **The retaliation.** The pose does not return to idle. It goes **straight into
  a wind-up**, so getting hit buys the enemy a turn. At the shipped values the
  sequence after your hit is fixed: 0.9 s of rising and trembling, then a 0.72 s
  wind-up, so the strike commits 1.62 s after you connect and the counter window
  is `[1.27, 1.62]`. No idle gap and no jitter, because the whole point is that
  you can learn this timing.
- **The effect.** An attack that *begins* while the rage window is open telegraphs
  at `telegraph_length * vengeful_telegraph_multiplier` (default 0.6, so 1.2 s
  becomes 0.72 s). The **counter window keeps its size**: it is still
  `counter_window` seconds, still anchored to the tail of the wind-up. You get
  less time to read, not less time to press.
- **Cancel.** A hit landed during a wind-up **cancels that attack**. The cue
  stops and no strike commits from it. This is not a free reset: the enemy rises
  into the pose and then throws a fresh, faster attack with a newly rolled A or
  B. Punishing a wind-up works, and it is exactly what makes the next one faster.
- **Expiry.** The rage window runs underneath all of this. After a retaliation
  cycle it usually runs out during the enemy's recovery, so once the loop
  settles back to idle the next attack telegraphs at normal length. Raise
  `vengeful_duration` past a full cycle and it will still be armed when the
  enemy comes back around. The HUD prints `VENGEFUL` with the seconds left.

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
  "player_attack_recovery": 1.0,
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
  unable to counter or swing again. `0.0` makes attacking free and collapses the
  experiment. It also has to stay above the length of the vengeful pose (0.9 s,
  hardcoded), or you can swing faster than the enemy can recover and it never
  gets a turn. `1.0` is the shipped value for that reason.
- `vengeful_duration` - float `>= 0`, seconds the rage window stays open after a
  landed hit. It also caps the pose, which is otherwise 0.9 s. At `0.0` the pose
  is skipped entirely and the enemy retaliates immediately at full telegraph
  length, which is a degenerate setting, not an off switch.
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
(1.2 / 0.35 / 8.0 / 1.0 / 1.0 / 3 / 1.0 / 2.5 / 0.6, seed random) and keeps
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

This is the question Phase 2 exists to answer, and at the shipped values it comes
down to arithmetic you can do at the keyboard.

Land a hit at `t = 0`. The enemy rises for 0.9 s and its retaliation commits at
1.62 s, with the counter window open from 1.27 s. Your own recovery ends at
1.0 s. So at 1.0 s you have a real choice, and it is not close to free either
way:

- **Hold back.** You are free at 1.0 s, well before the window opens at 1.27 s.
  Read A or B off the short wind-up, press the right counter, and you win the
  cycle without taking a hit.
- **Swing again.** You land a second hit and go into recovery until 2.0 s. The
  retaliation commits at 1.62 s, while you are still locked out. It hits you and
  you die.

That is the dilemma stated in seconds. There is no jitter in it, so which way it
goes is your read, not the RNG. Play a few fights and judge by hand:

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

The honest failure mode to look for: if the fastest way to win is to mash **J**
from the opening, the decision does not exist. Two things prevent that, and if it
still feels free, one of them is mistuned. `player_attack_recovery` gates the next
swing as well as the counters, so hits cannot be chained faster than 1.0 s. And
the retaliation out of the vengeful pose means the second hit in a chain is
answered at 1.62 s, inside the lockout the second hit bought. Mashing does not
race the enemy any more, it feeds it.

Every other constant (idle jitter, strike speed, recovery time, the vengeful pose
length and shake, colors, camera angle) is hardcoded in `main.gd`, on purpose.

## Verification

The machine this was written on has no Godot binary, so **everything in Phase 2
is reviewed against Godot 4 conventions and is not runtime-confirmed**. Nothing
below has been seen or heard running. Verify by hand in the editor:

Phase 2 (player offense + Vengeful):

- **J** damages the enemy in idle, wind-up, recovery and vengeful, and whiffs
  only during the strike.
- SPACE, K and J all do nothing for `player_attack_recovery` seconds after any J
  press, and a blocked counter does not consume the cycle's one counter attempt
  (you can still counter later in the same wind-up). Mashing J does not extend
  the lockout.
- Three hits produce **FIGHT WON**, it holds for the recovery beat, and the enemy
  comes back at full HP. The HUD's `left:` count matches what you have landed,
  and pressing J during the FIGHT WON hold does nothing.
- Dying resets the enemy to full HP and clears the rage window, so you cannot
  chip it down across deaths and a fresh fight never opens with a short
  telegraph. Same after FIGHT WON and after **R**.
- Repeat hits on an already-vengeful enemy do not restart the pose. It should
  always get back to idle and attack you, never be locked in place.
- Hitting the enemy mid-wind-up cancels it: the tone stops, no strike lands, and
  it rises into the vengeful pose.
- The pose leads straight into a wind-up with no idle pause, and that retaliation
  is counterable. Land a hit, do nothing else, and confirm you can read A or B
  off the short wind-up and counter it. If you cannot, the trait is a punishment
  rather than a constraint.
- Land a hit, immediately land a second, and confirm the retaliation reaches you
  while you are still locked out. That failure should be legible as your choice,
  not as the enemy cheating.
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
