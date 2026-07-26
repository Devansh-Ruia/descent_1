"""Synthesize Descent's two audio cues with SoX.

Run:  python tools/gen_audio.py

windup.wav - rising tonal tension cue (a sine sweeping up, with tremolo).
hit.wav    - short percussive thud (dropping low sine + a noise burst, mixed).
The two must sound obviously different: the tell is carried by sound as well as motion.
"""
import os
import subprocess

# Change this if SoX lives elsewhere.
SOX = r"C:\Users\super\AppData\Local\Microsoft\WinGet\Packages\ChrisBagwell.SoX_Microsoft.Winget.Source_8wekyb3d8bbwe\sox-14.4.2\sox.exe"

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "audio")
os.makedirs(OUT, exist_ok=True)


def sox(*args):
    subprocess.run([SOX, *args], check=True)


windup = os.path.join(OUT, "windup.wav")
hit = os.path.join(OUT, "hit.wav")

# 16-bit signed PCM so Godot's WAV importer reads it without fuss.
FMT = ("-b", "16", "-e", "signed-integer")

# windup: 200 -> 700 Hz rising sine, fade in/out, tremolo for building tension.
sox("-n", "-r", "44100", "-c", "1", *FMT, windup,
    "synth", "1.1", "sine", "200-700",
    "fade", "t", "0.05", "1.1", "0.2",
    "tremolo", "10", "30",
    "gain", "-n", "-3")

# hit: mix a dropping low sine (thump) with a fast-decaying noise burst.
thump = os.path.join(OUT, "_thump.wav")
noise = os.path.join(OUT, "_noise.wav")
sox("-n", "-r", "44100", "-c", "1", *FMT, thump,
    "synth", "0.22", "sine", "160-60",
    "fade", "t", "0", "0.22", "0.2",
    "gain", "-3")
sox("-n", "-r", "44100", "-c", "1", *FMT, noise,
    "synth", "0.10", "whitenoise",
    "fade", "t", "0", "0.10", "0.09",
    "gain", "-6")
sox("-m", thump, noise, *FMT, hit, "gain", "-n", "-2")
os.remove(thump)
os.remove(noise)

print("DONE audio ->", OUT)
