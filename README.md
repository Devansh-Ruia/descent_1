# Descent - Phase 2: the first trait

Not a game. This is a decision test built on the Phase 0 readability test: a bare
room, one enemy that telegraphs one of two attacks each cycle, two counters, and
now one attack of your own. You read which attack is winding up and press its
counter. You are judging:

1. Can you tell attack **A**'s wind-up from attack **B**'s in time to choose?
2. Does landing the right counter feel like a **read**, not a guess between two
   buttons?
3. Does hitting the enemy feel like it costs you something?
4. Both verbs deal damage now. Do you ever *choose* the slow safe one, or is one
   of the two strictly better?

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
correct attack during the tell's tail = WIN (flash + label), and it takes
`counter_damage` off the enemy's HP. Wrong counter, mistimed, or nothing = the
strike lands (thud) = LOSE. After each result it
auto-resets and reveals the attack letter (A or B) on the label, so you can
check your read before the next cycle.

## Your attack, and what it costs

**J** lands a hit whenever the enemy is not already mid-strike and not winding up
a retaliation. It whiffs during the strike, because the strike is committed and
moving, and it whiffs for the whole of a vengeful wind-up, because that attack is
the one you provoked (see **Vengeful** below). Either way the press puts
you in recovery for `player_attack_recovery` seconds, and while that is draining
**SPACE, K and J all do nothing**. A blocked counter is not consumed, it simply
does not happen, so you cannot burn your one counter attempt by mashing. A
blocked J is eaten outright and does not refresh the lockout, so mashing cannot
trap you in permanent recovery either. That is the trade this phase exists to
test: every swing you throw buys damage with a full second of no defense.

The enemy has `enemy_hp` HP (default 3). A landed **J** takes off
`attack_damage`, a successful counter takes off `counter_damage`, both default
`1`. The blow that empties the bar ends the fight: the label reads **FIGHT WON**,
holds through the usual recovery beat, then the enemy refills and the loop
continues so you can keep testing. That is true whichever verb landed it, so a
counter can end a fight and it reads FIGHT WON, not WIN. FIGHT WON does not
print an A/B letter, because it is not a read on this cycle's attack.

## Two ways to deal damage

Countering deals damage. Before, it only cancelled an attack, so the only way to
actually kill the enemy was to swing, and the only question the phase could ask
was "how much does swinging cost". Now both verbs advance the fight and the
choice between them is a real one:

- **Swing (J).** Fast. You can throw one every `player_attack_recovery` seconds
  and you do not have to wait for the enemy to do anything. It costs your
  defense for that whole second, and it **arms Vengeful**: the enemy rises,
  retaliates at a 0.72 s telegraph, and that retaliation cannot be cancelled.
- **Counter (SPACE / K).** Safe. It deals its damage without spending your
  defense first and it **never enrages the enemy**: no pose, no rage window, no
  shortened telegraph. What limits it is that you do not control the clock. You
  can only counter an attack the enemy chose to throw, and it chooses on a
  jittered `0.6-1.6` s idle gap plus a 1.2 s telegraph.

The enrage is a property of the **source** of the damage, not of taking damage,
which is why it lives at the two call sites rather than inside the shared damage
path. The rate limit on countering is the idle jitter, deliberately, not a
damage penalty: making the counter deal less would just re-answer the question
with arithmetic instead of with a decision.

You still die to a single enemy hit, so the safe verb is not free either. Waiting
for a wind-up you then misread is a loss, and a whole fight of waiting is a fight
you spend inside the enemy's tempo.

You still die to a single enemy hit, and **dying resets the fight**: the enemy
comes back at full HP and no longer vengeful. Otherwise trading your life for one
hit would be strictly profitable, and the fastest route to FIGHT WON would be to
die twice on purpose. That asymmetry is deliberate: the enemy needs three of
yours, you need one of its. FIGHT WON and **R** reset the same way, so a fresh
fight never starts with a rage window still running.

## Vengeful

The first trait, and the only one. Vengeful is a constraint, not a behaviour
pattern: it does not learn, adapt, or read you.

- **Trigger.** Deterministic, and it is your **swing** that does it. Every landed
  **J** sets `vengeful_left = vengeful_duration`. There is no roll and no
  condition: hit it with J, it is vengeful. A **counter never enrages it**, at
  any `counter_damage`. The enrage is a property of the verb you used, not of the
  enemy taking damage. A swing landed while it is *already* in the pose refreshes
  the rage window but does not restart the pose, so repeat hits cannot pin it
  there.
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
- **How you counter it.** Exactly like any other attack. The retaliation reuses
  attack A or attack B, picked by a fresh coin flip, and the counter mapping is
  unchanged and universal: **SPACE beats A, K beats B**. There is no third pose
  and no special input. The vengeful rise ramps out to baseline *before* the
  wind-up starts, so it never bleeds into the A/B coil, and on a vengeful cycle
  the A/B pose is **fully formed by the time the counter window opens** instead
  of half-built. The pose ramp is compressed into the part of the wind-up before
  the window; the timing is untouched. You get less time, not a worse picture.
- **Cancel, once.** A hit landed during a *normal* wind-up **cancels that
  attack**. The cue stops and no strike commits from it. The enemy rises into the
  pose and then throws a fresh, faster attack with a newly rolled A or B.
- **No second cancel.** **J whiffs for the whole vengeful wind-up.** The press is
  eaten, the recovery is still paid, and the retaliation comes anyway. You
  provoked that attack, so you have to counter it. This closes the loop
  play-testing found: every swing was landing inside the retaliation's wind-up
  and cancelling it, so aggression never had to pay for what it started. Whether
  a wind-up is vengeful is locked at the moment it starts, so the rule cannot
  flicker if the rage window expires while the enemy is already coiling.
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

Edit `tuning.json` at the repo root. Eleven keys, all numbers, plus one
optional twelfth (`seed`):

```json
{
  "telegraph_length": 1.2,
  "counter_window": 0.35,
  "camera_distance": 8.0,
  "windup_color_amount": 0.0,
  "windup_lean_amount": 2.0,
  "enemy_hp": 3,
  "counter_damage": 1,
  "attack_damage": 1,
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
- `enemy_hp` - integer `>= 1`, HP the enemy starts each fight with. Clamped up to
  1 (a 0-HP enemy would end the fight on the first frame you touched it).
- `counter_damage` - integer `>= 0`, HP a successful counter takes off. Floored
  at `0`, not at `1`, because "this verb deals no damage" is a legitimate
  experiment: set it to `0` to get the old behaviour back, where countering only
  cancelled the attack, and compare. Countering never enrages the enemy at any
  value.
- `attack_damage` - integer `>= 0`, HP one landed **J** takes off. Same floor and
  the same reason. At `0` a swing still costs your defense and still arms
  Vengeful, it just does not advance the fight, which is the cleanest way to feel
  what the swing is actually buying you.
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
current values, the enemy's remaining HP, both damage numbers, the resolved
counter window for both a normal and a vengeful wind-up, and a `VENGEFUL` readout while the rage window is
open. Missing file or a bad/missing key falls back to sane defaults
(1.2 / 0.35 / 8.0 / 1.0 / 1.0 / 3 / 1 / 1 / 1.0 / 2.5 / 0.6, seed random) and
keeps running.

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

### Experiment: do you ever choose to hold back and counter?

This is the question Phase 2 exists to answer. Both verbs deal damage, so both
are a way to win the fight, and the whole point is to find out whether the choice
between them is real or whether one is simply better. At the shipped values it
comes down to arithmetic you can do at the keyboard.

The two verbs are not symmetric, on purpose:

- **Swinging is faster.** One swing every `player_attack_recovery` seconds,
  whenever you want it. It costs your defense for that second and it arms
  Vengeful, and since **J** whiffs on a vengeful wind-up, the retaliation you
  bought is one you have to counter.
- **Countering is safe.** No enrage, no shortened telegraph, no defense spent up
  front. What it costs is control of the clock: you can only counter an attack
  the enemy chose to throw, on a `0.6-1.6` s jittered idle gap plus a 1.2 s
  telegraph. The jitter is what rate-limits the counter path, not a damage
  penalty.

Land a hit at `t = 0`. The enemy rises for 0.9 s and its retaliation commits at
1.62 s, with the counter window open from 1.27 s. Your own recovery ends at
1.0 s. So at 1.0 s you have a real choice, and it is not close to free either
way:

- **Hold back.** You are free at 1.0 s, well before the window opens at 1.27 s.
  Read A or B off the short wind-up, press the right counter, and you win the
  cycle without taking a hit.
- **Swing again.** You press **J** at 1.0 s, but the retaliation is already
  coiling and a vengeful wind-up cannot be cancelled, so the swing whiffs. No
  damage, and you are locked out again until 2.0 s. The strike commits at 1.62 s,
  inside that lockout. It hits you and you die. This is the half that used to be
  free: the same press used to delete the attack.

That is the dilemma stated in seconds. There is no jitter in it, so which way it
goes is your read, not the RNG. Play several fights and judge by hand:

1. Do you ever *choose* to hold back and counter instead of swinging, or is one
   of the two verbs still strictly better? If you always swing, the cost is too
   cheap: raise `player_attack_recovery`, or lower
   `vengeful_telegraph_multiplier`. If you always wait, swinging is not buying
   enough: the shipped answer is that it buys tempo, so check whether the idle
   jitter is actually making you wait.
2. Is the shortened telegraph readable at all, or does a vengeful attack feel
   unfair? If it is unreadable, the trait is a punishment rather than a
   constraint. Raise `vengeful_telegraph_multiplier` toward `1.0` until it is
   tight but fair.
3. Does the rise-and-tremble land as a warning, or does it just look like a third
   attack you should be countering? It is meant to say "the next one is fast",
   not "counter me now".
4. Does the wind-up cancel feel good or feel cheap? Punishing a normal wind-up
   removes an attack and speeds up the next one. You only get the one, because
   **J** whiffs on the retaliation, so the trade is: one attack deleted in
   exchange for a faster one you are committed to reading.

The honest failure mode to look for: if the fastest way to win is to mash **J**
from the opening, the decision does not exist. Three things prevent that, and if
it still feels free, one of them is mistuned. `player_attack_recovery` gates the
next swing as well as the counters, so hits cannot be chained faster than 1.0 s.
The retaliation out of the vengeful pose means the second hit in a chain is
answered at 1.62 s, inside the lockout the second hit bought. And **J** whiffs on
that retaliation, so the swing that used to cancel it now just spends your
defense and leaves the attack standing. Mashing does not race the enemy, it feeds
it.

Every other constant (idle jitter, strike speed, recovery time, the vengeful pose
length and shake, colors, camera angle) is hardcoded in `main.gd`, on purpose.

## Verification

The machine this was written on has no Godot binary, so **everything in Phase 2
is reviewed against Godot 4 conventions and is not runtime-confirmed**. That
includes both of the fixes on this page: the **J** whiff on vengeful wind-ups and
counter damage. Nothing below has been seen or heard running. Verify by hand in
the editor:

The four that matter most, because both fixes hang off them:

- **J** whiffs during a vengeful wind-up and your recovery is still paid for the
  whiff, and **J** still cancels a normal wind-up exactly as before.
- Counters deal damage, and a counter can land the killing blow: the label reads
  **FIGHT WON**, with no A/B letter after it, not the per-cycle **WIN**.
- The vengeful pose is distinct from both A and B at `windup_color_amount` `0.0`.
  It is the pose that has to carry it, so check it with color off.
- Neither pure-swinging nor pure-countering wins every fight. If either one does,
  the phase has the same problem it started with, just pointed the other way.

Phase 2 (player offense + Vengeful):

- **J** damages the enemy in idle, a normal wind-up, recovery and the vengeful
  pose, and whiffs during the strike and during a vengeful wind-up.
- **J** whiffs for the whole retaliation wind-up: press it there and the enemy
  keeps coiling, no hit registers, the HP count does not move, and your recovery
  is still spent (SPACE, K and J are all dead for `player_attack_recovery`
  seconds afterwards). A *normal* wind-up still cancels exactly as before.
- On a vengeful cycle the A or B pose is fully formed by the time the counter
  window opens, and there is no visual pop at the moment the strike commits.
- SPACE, K and J all do nothing for `player_attack_recovery` seconds after any J
  press, and a blocked counter does not consume the cycle's one counter attempt
  (you can still counter later in the same wind-up). Mashing J does not extend
  the lockout.
- Three hits produce **FIGHT WON**, it holds for the recovery beat, and the enemy
  comes back at full HP. The HUD's `left:` count matches what you have landed,
  and pressing J during the FIGHT WON hold does nothing.
- A successful counter takes `counter_damage` off the HUD's `left:` count, and
  the enemy does **not** go vengeful from it: no rise, no tremble, no `VENGEFUL`
  readout, and the next wind-up is full length. Counter three times in a row and
  the fight ends without the enemy ever being enraged.
- Mix the verbs: swing once, counter twice, and confirm the fight still ends at
  three and the FIGHT WON hold looks the same whichever verb landed last.
- Set `counter_damage` to `0`, press **R**, and countering goes back to cancelling
  the attack without advancing the fight. Set `attack_damage` to `0` and a swing
  still enrages the enemy while buying nothing. Both are experiments, not
  settings to ship.
- Dying resets the enemy to full HP and clears the rage window, so you cannot
  chip it down across deaths and a fresh fight never opens with a short
  telegraph. Same after FIGHT WON and after **R**.
- Repeat hits on an already-vengeful enemy do not restart the pose. It should
  always get back to idle and attack you, never be locked in place.
- Hitting the enemy mid-*normal*-wind-up cancels it: the tone stops, no strike
  lands, and it rises into the vengeful pose.
- The pose leads straight into a wind-up with no idle pause, and that retaliation
  is counterable. Land a hit, do nothing else, and confirm you can read A or B
  off the short wind-up and counter it. If you cannot, the trait is a punishment
  rather than a constraint.
- Land a hit, then press **J** again the moment your recovery clears: the swing
  whiffs into the retaliation wind-up and the strike reaches you while you are
  locked out. That failure should be legible as your choice, not as the enemy
  cheating.
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
