# Descent - Phase 4: the paired constraint

Not a game. This is a decision test built on the Phase 0 readability test: a bare
room, one enemy that telegraphs one of two attacks each cycle, two counters, and
one attack of your own. The A/B order is no longer a coin flip: it is a fixed
repeating sequence, and there is a visible beat before every one of them. On top
of that the enemy carries exactly one constraint, picked by `enemy_constraint`:
**Vengeful**, which retaliates for every hit you land, or **Adaptive**, which
counts *when* in the cycle you swing and stops rewarding the part you repeat.
Never both, so each paired fight is a clean measurement. You read which attack is
winding up and press its counter. You are judging:

1. Can you tell attack **A**'s wind-up from attack **B**'s in time to choose?
2. Does landing the right counter feel like a **read**, not a guess between two
   buttons?
3. Does hitting the enemy feel like it costs you something?
4. Both verbs deal damage now. Do you ever *choose* the slow safe one, or is one
   of the two strictly better?
5. The order is learnable by watching. Do you ever hold back a swing
   *specifically* to keep tracking the sequence?
6. Adaptive punishes repetition. Do you ever change your swing timing
   *specifically* because the enemy has learned the old one?

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
	 seed, refills the enemy's HP, restarts the sequence from step one, and
	 clears everything Adaptive has learned).

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

**J** lands a hit whenever the enemy is not already mid-strike and not winding
up a retaliation. It whiffs during the strike, because the strike is committed
and moving, and it whiffs for the whole of a vengeful wind-up, because that
attack is the one you provoked (see **Vengeful** below). Under
`enemy_constraint: "adaptive"` there is a third way to whiff: swinging in a part
of the cycle the enemy has already learned, which reads **WHIFF** on the label
unless the label is still holding an A/B reveal (see **Adaptive** below). Either
way the press puts you in recovery for `player_attack_recovery` seconds, and
while that is draining **SPACE, K and J all do nothing**. A blocked counter is
not consumed, it simply does not happen, so you cannot burn your one counter
attempt by mashing. A blocked J is eaten outright and does not refresh the
lockout, so mashing cannot trap you in permanent recovery either. That is the
trade this phase exists to test: every swing you throw buys damage with a full
second of no defense.

The enemy has `enemy_hp` HP (default 9). A landed **J** takes off
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
  `0.55-0.75` s guard beat plus a 1.2 s telegraph.

The enrage is a property of the **source** of the damage, not of taking damage,
which is why it lives at the two call sites rather than inside the shared damage
path. The rate limit on countering is the idle jitter, deliberately, not a
damage penalty: making the counter deal less would just re-answer the question
with arithmetic instead of with a decision.

You still die to a single enemy hit, so the safe verb is not free either. Waiting
for a wind-up you then misread is a loss, and a whole fight of waiting is a fight
you spend inside the enemy's tempo.

**Dying resets the fight**: the enemy comes back at full HP and no longer
vengeful. What it does **not** reset is your position in the sequence. The
pattern keeps running across deaths, so dying never buys you a free re-sync on it
(see **Methodical** below). Otherwise trading your life for one hit would be
strictly profitable, and the fastest route to FIGHT WON would be to trade a life
for every hit. That asymmetry is deliberate: the enemy needs nine of yours,
you need one of its. FIGHT WON resets HP and the rage window the same way, so a
fresh fight never starts with a short telegraph. **R** goes further: it re-reads
`tuning.json`, so it also restarts the sequence from the top along with the RNG.

## Vengeful

The first trait. Vengeful is a constraint, not a behaviour pattern: it does not
learn, adapt, or read you.

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
  a wind-up**, so getting hit buys the enemy a turn. It skips IDLE, which means
  it skips the **guard beat** as well: that missing beat is how you see, at a
  glance, that this attack is off-sequence (see **Methodical** below). At the
  shipped values the sequence after your hit is fixed: 0.9 s of rising and
  trembling, then a 0.72 s wind-up, so the strike commits 1.62 s after you
  connect and the counter window is `[1.27, 1.62]`. No idle gap and no jitter,
  because the whole point is that you can learn this timing.
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

## Methodical

The second trait, and the first *pattern* one. Methodical does not learn, adapt
or read you either. It just refuses to be random.

- **The sequence.** The A/B order is fixed and repeating, read from
  `methodical_sequence` (default `"AABAB"`). It loops forever: A, A, B, A, B, A,
  A, B, A, B... Nothing else about the attack changes, so **SPACE beats A, K
  beats B** exactly as before. What changes is that the next attack is knowable
  before the wind-up starts, if you have been counting.
- **The reset beat.** Every sequence attack is preceded by a visible beat: the
  enemy squares up, rolling side to side and settling level over
  `methodical_reset_time` (default 0.55 s). This is the existing IDLE state, not
  a new one, and the idle gap is now that beat plus at most 0.20 s of jitter. So
  the beat always finishes before the wind-up starts, and the rhythm is never a
  metronome.
- **Why the roll axis.** The square-up is a damped roll: side to side, settling
  to level. Nothing else in the game uses that axis. A rears back and tips away,
  B crouches and squashes, Vengeful rises tall and trembles sideways. The guard
  beat is the only motion on the roll, so it cannot be mistaken for a wind-up and
  it cannot bait a counter.
- **What it is for.** It gives the sequence a punctuation mark. Without a beat
  between attacks you are counting invisible events; with one, each attack is
  visibly step N of something.
- **The HUD does not print it.** `methodical_sequence` is deliberately kept off
  the info block, along with the current position in it and the next attack.
  Printing any of them would hand back the lookup table the trait exists to make
  you earn. The only ground truth is the post-cycle A/B letter on the result
  label, which is how you learn the sequence: by watching, one cycle at a time.

## Adaptive

The third trait, and the paired constraint to Vengeful. The two never run on the
same enemy: `enemy_constraint` picks one, so both fights are playable from the
same build, and `"adaptive"` is what ships. Like the other two, Adaptive is a
constraint rather than a behaviour pattern. It does not read your intent, it does
not choose its attacks differently, and it never touches the A/B mapping. All it
does is count.

- **What it is allowed to read.** Your **counter** choice is dictated by the
  enemy's attack, so it carries no repetition worth punishing: pressing SPACE on
  every A is not a habit, it is the correct answer. That leaves exactly two
  discretionary choices in this build, whether you swing and when, so a signature
  is a swing plus a coarse bucket for where in the cycle it landed. Never
  swinging at all is a signature too.
- **The four signatures.** Read from the enemy's state at the moment of an
  accepted **J** press. A press eaten by your own recovery lockout is not an
  action and records nothing.

  | Signature | Enemy state at the press |
  |---|---|
  | `GUARD` | `IDLE`, so during the guard beat |
  | `WINDUP` | `WINDUP` |
  | `AFTER` | `STRIKE`, `RECOVERY`, or the stance shift |
  | `PATIENCE` | no accepted swing anywhere in the cycle |

  The signature is your *choice*, not its outcome, so a press that whiffs still
  records. Combat inputs during a terminal **FIGHT WON** or **LOSE** hold are
  rejected before they spend recovery or mark a bucket. The legitimate killing
  swing still belongs to the completed cycle. `STRIKE` and `RECOVERY` are the tail of the cycle that just
  telegraphed. The stance shift is not: it starts *after* the cycle boundary has
  already counted, so a press during the lift is credited to the **following**
  cycle. It shares the `AFTER` bucket anyway, because every press needs a bucket
  and a press belonging to none would silently read as `PATIENCE`. A press during
  `STRIKE` has never been able to deal damage, so `AFTER` is in practice the
  recovery bucket.
- **Counting is per cycle, not per press.** A press only marks its bucket as
  seen. All the arithmetic happens once, at the end of the enemy's recovery: each
  bucket you used this cycle gains `1.0`, and every bucket you did not use decays
  to 40% of what it held. One cycle is therefore worth at most one point to any
  one bucket, however many times you press inside it, which is the only way
  "repeated for N cycles" can mean what it says.
- **What that makes safe.** A *strict* rotation of period *p*, one bucket per
  cycle and never two in a row, settles at `1 / (1 - 0.4^(p-1))`. Strict
  alternation between two buckets tops out at `1.67`, a three-way rotation at
  `1.19`, and both stay under any threshold of `2` or more, permanently. At such
  a threshold, varying your timing is not a trick that delays Adaptive, it is an
  answer that beats it outright. Swinging in the same bucket every cycle is the
  other end of that: 1, 2, 3, 4 and climbing without bound, so at a threshold of
  `3` it would trip on the third consecutive cycle **out of a cold bucket**.
- **What is safe at the shipped threshold.** `adaptive_threshold` ships at `1`,
  and no ceiling stays under that: one cycle in a bucket takes it to `1.0`, so
  any bucket you use adapts at that cycle's recovery exit. The swing lands the
  first time and whiffs the next time, unless the bucket was evicted in between.
  What a rotation has to beat here is `adaptive_capacity`, not the threshold.
  Each new adaptation pushes the oldest one off, so a strict rotation of period
  *p* lands every swing only if *p* is at least `adaptive_capacity + 1`, which is
  `3`: each bucket has been evicted by the time it comes back around. Alternating
  two buckets fills both slots, so from cold memory the third swing whiffs. There
  are only three press buckets, so in a rotation that swings every cycle, every
  third swing is a wind-up cancel. `PATIENCE` sits in the same list, so a cycle
  with no accepted swing adapts it and can take the third slot instead, at the
  price of a compressed guard beat while it is up. A whiffed swing is still an
  accepted press, so it keeps `PATIENCE` off.
- **What it does not make safe.** Activation is a test on the weight, not on a
  fresh run of cycles, so at a threshold of `2` or more a bucket still warm from
  a recent partial habit crosses sooner than `adaptive_threshold` consecutive
  cycles: `k` in a row is enough as soon as `k >= N - 0.4 * w`, where `w` is what
  the bucket held before them. That is what catches a duty cycle fatter than
  one-in-*p*, which the ceiling formula above says nothing about. A threshold-3
  example: swing twice and rest once in one bucket and the weight runs 1, 2, 0.8,
  1.8, 2.8, 1.12, 2.12, 3.12, adapting off the last **two** consecutive cycles.
  That is wanted, not a leak: "swing twice, rest once" is a habit, and the rule
  is that a habit eventually gets read. None of this can happen at the shipped
  `1`, where a single cycle always crosses, so a bucket that is not adapted
  always sits at exactly `0`.
- **Forming, capacity, eviction.** When a bucket's weight reaches
  `adaptive_threshold` it becomes active. `adaptive_capacity` (default `2`) caps
  how many can be active at once, and a new one **evicts the oldest**, whose
  weight is zeroed on the way out, so it has to be re-earned from zero and cannot
  re-cross without being used again. An active adaptation never expires on its
  own. Decay does not flush it, only a newer adaptation pushing it off the front
  does. So the way to get an adaptation off you is to build a different one,
  which means finding a third rhythm rather than going back to the first.
  `PATIENCE` takes a slot in the same list under the same cap and the same rule.
- **What an adaptation does to a swing.** Swing into an adapted bucket and the
  swing passes through. No damage, no flinch, no cancel, and the label reads
  **WHIFF**, unless the label is busy holding an A/B reveal (see below). The
  press still costs you `player_attack_recovery` seconds of defense, exactly as
  it always did, so an adapted habit is not blocked, it is priced. `PATIENCE`
  can never whiff anything, because it is not a press.
- **What an adapted `PATIENCE` does.** It compresses the guard beat by
  `adaptive_patience_guard_multiplier` (default `0.5`). Both halves scale
  together, the square-up pose and the idle gap that contains it, jitter
  included. At the shipped values a `0.55` s beat plus up to `0.20` s of jitter
  becomes `0.28` s plus up to `0.10` s, so the loop speeds up and the safe
  opening you were living in gets smaller. The wobble runs on beat *progress*
  rather than wall-clock seconds, so it completes the same square-up-and-settle
  and lands just as level in `0.28` s as it does in `0.55` s: a compressed beat
  is a faster beat, not a truncated one. That is the answer to pure defense.
  Countering costs nothing up front, so the only thing that can be charged for
  it is tempo.
- **The stance shift.** On any cycle where an adaptation forms, the enemy rises
  off the floor and settles back down over about `0.45` s before the next guard
  beat. A terminal result skips the stance and starts the next fight's guard;
  the completed cycle still activates learning at its recovery exit. No resolved
  hit is changed retroactively. In a living fight the shift signals learning. It is a lift, so
  it cannot be confused with anything else on screen: A rears back and tips away,
  B crouches and squashes, the guard beat rolls side to side and settles level,
  the vengeful pose stretches tall and trembles sideways. Nothing else in the
  game leaves the ground.
- **The cancel survives, the retaliation does not.** A hit landed during a normal
  wind-up still **cancels that attack**, the same as under Vengeful: the cue stops
  and no strike commits from it. What is different is what comes next. There is
  no rise-tall pose and no faster follow-up, the enemy just uncoils through its
  normal recovery, and the label reads **HIT** with no A/B letter after it.
  Revealing the letter of a wind-up that never landed would hand back the
  sequence step the swing was supposed to cost.
- **Two new labels, neither of which leaks anything.** **HIT** is a swing that
  cancelled a wind-up. **WHIFF** is a swing into an adapted bucket. Neither
  carries an A/B letter. Between the label, the HP `left:` count and the flinch
  you can always tell which of the two happened, and that is the readability
  guarantee Adaptive needs in place of Vengeful's visibly missing guard beat.
  One deliberate exception: a whiff during the enemy's recovery or its stance
  shift prints **nothing at all**, because the label is still holding that
  cycle's A/B reveal and the letter is the only ground truth you ever get on the
  sequence. The other two channels carry the read alone there, which they can, a
  landed swing flinches the enemy and moves `left:` and a whiff does neither.
- **Learning survives the fight.** Weights and active adaptations are not cleared
  by your death or by **FIGHT WON**. At `enemy_hp` 9 and the shipped threshold of
  `1`, a counter plus a poke into the enemy's recovery takes two HP on the first
  cycle and adapts `AFTER` at that cycle's recovery exit. The enemy is at 7 HP
  then, so the adaptation bites inside the fight that taught it. Persistence
  still matters, because per-fight learning would let a death wipe it. It is
  also the rule the sequence already follows: dying does not re-sync the thing
  you are being read on, so trading your life for a clean slate is not a move.
  **R** clears both.
- **The HUD does not print what it learned.** It shows `adaptive_threshold`,
  `adaptive_capacity`, `adaptive_patience_guard_multiplier` and a bare
  `active: N/M` count. It never shows which buckets are adapted and it never
  shows a weight, for the same reason it never shows `methodical_sequence`:
  working out which habit it caught is exactly what the whiff, the label and the
  stance shift exist to make you do. A count leaks no habit while still telling
  you an eviction is one adaptation away. `methodical_reset_time` keeps printing
  its tuned value too, never the compressed one, because that would give away
  that `PATIENCE` is up.

Counters are unchanged and unaffected. Adaptive never reads them, never whiffs
them, and **SPACE beats A, K beats B** at every point above.

## Arbitration: which system picks the next attack

Methodical picks every sequence attack under either constraint. What varies is
which other trait is sitting on top of it, and `enemy_constraint` is the only
thing that decides that, so the rule splits in two.

### Under `enemy_constraint: "vengeful"`

Two traits want to choose the same thing, so the rule between them is explicit.
All five parts of it:

1. **Vengeful is unchanged.** It still fires deterministically on a landed **J**
   hit, and it still shortens the next telegraph by
   `vengeful_telegraph_multiplier`. The counter window keeps its size.
2. **The retaliation is off-sequence.** It is a fresh coin flip, not the next
   step. You provoked it, so it is not part of the pattern you were tracking and
   it is not predictable from that pattern either.
3. **The retaliation does not advance the sequence, but interrupting one does.**
   With `methodical_resume` at its default `"next"`, the position advances the
   moment a *sequence* wind-up **begins**, and it is never rolled back. Cancel
   that wind-up with **J** and the step is still consumed: that attack never
   replays, and you have lost a step of the pattern you were counting. Landing a
   hit during the guard beat, when no wind-up is in flight, consumes no step.
   Both of those are intended, not bugs.
4. **`"restart"` is the harsh alternative.** Set `methodical_resume` to
   `"restart"` and the position is zeroed at the retaliation, so enraging the
   enemy throws away *all* positional knowledge and the sequence starts over from
   the top. `"next"` charges you one step for a swing; `"restart"` charges you
   the whole read.
5. **The handoff is visible.** The retaliation comes straight out of the vengeful
   pose with **no guard beat**, and every sequence attack is preceded by one. So
   you can always tell which system is speaking: beat then wind-up = the
   sequence, tremble then wind-up = the retaliation. The two impulses never
   blend.

The short version: **swinging costs you the read.** It already cost your defense
for `player_attack_recovery` seconds and bought an attack you cannot cancel. Now
it also spends a step of the pattern and inserts an unpredictable attack in the
middle of it.

### Under `enemy_constraint: "adaptive"`

Nothing enrages the enemy here, so there is no retaliation for four of those five
rules to act on. Rule 3 is the one that survives, and it survives unchanged.

- **Rules 1, 2, 4 and 5 are inoperative.** No hit shortens a telegraph (1). There
  is no off-sequence attack, because there is no retaliation to be off-sequence
  (2). `methodical_resume` never fires, because the only thing that reads it is
  the retaliation branch (4). And there is no vengeful-to-wind-up handoff left to
  be visible (5). `vengeful_duration` and `vengeful_telegraph_multiplier` are
  dead keys, the HUD stops printing them, and the `VENGEFUL` readout can never
  light. Every attack comes from the sequence, with no coin flips inserted in the
  middle of it, so the pattern is easier to count under Adaptive than it has ever
  been.
- **Rule 3 survives, and it is the whole arbitration.** The position still
  advances the moment a *sequence* wind-up **begins**, and it is still never
  rolled back. Cancel that wind-up with **J** and the step is still consumed:
  that attack never replays, and you have lost a step of the pattern you were
  counting. Landing a hit during the guard beat, with no wind-up in flight, still
  consumes no step. So swinging still costs you the read, and it costs it in a
  fight where the read is cleaner and therefore worth more.
- **The second price is on the timing, not on the next attack.** Adaptive's
  reply to a swing is not another attack. Cancelling wind-ups is close to free
  for exactly `adaptive_threshold` cycles **out of a cold `WINDUP` bucket**, which
  at the shipped `1` is a single cancel. At a threshold of `2` or more a warm
  bucket takes fewer. Learning is not cleared by your death or by FIGHT WON, so a
  second fight can start with `WINDUP` already adapted, and then its first cancel
  whiffs. A cancel buys 1.1 s of recovery, then a 0.55 to 0.75 s guard beat, then
  a 1.2 s telegraph, so about 2.9 to 3.1 s of quiet against a 1.0 s lockout. At
  the shipped threshold that cancel also adapts `WINDUP` at the recovery's exit,
  so the 0.45 s stance shift runs before the guard beat and the quiet is about
  3.3 to 3.5 s. Then the same press stops working. That line is the pure cancel,
  one HP a cycle and nothing else, so it stops with 8 of the enemy's 9 HP still
  up. Findings item 3 recorded aggression as *strictly* dominant. Here it is
  dominant and then priced.

The short version under Adaptive: **swinging costs you the read, and repeating
yourself costs you the swing.**

## Tuning

Edit `tuning.json` at the repo root. Eighteen keys, fifteen numbers and three
strings, plus one optional nineteenth (`seed`):

```json
{
  "telegraph_length": 1.2,
  "counter_window": 0.35,
  "camera_distance": 8.0,
  "windup_color_amount": 0.0,
  "windup_lean_amount": 2.0,
  "enemy_hp": 9,
  "counter_damage": 1,
  "attack_damage": 1,
  "player_attack_recovery": 1.0,
  "vengeful_duration": 2.5,
  "vengeful_telegraph_multiplier": 0.6,
  "methodical_sequence": "AABAB",
  "methodical_reset_time": 0.55,
  "methodical_resume": "next",
  "enemy_constraint": "adaptive",
  "adaptive_threshold": 1,
  "adaptive_capacity": 2,
  "adaptive_patience_guard_multiplier": 0.5
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
  1 (a 0-HP enemy would end the fight on the first frame you touched it). Shipped
  at `9`. Phase 3 raised it from `3` to `6`, because a fight has to outlast one
  full pass of the sequence or there is nothing to learn inside it. Phase 4
  raised it from `6` to `9` against the then-shipped `adaptive_threshold` of
  `3`, because counter-then-J takes two HP a cycle at the shipped damage and `9`
  is the smallest value where that line needs `adaptive_threshold + 2` cycles,
  five at that threshold, to kill by damage alone. At `6` it killed in the same
  recovery whose exit formed the `AFTER` adaptation, so the fight that taught it
  never played a cycle against it. At `9` and threshold `3` the enemy was at
  3 HP when `AFTER` adapted. At the shipped threshold of `1` it is at 7 HP, at
  cycle one's recovery exit. The HP is not derived from the threshold: change
  `adaptive_threshold` and `enemy_hp` stays where it is, which is why it stayed
  at `9` when the threshold moved to `1`.
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
- `methodical_sequence` - **string**. The repeating A/B order, default `"AABAB"`.
  Case-insensitive, and any character that is not an `A` or a `B` is ignored, so
  `"aabab"` and `"A-A-B-A-B"` parse identically. Parsed once at load, never per
  cycle. If it parses to nothing (empty string, `"xyz"`, wrong type, key missing)
  it falls back to `"AABAB"`, because a sequence of no attacks is not a pattern
  and every read of it would be out of range. Length is free: `"AB"` is a
  two-beat alternation, `"AAAB"` is a four-beat one with a tell at the end.
- `methodical_reset_time` - float `>= 0`, seconds of the guard beat that precedes
  every sequence attack, default `0.55`. The idle gap is this plus at most 0.20 s
  of jitter, so raising it slows the whole loop down. At `0.0` the beat vanishes
  and the sequence runs with no punctuation, which is the clean A/B test for
  whether the beat is doing anything.
- `methodical_resume` - **string**, `"next"` (default) or `"restart"`. Where the
  sequence picks up after a retaliation. See **Arbitration** above. Any other
  value, or the wrong type, falls back to `"next"`. Inert under
  `enemy_constraint: "adaptive"`, where no retaliation ever happens.
- `enemy_constraint` - **string**, `"adaptive"` (default) or `"vengeful"`. Which
  constraint this enemy carries on top of Methodical. Never both: an enemy that
  learns *and* retaliates is two experiments running at once and measures
  neither. Only the exact string `"vengeful"` opts out, so a typo, a number or a
  missing key lands on `"adaptive"`. Switching it takes a press of **R**, and
  that press also clears whatever Adaptive had learned, so a Vengeful fight can
  never start with a live adaptation on it. Under `"vengeful"` the build is
  Phase 3 exactly: no whiffs, no stance shift, no adaptive HUD lines.
- `adaptive_threshold` - integer `>= 1`, the weight one signature has to reach
  before the enemy adapts to it, default `1`. Because the count is a per-cycle
  seen-set, `N` is `N` consecutive cycles out of a **cold** bucket, so at `1` any
  bucket you use adapts at that cycle's recovery exit, and `PATIENCE` adapts
  after a single cycle with no accepted swing. At `2` or more a warm bucket takes
  fewer, because the test is on the accumulated weight and decay only takes a
  bucket to 40% a cycle: `k` consecutive cycles cross as soon as
  `k >= N - 0.4 * w`. So a duty cycle fatter than one-in-*p* is caught as well,
  by design. At those thresholds a strict rotation is *never* caught: alternating
  two buckets tops out at `1.67` and rotating three at `1.19`, permanently. At
  `1` the ceilings protect nothing, and what a rotation has to beat is
  `adaptive_capacity`: it lands every swing only if its period is at least
  `adaptive_capacity + 1`. Floored at `1`. Findings item 8 records the playtest
  at this value.
- `adaptive_capacity` - integer `>= 1`, how many adaptations can be live at once,
  default `2`. A new one evicts the oldest and zeroes its weight, so the evicted
  bucket becomes safe again and has to be re-earned from zero. At `1` the enemy
  can only hold one habit against you, so alternating two buckets is enough to
  keep flushing it, which is the cheapest way to feel the eviction rule working.
  Raise it to `4` and every bucket can be adapted at once, at which point there
  is nowhere left to move and the only safe play is to stop swinging, which
  `PATIENCE` then answers. Floored at `1`, not `0`: a capacity of `0` would evict
  every adaptation on the same boundary that formed it, leaving a stance shift
  that means nothing.
- `adaptive_patience_guard_multiplier` - float in `(0.0, 1.0]`, what the guard
  beat is multiplied by while `PATIENCE` is adapted, default `0.5`. The idle
  jitter scales with it, so the whole opening compresses rather than the pose
  and the gap coming apart. `1.0` means an adapted `PATIENCE` costs nothing,
  which is the clean A/B test for whether compressing the beat is doing any
  work. Clamped to `0.05` at the bottom, never `0`, because a zero-length beat
  would delete the punctuation the sequence is counted against. The risk to
  watch at `0.5`: the README already suspects `0.55` s is near the floor for a
  beat you can see, and `0.5` takes it to `0.28` s. If it reads as a flicker
  rather than a beat, raise this.
- `seed` - **optional**. Integer seed for the RNG that drives the A/B pick each
  cycle and the idle-gap jitter. Leave the key out (or set it `<= 0`) and every
  run randomizes, which is the default. Set it to a positive integer to replay
  the same A/B order and the same timing. Pressing **R** re-applies it, which
  restarts the sequence from the top. Parsed as an integer, a fractional value is
  truncated. The HUD prints `seed: random` when no override is in force.

Save the file, then press **R** in-game to apply them live. The HUD shows the
current values, the enemy's remaining HP, both damage numbers, `enemy_constraint`
and the resolved counter window. Only the live constraint's own keys are printed,
so the block stays the same height either way and never shows a number that
cannot do anything: under `"vengeful"` you get `vengeful_duration`,
`vengeful_telegraph_multiplier`, the vengeful counter window alongside the normal
one, and a `VENGEFUL` readout while the rage window is open, and under
`"adaptive"` you get the three adaptive keys and the `active: N/M` count instead.
It shows `methodical_reset_time` and `methodical_resume` but **never**
`methodical_sequence`, the position in it, or the next attack, and never which
signatures are adapted or any weight. Missing file or a
bad/missing key falls back to sane defaults (1.2 / 0.35 / 8.0 / 1.0 / 1.0 / 9 /
1 / 1 / 1.0 / 2.5 / 0.6 / "AABAB" / 0.55 / "next" / "adaptive" / 1 / 2 / 0.5,
seed random) and keeps running.

One caveat for a play session, and it now covers two learned things rather than
one: **R** re-reads `tuning.json`, so it silently re-syncs the pattern to step
one *and* clears every adaptive weight and active adaptation. Nothing on screen
says so, because the HUD shows neither the position nor which signatures were
caught. Tap **R** between fights to tweak a value and you have reset both of the
things the phase is trying to measure, which confounds any read on whether the
sequence is learnable *across* fights and any read on how Adaptive builds up over
one. Finish a measurement run before you touch it.

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
  the enemy chose to throw, on a `0.55-0.75` s guard beat plus a 1.2 s
  telegraph. The guard beat is what rate-limits the counter path, not a damage
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

### Experiment: do you ever hold back a swing to keep the read?

This is the question Phase 3 exists to answer, and it is the Phase 2 dilemma with
one more thing on the scale. Swinging already cost you a second of defense and
bought an attack you cannot cancel. Now it also costs you a step of the sequence:
the wind-up you cancelled is consumed and never replays, and the retaliation you
get instead is a coin flip that tells you nothing about where the pattern is.

Play several fights at the shipped values and judge by hand:

1. **Can you learn the sequence by watching?** Do not read it out of
   `tuning.json` first, that defeats the test. Play with the A/B letter on the
   result label and see whether you start pre-committing to a counter before the
   pose is readable. If you never do, either the sequence is too long, the fight
   is too short at `enemy_hp` 9, or the guard beat is not punctuating clearly
   enough to count against.
2. **Do you ever hold back a swing specifically to keep tracking it?** Not
   because you fear the retaliation, that was Phase 2. Because you know where you
   are in the pattern and swinging would throw that away. If the answer is never,
   the read is not worth enough: try `methodical_resume: "restart"`, which raises
   the price of one swing from a step to the whole pattern.
3. **Is the guard beat legible?** It should read as the enemy planting its feet
   and squaring up, distinct from A's rear-back, B's crouch and Vengeful's
   trembling rise. If it reads as a fourth wind-up you should be countering, the
   pose is wrong, not the timing.
4. **Is the handoff visible?** After you land a hit, the retaliation should
   arrive with no guard beat at all, and the next sequence attack after it should
   have one again. If you cannot see that difference, the arbitration rule is
   invisible and the trait is just noise.

The honest failure mode: if you can play the whole fight without ever counting,
the sequence is decoration. Either the guard beat is not marking the steps, or
0.55 s is too short to register as a beat, or `enemy_hp` 9 still is not long
enough to see `"AABAB"` come around twice.

### Experiment: do you ever change your timing because it learned the old one?

This is the question Phase 4 exists to answer, and Adaptive is the only trait
that can answer it. Set `enemy_constraint` to `"adaptive"`, press **R**, and play
several fights without reading the signature table above first. The mechanism is
meant to be inferable from play: you swing somewhere, it works once, then it
stops working, and the enemy lifts off the floor just before it stops.

Judge by hand:

1. **Do you ever change your swing timing specifically because the enemy has
   learned the old one?** Not because you are afraid of the wind-up, that was
   Phase 2, and not to hold your place in the sequence, that was Phase 3. Because
   the place you had been swinging stopped paying and you went looking for
   another one. From cold memory at nine HP, counter-then-J has the enemy at 7 HP
   when `AFTER` activates at cycle one's recovery exit, so the next post-counter
   J whiffs with fight left. Keep the habit and only the counters land, so the
   fight ends on cycle eight. Switch to a guard-beat swing plus the counter and
   that swing lands once before `GUARD` adapts too, so it ends on cycle seven.
   Rotating through all three press buckets from cycle two (a guard-beat swing
   plus the counter, then a wind-up cancel, then counter-then-J) ends it on cycle
   five. Keep the threshold at `1` and capacity at `2`. For a longer diagnostic
   replay, temporarily set `enemy_hp` to `12` and press **R** once, then keep
   using counter-then-hit until the enemy gives you a reason to change timing.
   Restore HP to `9` afterwards.
   This extends observation time, not normal combat balance. During recovery,
   watch the HP `left:` count and flinch because the A/B result owns the label.
2. **Can you tell *what* it learned, without being told?** You should be able to
   get from a run of whiffs to "it has my recovery-window swing", because the HUD
   refuses to say. If you can only ever tell that *something* was learned and
   never which thing, the feedback is too thin, and the first place to look is
   whether the stance shift is landing on the cycle you think it is.
3. **Does the stance shift read as learning, or as a fourth attack?** It should
   say "I have you", not "counter me now". If it baits a counter press, the pose
   is wrong rather than the timing.
4. **Is pure patience still playable?** Counter-only is the dominant line in the
   findings so far, and `PATIENCE` is the answer to it. Play a fight without
   pressing **J** once, then confirm the loop visibly speeds up after the first
   cycle, and that the compressed beat is *still legible as a beat* at `0.28` s.
   If it reads as a flicker, raise `adaptive_patience_guard_multiplier`. That is
   what the knob is for.
5. **Does eviction feel like an escape or like an accident?** With two
   adaptations live, build a third in a fresh bucket and go back to the oldest
   one. It should land again. The intended feel is that you bought that bucket
   back by changing twice, not that the enemy forgot.

The honest failure mode: if rotating your swing keeps every swing landing forever
with no thought behind it, Adaptive is not a constraint and the decision does not
exist. At the shipped threshold two buckets are not enough for that, since
alternation whiffs on the third swing. A rotation has to run through three, with
a wind-up cancel or a cycle with no swing as the third. Rotation beating the
counting rule is by design, not a bug, so the thing to measure is whether
rotating is something you have to notice and choose, or something your hands
were already doing before the enemy learned anything.

Every other constant (idle jitter, strike speed, recovery time, the guard-beat
roll and damping, the vengeful pose length and shake, the adaptive decay rate and
the lift of the stance shift, colors, camera angle) is hardcoded in `main.gd`, on
purpose. The decay is `0.4` rather than `0.5` deliberately: at `0.5` the
alternation ceiling is exactly `2.0`, which a threshold of `2` would reach by
float accumulation after about 53 cycles, so `0.4` is what keeps
`adaptive_threshold` honest across its whole range. At the shipped threshold of
`1` the decay has no effect on when anything adapts: a bucket you use reaches
`1.0` that cycle, and a bucket that is not adapted sits at exactly `0`. It
matters again from a threshold of `2` up.

## Verification

The earlier no-Godot handoff is historical. Adaptive has now run locally, and
the player reported "used counter then hit until it died" without changing
timing because of learning. That run did not pass the behavioral gate. A later
session at threshold `1`, the value that now ships, did pass it, for one player
in one session (findings item 8). The source-confirmed terminal-input repair
and deterministic Godot 4.7 results are recorded in findings item 7. Automated
checks establish mechanics, not whether the player notices the response or
chooses a new timing.

Run the arithmetic assertions and combat regressions with the installed Godot
4.7 executable:

```powershell
& 'C:/Users/super/Documents/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64_console.exe' --headless --path . --script tools/test_combat.gd
```

For the longer diagnostic only, temporarily set `enemy_hp` to `12` in
`tuning.json` and append `-- --diagnostic` to that command. Restore `9` after
the run. All other shipped tuning stays unchanged. The diagnostic checks that
the shipped threshold of `1` loaded, then runs its trace at a threshold of `3`
set inside the test. Visual and behavioral checks still need the player in the
editor:

Phase 4 (Adaptive), the four that matter most:

- **The stance shift is readable.** At `windup_color_amount` `0.0`, where the pose
  is all there is, the lift should be visible and should not be mistaken for A's
  rear-back, B's crouch, or the guard beat's roll. Check it on the `CapsuleMesh`
  import fallback as well as on the GLB, because the fallback is the worst case
  for a pose read.
- **An adapted swing visibly whiffs.** Swing in the same bucket
  `adaptive_threshold` times, watch for the shift, then swing there again. The HP
  `left:` count should not move, there should be no flinch, and your lockout
  should still be spent for `player_attack_recovery` seconds. Use the guard beat
  or the wind-up to see the **WHIFF** label as well: in the enemy's recovery and
  during the lift the label deliberately keeps that cycle's A/B reveal instead,
  so there the missing flinch and the frozen `left:` count are the whole tell.
  Judge the label's *color* here too: **WHIFF** at `(0.62, 0.58, 0.50)` sits only
  about `1.42:1` against the watching gray, well under the usual `3:1` for
  "reads as a different color", so confirm the warm cast is a real cue on your
  monitor and not one the words are carrying alone.
- **Varying your timing actually flushes an adaptation.** With two live, build a
  third in a fresh bucket and confirm the oldest one stops whiffing, so the
  bucket you were evicted out of is safe to use again. Then check what the
  shipped threshold of `1` does to rotation, from cold memory each time. Press
  **R**, rotate strictly through all three press buckets (a guard-beat swing
  plus the counter, a wind-up cancel, then counter-then-J) for a dozen cycles or
  more, and confirm every swing lands. Press **R** again, alternate two of those
  buckets, and confirm the third swing whiffs.
- **Pure patience is no longer free.** Counter only, for `adaptive_threshold`
  cycles, watch for the shift, and confirm the guard beat visibly shortens and
  the loop speeds up. The risk on this one is the other direction: confirm the
  compressed beat is still legible *as a beat* and not as a flicker. At the
  shipped `0.5` multiplier a `0.55` s beat becomes `0.28` s.

Also for Phase 4:

- Learning survives a death and a **FIGHT WON**, so an adaptation built in one
  fight is still on you in the next. **R** clears it.
- `enemy_constraint: "vengeful"` plus **R** restores Phase 3 exactly:
  retaliations, the short telegraph, the `VENGEFUL` readout, no whiffs, no lift,
  and no adaptive lines in the HUD.
- Under `"adaptive"` the `VENGEFUL` readout never lights, and every attack comes
  from the sequence, so there should be no off-sequence coin flips at all.
- Swinging still costs a sequence step: cancel a wind-up, confirm the label reads
  **HIT** with no A/B letter, and confirm the step you cancelled does not replay.
- Garbage in the four new keys (`""`, a number, a negative, `"xyz"`) plus **R**
  keeps the game running on the defaults.
- The HUD never reveals which signature is adapted, nor any weight, and the
  `methodical_reset_time` line keeps showing the tuned value even while the beat
  on screen is compressed.
- Nine hits in any mix of verbs still produce **FIGHT WON**.

Phase 3 (Methodical + arbitration), the four that matter most:

- **The sequence is learnable by watching.** Play without opening `tuning.json`
  and confirm the A/B letters on the result label repeat in a fixed order, and
  that you can eventually call the next one. Nothing in the HUD should have told
  you the order.
- **The guard square-up is visible and distinct.** It rolls side to side and
  settles level before every sequence attack, and it does not look like A, like
  B, or like the vengeful rise. Check it at `windup_color_amount` `0.0`, where
  the pose is all there is. No roll should leak into the wind-up, the strike, the
  vengeful pose or the recovery hold.
- **The retaliation visibly interrupts and hands back.** Land a hit and confirm
  the retaliation arrives out of the vengeful pose with **no** guard beat, and
  that the next sequence attack after it does have one. The two should never
  blend into one motion.
- **Swinging measurably costs the read.** Note where you are in the sequence,
  cancel a wind-up with **J**, and confirm the step you cancelled does not come
  back: after the retaliation the sequence resumes at the step *after* the one
  you interrupted. Then set `methodical_resume` to `"restart"`, press **R**, and
  confirm it instead resumes from the top.

Also for Phase 3:

- The retaliation's A/B is a coin flip, not the next sequence step: hit the enemy
  at the same position several times and confirm the retaliation letter varies.
- Landing a hit during the guard beat, with no wind-up in flight, costs no step:
  the sequence resumes exactly where it was.
- Set `methodical_sequence` to `""`, to `"zzz"`, or to a number, press **R**, and
  the game keeps running on `"AABAB"` rather than erroring. Set it to `"AB"` and
  confirm the shorter loop takes effect immediately without an index error.
- Set `methodical_reset_time` to `0.0` and the guard beat disappears while the
  sequence keeps running; raise it to `1.5` and the whole loop slows down.
- Nine hits, in any mix of verbs, produce **FIGHT WON**.

The four that matter most in Phase 2, because both fixes hang off them:

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
- Nine hits produce **FIGHT WON**, it holds for the recovery beat, and the enemy
  comes back at full HP. The HUD's `left:` count matches what you have landed,
  and pressing J during the FIGHT WON hold does nothing.
- A successful counter takes `counter_damage` off the HUD's `left:` count, and
  the enemy does **not** go vengeful from it: no rise, no tremble, no `VENGEFUL`
  readout, and the next wind-up is full length. Counter nine times in a row and
  the fight ends without the enemy ever being enraged.
- Mix the verbs: swing twice, counter seven times, and confirm the fight still
  ends at nine and the FIGHT WON hold looks the same whichever verb landed last.
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
- The A/B order is no longer driven by the RNG, so `seed` now only controls the
  idle-gap jitter and the retaliation's coin flip. With no `seed` key those
  differ between runs; adding `"seed": 20260726` replays them. The sequence
  itself repeats regardless of the seed, which is the point.
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
