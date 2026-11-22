"""Makes Earshot's test sound: a 32-second music-box tune (an original melody)."""
import sys
import wave

import numpy as np

RATE = 44100
LENGTH = 32.0
EIGHTH = 0.3125  # 96 BPM

# MIDI notes, None = rest. Two phrases, played A B A B A B' (30 seconds).
A = [76, 79, 81, 79, 76, 74, 72, None, 74, 76, 79, 76, 74, 72, 69, None]
B = [72, 74, 76, 79, 81, 84, 81, 79, 76, 79, 76, 74, 72, None, None, None]
B_END = [72, 74, 76, 79, 81, 84, 81, 79, 76, 74, 76, 79, 72, None, None, None]
MELODY = A + B + A + B + A + B_END
BASS = [48, 45, 41, 43]  # C, A minor, F, G: one every half bar


def freq(note):
    return 440.0 * 2 ** ((note - 69) / 12)


def bell(note, seconds, decay, partials, level):
    t = np.arange(int(seconds * RATE)) / RATE
    f = freq(note)
    tone = sum(amp * np.sin(2 * np.pi * f * ratio * t) for ratio, amp in partials)
    envelope = np.exp(-t / decay) * np.minimum(1, t / 0.004)
    return level * tone * envelope


def main(path):
    out = np.zeros(int(LENGTH * RATE))

    def add(start, signal):
        i = int(start * RATE)
        end = min(len(out), i + len(signal))
        out[i:end] += signal[: end - i]

    box = [(1, 1.0), (2, 0.35), (3, 0.12), (4.2, 0.05)]
    for index, note in enumerate(MELODY):
        if note is not None:
            add(index * EIGHTH, bell(note, 2.5, 0.45, box, 0.30))
    for index in range(len(MELODY) // 4):
        add(index * 4 * EIGHTH, bell(BASS[index % 4], 2.0, 0.8, [(1, 1.0), (2, 0.25)], 0.22))
    # The last note rings on; the tail fades out by the end of the file.
    tail = int((LENGTH - 2.0) * RATE)
    out[tail:] *= np.linspace(1, 0, len(out) - tail)

    out = np.tanh(out * 1.2) / np.tanh(1.2)  # gentle limiter
    out *= 0.7 / np.max(np.abs(out))  # peak at about -3 dB
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes((out * 32767).astype(np.int16).tobytes())


if __name__ == "__main__":
    main(sys.argv[1])
