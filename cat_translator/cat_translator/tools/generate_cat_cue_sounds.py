#!/usr/bin/env python3
"""
냥냥이톡 "말 걸기" 기능용 신호음 합성 스크립트.

중요: 이 소리들은 실제 고양이 울음소리를 녹음하거나 "고양이 언어로 번역"한 것이
아니라, 고양이의 주의를 끌거나 편안하게 하는 데 도움이 될 수 있다고 알려진
특징(높은 피치의 짹짹거리는 소리 = 새끼를 부르는 소리와 유사해 주의를 끔,
낮고 느린 톤 = 안정감, 짧고 날카로운 소리 = 행동 중단 신호, 일관된 벨 소리 =
먹이 시간과 연결되는 조건화된 신호 등)을 참고해 직접 합성한 효과음이다.
저작권 문제가 없는 100% 합성 사인파 기반 WAV 파일이며, 실제 고양이 발성을
흉내 낸 것이 아님을 앱/문서 어디에서도 "번역"이라고 과장하지 않는다.

출력: assets/sounds/*.wav (44100Hz, mono, 16-bit PCM)
"""
import numpy as np
from scipy.io import wavfile
import os

SR = 44100
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "sounds")
os.makedirs(OUT_DIR, exist_ok=True)


def fade(signal, sr, attack_ms=8, release_ms=25):
    n = len(signal)
    a = max(1, int(sr * attack_ms / 1000))
    r = max(1, int(sr * release_ms / 1000))
    a = min(a, n // 2)
    r = min(r, n // 2)
    env = np.ones(n)
    env[:a] = np.linspace(0.0, 1.0, a)
    env[-r:] = np.linspace(1.0, 0.0, r)
    return signal * env


def tone(freq, duration_s, sr=SR, amp=0.6, attack_ms=8, release_ms=25, vibrato_hz=0.0, vibrato_depth=0.0):
    t = np.linspace(0, duration_s, int(sr * duration_s), endpoint=False)
    inst_freq = freq
    if vibrato_hz > 0:
        inst_freq = freq + vibrato_depth * np.sin(2 * np.pi * vibrato_hz * t)
        phase = 2 * np.pi * np.cumsum(inst_freq) / sr
        wave = np.sin(phase)
    else:
        wave = np.sin(2 * np.pi * freq * t)
    wave = fade(wave, sr, attack_ms, release_ms) * amp
    return wave


def chirp(f0, f1, duration_s, sr=SR, amp=0.6, attack_ms=5, release_ms=15):
    t = np.linspace(0, duration_s, int(sr * duration_s), endpoint=False)
    k = (f1 - f0) / duration_s
    phase = 2 * np.pi * (f0 * t + 0.5 * k * t ** 2)
    wave = np.sin(phase)
    wave = fade(wave, sr, attack_ms, release_ms) * amp
    return wave


def silence(duration_s, sr=SR):
    return np.zeros(int(sr * duration_s))


def normalize(signal, peak=0.85):
    m = np.max(np.abs(signal)) if len(signal) else 0
    if m == 0:
        return signal
    return signal / m * peak


def write_wav(name, signal):
    signal = normalize(signal)
    pcm16 = np.clip(signal * 32767, -32768, 32767).astype(np.int16)
    path = os.path.join(OUT_DIR, name)
    wavfile.write(path, SR, pcm16)
    dur = len(signal) / SR
    print(f"wrote {path}  ({dur:.2f}s)")


def build_call_attention():
    """부르기: 짹짹거리는 트릴 4회 반복 (새끼를 부르는 고주파 소리를 참고)."""
    parts = []
    for i in range(4):
        parts.append(chirp(1300, 2300, 0.11, amp=0.7, attack_ms=4, release_ms=20))
        parts.append(silence(0.07))
    return np.concatenate(parts)


def build_praise():
    """칭찬/애정: 낮은 허밍 + 완만한 AM(마치 그르렁거리는 느낌)과 끝에 살짝 올라가는 음."""
    t = np.linspace(0, 1.3, int(SR * 1.3), endpoint=False)
    carrier = np.sin(2 * np.pi * 180 * t)
    am = 0.55 + 0.45 * np.sin(2 * np.pi * 22 * t)  # 그르렁거리는 느낌의 저주파 변조
    purr = carrier * am
    purr = fade(purr, SR, 60, 200) * 0.55

    lilt = tone(420, 0.45, amp=0.35, attack_ms=20, release_ms=120, vibrato_hz=5, vibrato_depth=15)
    gap = silence(0.05)
    return np.concatenate([purr, gap, lilt])


def build_feeding_cue():
    """밥 시간: 밝은 두 음 벨소리 (일정하게 반복하면 식사 시간과 연결되는 신호가 됨)."""
    ding1 = tone(1046.5, 0.16, amp=0.75, attack_ms=3, release_ms=110)  # C6
    gap = silence(0.09)
    ding2 = tone(1396.9, 0.2, amp=0.75, attack_ms=3, release_ms=140)  # F6
    return np.concatenate([ding1, gap, ding2])


def build_warning():
    """안 돼/주의: 짧고 날카로운 버즈 (행동을 멈추게 하는 짧은 신호)."""
    dur = 0.22
    t = np.linspace(0, dur, int(SR * dur), endpoint=False)
    rng = np.random.default_rng(42)
    noise = rng.uniform(-1, 1, len(t))
    tone_part = np.sin(2 * np.pi * 180 * t)
    mix = 0.5 * noise + 0.5 * tone_part
    mix = fade(mix, SR, attack_ms=2, release_ms=60) * 0.8
    return mix


def build_calm():
    """안심: 느리고 낮은 톤 + 아주 완만한 비브라토로 안정감 있는 느낌."""
    low = tone(210, 2.4, amp=0.5, attack_ms=250, release_ms=500, vibrato_hz=3.2, vibrato_depth=4)
    sub = tone(105, 2.4, amp=0.25, attack_ms=300, release_ms=600)
    return low + sub


def build_play():
    """놀자: 통통 튀는 느낌의 짧은 음 4개 (장난기 있는 리듬)."""
    notes = [440.0, 523.25, 659.25, 784.0]  # A4, C5, E5, G5
    parts = []
    for f in notes:
        parts.append(tone(f, 0.09, amp=0.65, attack_ms=3, release_ms=40))
        parts.append(silence(0.045))
    return np.concatenate(parts)


def main():
    write_wav("call_attention.wav", build_call_attention())
    write_wav("praise.wav", build_praise())
    write_wav("feeding_cue.wav", build_feeding_cue())
    write_wav("warning.wav", build_warning())
    write_wav("calm.wav", build_calm())
    write_wav("play.wav", build_play())


if __name__ == "__main__":
    main()
