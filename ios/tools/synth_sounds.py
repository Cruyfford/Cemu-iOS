# Original menu music + UI sounds for the Cemu iOS frontend (procedurally synthesized).
import numpy as np, sys, os
from scipy.io import wavfile
from scipy.signal import fftconvolve

SR = 44100
OUT = sys.argv[1]
rng = np.random.default_rng(7)

def midi(n): return 440.0 * 2 ** ((n - 69) / 12)

def env(n, a, d, s, r, sus_len):
    a, d, r = int(a*SR), int(d*SR), int(r*SR)
    sus = max(int(sus_len*SR) - a - d, 0)
    e = np.concatenate([np.linspace(0,1,max(a,1)), np.linspace(1,s,max(d,1)), np.full(sus, s), np.linspace(s,0,max(r,1))])
    return e[:n] if len(e) >= n else np.pad(e, (0, n-len(e)))

def epiano(f, dur, vel=0.5):
    # FM electric piano: soft tine + bell partial
    n = int((dur + 1.2) * SR); t = np.arange(n) / SR
    mod_env = np.exp(-t * 6)
    mod = np.sin(2*np.pi*f*t) * (1.8 * mod_env + 0.3)
    car = np.sin(2*np.pi*f*t + mod)
    bell = np.sin(2*np.pi*f*4.0*t) * np.exp(-t*9) * 0.18
    amp = env(n, 0.004, 0.6, 0.35, 1.0, dur) * np.exp(-t*0.9)
    return (car + bell) * amp * vel

def marimba(f, dur, vel=0.5):
    n = int((dur + 0.6) * SR); t = np.arange(n) / SR
    x = np.sin(2*np.pi*f*t) * np.exp(-t*5) + 0.3*np.sin(2*np.pi*f*3.99*t)*np.exp(-t*14) + 0.1*np.sin(2*np.pi*f*9.2*t)*np.exp(-t*30)
    return x * vel * np.minimum(t/0.002, 1)

def bass(f, dur, vel=0.6):
    n = int((dur + 0.15) * SR); t = np.arange(n) / SR
    x = np.sin(2*np.pi*f*t) + 0.25*np.sin(2*np.pi*2*f*t)*np.exp(-t*4)
    return np.tanh(1.3*x) * env(n, 0.006, 0.15, 0.7, 0.12, dur) * vel

def whistle(f, dur, vel=0.35):
    # soft flute/whistle lead with vibrato
    n = int((dur + 0.25) * SR); t = np.arange(n) / SR
    vib = 1 + 0.006*np.sin(2*np.pi*5.2*t) * np.minimum(t/0.35, 1)
    ph = 2*np.pi*np.cumsum(f*vib)/SR
    x = np.sin(ph) + 0.12*np.sin(2*ph) + 0.03*rng.standard_normal(n) * env(n, 0.02, 0.05, 0.2, 0.1, dur)
    return x * env(n, 0.04, 0.1, 0.8, 0.2, dur) * vel

def shaker(dur, vel=0.12):
    n = int(dur*SR); t = np.arange(n)/SR
    x = rng.standard_normal(n); x = np.diff(np.concatenate([[0], x]))  # brighten
    return x * np.exp(-t*45) * vel

def kick(vel=0.5):
    n = int(0.3*SR); t = np.arange(n)/SR
    f = 50 + 70*np.exp(-t*30)
    return np.sin(2*np.pi*np.cumsum(f)/SR) * np.exp(-t*12) * vel

def snap(vel=0.25):
    n = int(0.18*SR); t = np.arange(n)/SR
    return (rng.standard_normal(n)*np.exp(-t*35) + 0.4*np.sin(2*np.pi*1800*t)*np.exp(-t*60)) * vel

def place(buf, x, start):
    i = int(start*SR)
    if i >= len(buf): return
    m = min(len(x), len(buf) - i)
    buf[i:i+m] += x[:m]

def reverb(x, secs=2.2, mix=0.25):
    n = int(secs*SR); t = np.arange(n)/SR
    ir = rng.standard_normal(n) * np.exp(-t*3.2)
    ir[:int(0.012*SR)] = 0
    wet = fftconvolve(x, ir)[:len(x)]
    wet /= (np.max(np.abs(wet)) + 1e-9) / (np.max(np.abs(x)) + 1e-9)
    return x*(1-mix) + wet*mix

def stereo(l, r): return np.stack([l, r], axis=1)

def save(name, x, peak=0.85):
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    wavfile.write(os.path.join(OUT, name), SR, (x*32767).astype(np.int16))

# ---------------- music ----------------
BPM = 104; beat = 60/BPM; bar = 4*beat
# original progression in F major, 16 bars
prog = [
    ("F",  [53, 57, 60, 64, 67]),  # Fmaj9
    ("Dm", [50, 57, 60, 64, 65]),  # Dm9
    ("Gm", [55, 58, 62, 65, 69]),  # Gm9
    ("C",  [48, 58, 62, 65, 67]),  # C9sus
    ("Bb", [46, 57, 62, 65, 69]),  # Bbmaj7
    ("Am", [45, 55, 60, 64, 67]),  # Am7
    ("Gm", [43, 58, 62, 65, 69]),  # Gm9
    ("C",  [48, 58, 64, 67, 70]),  # C7
]
bass_roots = {"F":41, "Dm":38, "Gm":43, "C":36, "Bb":34, "Am":45}
chords = prog + prog
nbars = len(chords)
L = nbars*bar
music_l = np.zeros(int((L+3)*SR)); music_r = np.zeros_like(music_l)
drums = np.zeros_like(music_l)

for bi, (name, notes) in enumerate(chords):
    t0 = bi*bar
    # comping: syncopated epiano stabs
    for off, length, v in [(0, 1.4, 0.32), (1.5, 0.45, 0.22), (2.5, 1.3, 0.27)]:
        for k, nte in enumerate(notes[1:]):
            x = epiano(midi(nte), length*beat, v * (0.9 if k % 2 else 1))
            pan = 0.35 + 0.1*k
            place(music_l, x*(1-pan), t0 + off*beat + 0.006*k)
            place(music_r, x*pan, t0 + off*beat + 0.006*k)
    # bass: root, fifth, walk
    r = bass_roots[name]
    for off, nt, ln in [(0, r, 1.4), (1.5, r+7, 0.45), (2.0, r+12, 0.9), (3.0, r+7, 0.4), (3.5, r+5 if bi % 2 else r+10, 0.4)]:
        x = bass(midi(nt), ln*beat, 0.55)
        place(music_l, x*0.5, t0+off*beat); place(music_r, x*0.5, t0+off*beat)
    # drums: light kick, rim snap, shaker 8ths
    place(drums, kick(0.45), t0); place(drums, kick(0.35), t0 + 2.5*beat)
    place(drums, snap(0.16), t0 + 1*beat); place(drums, snap(0.16), t0 + 3*beat)
    for e in range(8):
        place(drums, shaker(0.12, 0.05 if e % 2 else 0.08), t0 + e*beat/2)

# original melody (beats, midi, length) — first 8 bars marimba, second 8 bars whistle
mel = [
 (0,72,1),(1,74,0.5),(1.5,76,1.5),(3.5,72,0.5),
 (4,74,1),(5,72,0.5),(5.5,69,2),
 (8,70,1),(9,72,0.5),(9.5,74,1),(10.5,77,1.5),
 (12,76,1),(13,74,0.5),(13.5,72,2.5),
 (16,69,0.5),(16.5,72,0.5),(17,76,1),(18,77,0.5),(18.5,76,1.5),
 (20,72,1),(21,69,1),(22,72,2),
 (24,70,1),(25,69,0.5),(25.5,67,1),(26.5,70,1.5),
 (28,72,1),(29,74,1),(30,76,2),
]
for (b, n, ln) in mel:
    x = marimba(midi(n), ln*beat, 0.30)
    place(music_l, x*0.6, b*beat); place(music_r, x*0.4, b*beat)
mel2 = [(b+32, n + (0 if i % 5 else 0), ln) for i, (b, n, ln) in enumerate(mel)]
for (b, n, ln) in mel2:
    x = whistle(midi(n), ln*beat*0.95, 0.20)
    place(music_l, x*0.45, b*beat); place(music_r, x*0.55, b*beat)
    y = marimba(midi(n+12), 0.3, 0.06)
    place(music_l, y*0.3, b*beat); place(music_r, y*0.7, b*beat)

mix_l = reverb(music_l, 2.4, 0.22) + drums*0.8
mix_r = reverb(music_r, 2.4, 0.22) + drums*0.8
# seamless loop: fold the tail past the loop point back onto the start
n = int(L*SR)
for ch in (mix_l, mix_r):
    tail = ch[n:]
    ch[:len(tail)] += tail
song = stereo(mix_l[:n], mix_r[:n])
save("menu_music.wav", song, 0.7)

# ---------------- UI sounds ----------------
def chime(notes, gap, dur=0.35, vel=0.5, bright=1.0):
    total = int((gap*len(notes) + dur + 0.6)*SR)
    b = np.zeros(total)
    for i, nt in enumerate(notes):
        place(b, marimba(midi(nt), dur, vel)*0.7 + epiano(midi(nt+12), dur*0.6, vel*0.25*bright)[:int((dur+0.6)*SR)], i*gap)
    return reverb(b, 1.0, 0.2)

save("ui_tap.wav", chime([84], 0, 0.12, 0.5, 0.6)[:int(0.35*SR)], 0.55)
save("ui_select.wav", chime([79, 86], 0.055, 0.2, 0.5), 0.6)
save("ui_back.wav", chime([86, 79], 0.055, 0.2, 0.45), 0.5)
save("ui_toggle.wav", chime([91], 0, 0.08, 0.4, 0.4)[:int(0.25*SR)], 0.4)
save("ui_open.wav", chime([77, 81, 84], 0.045, 0.22, 0.45), 0.55)
# launch: rising sparkle arpeggio + soft swell
launch = chime([65, 69, 72, 76, 79, 84, 88], 0.06, 0.5, 0.45)
tl = np.arange(len(launch))/SR
swell = np.sin(2*np.pi*midi(53)*tl)*np.minimum(tl/0.25,1)*np.exp(-tl*2.5)*0.25
save("ui_launch.wav", reverb(launch + swell, 1.8, 0.3), 0.7)
save("ui_error.wav", chime([70, 66], 0.09, 0.25, 0.45, 0.3), 0.5)
print("ok", len(song)/SR)
