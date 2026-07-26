# Descent - Phase 0 readability prototype

Not a game. This is a single readability test: a bare room, one enemy that
telegraphs one attack, and one counter. You are judging two things:

1. Can you tell the **wind-up** (telegraph) from the **commitment** (the strike)?
2. Does landing the counter feel like a **read**, not a coin flip?

## How to run

1. Open this folder as a project in **Godot 4.7** (Project Manager -> Import ->
   pick `project.godot`). First open imports the `.glb`/`.wav` assets.
2. Press **F5** (Play). The main scene is `main.tscn`.
3. Controls:
   - **SPACE** - counter. Press it inside the tail of the wind-up.
   - **R** - reload `tuning.json` live (also re-applies the camera distance).

The enemy loops forever: it waits, rears back and turns yellow while a rising
tone plays (the tell), then lunges. Counter during the tell's tail = WIN
(flash + label). Mistime it or do nothing = the strike lands (thud) = LOSE.
After each result it auto-resets so you can practice.

## Tuning

Edit `tuning.json` at the repo root. Exactly three keys, all numbers:

```json
{
  "telegraph_length": 1.2,
  "counter_window": 0.35,
  "camera_distance": 8.0
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

Save the file, then press **R** in-game to apply all three live. The HUD shows
the current values and the resolved window. Missing file or a bad/missing key
falls back to sane defaults (1.2 / 0.35 / 8.0) and keeps running.

Every other constant (idle jitter, strike speed, recovery time, colors, camera
angle) is hardcoded in `main.gd`, on purpose.

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
