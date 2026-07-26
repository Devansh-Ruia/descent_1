# Descent - Phase 0 readability prototype

Not a game. This is a single readability test: a bare room, one enemy that
telegraphs one attack, and one counter. You are judging two things:

1. Can you tell the **wind-up** (telegraph) from the **commitment** (the strike)?
2. Does landing the counter feel like a **read**, not a coin flip?

## How to run

1. Open this folder as a project in **Godot 4.7** (Project Manager -> Import ->
   pick `project.godot`). First open imports the `.glb` assets. The `.wav`
   audio now loads at runtime (`AudioStreamWAV.load_from_file`), so it needs no
   import step.
2. Press **F5** (Play). The main scene is `main.tscn`.
3. Controls:
   - **SPACE** - counter. Press it inside the tail of the wind-up.
   - **R** - reload `tuning.json` live (also re-applies the camera distance).

The enemy loops forever: it waits, rears back and turns yellow while a rising
tone plays (the tell), then lunges. Counter during the tell's tail = WIN
(flash + label). Mistime it or do nothing = the strike lands (thud) = LOSE.
After each result it auto-resets so you can practice.

The wind-up cue now scales to `telegraph_length`: the fixed `windup.wav` is
played back stretched (via `pitch_scale`) so the rising tone spans the whole
wind-up and its peak lands on the strike commit at any length. Tradeoff:
`pitch_scale` also lowers the pitch at longer telegraphs, so the cue drifts
deeper as `telegraph_length` grows. Switch to in-engine synthesis if that drift
is ever unwanted.

## Tuning

Edit `tuning.json` at the repo root. Exactly five keys, all numbers:

```json
{
  "telegraph_length": 1.2,
  "counter_window": 0.35,
  "camera_distance": 8.0,
  "windup_color_amount": 1.0,
  "windup_lean_amount": 1.0
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
- `windup_lean_amount` - float `>= 0`, multiplies how far the enemy coils and
  leans back during the wind-up. `1.0` = current, higher = more exaggerated,
  `0.0` = no pose change. The strike lunge starts from this scaled pose, so
  there is no pop when you change it.

Both `windup_*` keys default to `1.0`, which is a no-op: leave them alone and
the wind-up looks exactly as before.

Save the file, then press **R** in-game to apply all five live. The HUD shows
the current values and the resolved window. Missing file or a bad/missing key
falls back to sane defaults (1.2 / 0.35 / 8.0 / 1.0 / 1.0) and keeps running.

### Experiment: does the wind-up read on pose alone?

To test whether the tell survives without color, set `windup_color_amount` to
`0.0` and `windup_lean_amount` to about `2.0`-`3.0`, save, press **R**, and
play. If the wind-up is still readable with no color change, the pose is
carrying the tell. If it stops reading, the tell was leaning on color.

Every other constant (idle jitter, strike speed, recovery time, colors, camera
angle) is hardcoded in `main.gd`, on purpose.

## Verification

The machine these fixes were written on has no Godot binary, so the audio fix
is reviewed against Godot 4 conventions, not runtime-confirmed. Verify it by
hand: run the project with sound on and confirm the wind-up cue fires during
the wind-up and the hit cue fires on the loss. Then run the pose experiment
above.

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
