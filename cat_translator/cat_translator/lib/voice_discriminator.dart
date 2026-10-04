import 'dart:math';

/// 사람 목소리 계열 YAMNet(AudioSet) 라벨 이름 모음 (공식 클래스 인덱스
/// 0~35, AudioSet 온톨로지의 "Human voice" 상위 카테고리 전체).
/// 사람이 고양이 소리를 흉내 낼 때도 결국 이 성대를 쓰기 때문에, 이 중
/// 하나라도 고양이 라벨과 비슷하거나 더 높은 점수를 받으면 "사람이 낸
/// 소리일 가능성이 높다"는 신호로 쓴다.
const Set<String> humanVoiceLabelNames = {
  'speech',
  'child speech, kid speaking',
  'conversation',
  'narration, monologue',
  'babbling',
  'speech synthesizer',
  'shout',
  'bellow',
  'whoop',
  'yell',
  'children shouting',
  'screaming',
  'whispering',
  'laughter',
  'baby laughter',
  'giggle',
  'snicker',
  'belly laugh',
  'chuckle, chortle',
  'crying, sobbing',
  'baby cry, infant cry',
  'whimper',
  'wail, moan',
  'sigh',
  'singing',
  'child singing',
  'synthetic singing',
  'rapping',
  'humming',
  'groan',
  'grunt',
  'whistling',
};

/// scores/labels 중 사람 목소리 라벨의 최고 점수를 뽑는다.
/// (고양이 라벨 점수와 같은 YAMNet 추론 결과에서 공짜로 얻을 수 있어
/// 추가 연산 비용이 거의 없다.)
double maxHumanVoiceScore(List<double> scores, List<String> labels) {
  double best = 0;
  for (int i = 0; i < scores.length && i < labels.length; i++) {
    final name = labels[i].toLowerCase().trim();
    if (humanVoiceLabelNames.contains(name) && scores[i] > best) {
      best = scores[i];
    }
  }
  return best;
}
// ---------------------------------------------------------------------
// 아주 가벼운 복소수 연산 (외부 패키지 없이 FFT / LPC 근 찾기에 사용).
// ---------------------------------------------------------------------
class Cplx {
  final double re;
  final double im;
  const Cplx(this.re, this.im);

  Cplx operator +(Cplx o) => Cplx(re + o.re, im + o.im);
  Cplx operator -(Cplx o) => Cplx(re - o.re, im - o.im);
  Cplx operator *(Cplx o) =>
      Cplx(re * o.re - im * o.im, re * o.im + im * o.re);
  Cplx operator /(Cplx o) {
    final d = o.re * o.re + o.im * o.im;
    if (d == 0) return const Cplx(0, 0);
    return Cplx((re * o.re + im * o.im) / d, (im * o.re - re * o.im) / d);
  }

  double get abs => sqrt(re * re + im * im);
  double get arg => atan2(im, re);
}

// ---------------------------------------------------------------------
// FFT (라디오-2, 길이는 2의 거듭제곱이어야 함) — purr 이중음화 판정용.
// ---------------------------------------------------------------------
void _fftInPlace(List<double> re, List<double> im) {
  final n = re.length;
  int j = 0;
  for (int i = 1; i < n; i++) {
    int bit = n >> 1;
    while (bit >= 1 && (j & bit) != 0) {
      j ^= bit;
      bit >>= 1;
    }
    j ^= bit;
    if (i < j) {
      final tr = re[i];
      re[i] = re[j];
      re[j] = tr;
      final ti = im[i];
      im[i] = im[j];
      im[j] = ti;
    }
  }
  for (int len = 2; len <= n; len <<= 1) {
    final ang = -2 * pi / len;
    final wr = cos(ang);
    final wi = sin(ang);
    final half = len ~/ 2;
    for (int i = 0; i < n; i += len) {
      double curWr = 1.0, curWi = 0.0;
      for (int k = 0; k < half; k++) {
        final ur = re[i + k];
        final ui = im[i + k];
        final vr = re[i + k + half] * curWr - im[i + k + half] * curWi;
        final vi = re[i + k + half] * curWi + im[i + k + half] * curWr;
        re[i + k] = ur + vr;
        im[i + k] = ui + vi;
        re[i + k + half] = ur - vr;
        im[i + k + half] = ui - vi;
        final nwr = curWr * wr - curWi * wi;
        final nwi = curWr * wi + curWi * wr;
        curWr = nwr;
        curWi = nwi;
      }
    }
  }
}
/// 그르렁(purr) 소리가 "이중음화(biphonation)" 특징을 보이는지 판정한다.
/// 고양이의 그르렁 소리는 성대(가성대/진성대)에서 서로 무관한 두 개의
/// 진동이 동시에 나는 경우가 많아, 정수비(배음) 관계가 아닌 두 개의
/// 강한 저주파 피크가 함께 나타난다. 사람이 흉내 낸 소리(허밍 등)는
/// 보통 기본 주파수 하나와 그 배음들만 나타난다.
///
/// 반환값: true=이중음화 확인됨(진짜 고양이일 가능성 높음),
///         false=단일 음원으로 보임(사람이 흉내 냈을 가능성),
///         null=판정 불가(피크가 뚜렷하지 않거나 소리가 너무 짧음).
/// 주의: 1차 근사 규칙이며, 실제 고양이/사람 녹음 샘플로 임계값을
/// 계속 보정해 나가야 한다.
bool? isPurrBiphonic(List<double> waveform, int sampleRate) {
  if (waveform.length < 512) return null;

  int n = 1;
  while (n < waveform.length) {
    n <<= 1;
  }
  if (n < 8192) n = 8192; // 저주파(20~800Hz) 구분을 위해 주파수 해상도를 충분히 확보.

  final re = List<double>.filled(n, 0.0);
  final im = List<double>.filled(n, 0.0);
  final len = waveform.length;
  for (int i = 0; i < len; i++) {
    final w = len > 1 ? 0.5 - 0.5 * cos(2 * pi * i / (len - 1)) : 1.0; // Hann
    re[i] = waveform[i] * w;
  }

  _fftInPlace(re, im);

  final half = n ~/ 2;
  final freqRes = sampleRate / n;
  final minBin = max(1, (20 / freqRes).round());
  final maxBin = min(half - 2, (800 / freqRes).round());
  if (maxBin <= minBin + 2) return null;

  final mags =
      List<double>.generate(half, (i) => sqrt(re[i] * re[i] + im[i] * im[i]));

  final peaks = <MapEntry<int, double>>[];
  for (int i = minBin + 1; i < maxBin; i++) {
    if (mags[i] > mags[i - 1] && mags[i] > mags[i + 1]) {
      peaks.add(MapEntry(i, mags[i]));
    }
  }
  if (peaks.length < 2) return null;

  peaks.sort((a, b) => b.value.compareTo(a.value));
  final top = peaks.take(6).toList();
  final p1 = top.first;
  if (p1.value <= 0) return null;

  const relThreshold = 0.3; // 비교 대상 피크가 1번 피크의 30% 이상이어야 의미있다고 봄.
  const harmonicTolerance = 0.06; // 정수배(배음)에서 6% 이내 오차는 "같은 음원의 배음"으로 간주.

  for (final p in top.skip(1)) {
    if (p.value < p1.value * relThreshold) continue;
    final f1 = p1.key * freqRes;
    final f2 = p.key * freqRes;
    final ratio = f2 > f1 ? f2 / f1 : f1 / f2;
    final nearestInt = max(1.0, ratio.roundToDouble());
    final deviation = (ratio - nearestInt).abs() / nearestInt;
    if (deviation > harmonicTolerance) {
      return true; // 배음 관계가 아닌 강한 저주파 피크 2개 -> 이중음화로 판단.
    }
  }
  return false; // 발견된 강한 피크들이 모두 배음 관계 -> 단일 음원으로 봄.
}
// ---------------------------------------------------------------------
// LPC(Linear Predictive Coding) 기반 포먼트 추출 — meow 흉내 판정 보조용.
// ---------------------------------------------------------------------

List<double> _autocorrelate(List<double> x, int maxLag) {
  final n = x.length;
  final r = List<double>.filled(maxLag + 1, 0.0);
  for (int lag = 0; lag <= maxLag; lag++) {
    double sum = 0;
    for (int i = 0; i < n - lag; i++) {
      sum += x[i] * x[i + lag];
    }
    r[lag] = sum;
  }
  return r;
}

/// Levinson-Durbin 재귀로 LPC 계수를 구한다. 반환값은 a[0]=1.0을 포함해
/// 길이 order+1 (즉 [1, a1, a2, ..., aOrder]).
List<double> _levinsonDurbin(List<double> r, int order) {
  final a = List<double>.filled(order + 1, 0.0);
  a[0] = 1.0;
  if (r[0] == 0) return a;
  double e = r[0];
  for (int i = 1; i <= order; i++) {
    double acc = r[i];
    for (int j = 1; j < i; j++) {
      acc += a[j] * r[i - j];
    }
    final k = -acc / e;
    final newA = List<double>.from(a);
    for (int j = 1; j < i; j++) {
      newA[j] = a[j] + k * a[i - j];
    }
    newA[i] = k;
    for (int j = 0; j <= i; j++) {
      a[j] = newA[j];
    }
    e *= (1 - k * k);
    if (e <= 1e-9) break;
  }
  return a;
}

/// Durand-Kerner(바이어슈트라스) 방법으로 다항식의 복소근을 구한다.
/// [coeffsHighToLow]는 최고차항부터 상수항까지 순서 (예: [1, a1, ..., aN]).
List<Cplx> _polynomialRoots(List<double> coeffsHighToLow) {
  final n = coeffsHighToLow.length - 1;
  if (n <= 0) return [];

  Cplx evalPoly(Cplx z) {
    Cplx result = const Cplx(0, 0);
    for (final c in coeffsHighToLow) {
      result = result * z + Cplx(c, 0);
    }
    return result;
  }

  // 초기값은 단위원에 가깝게(반지름 0.9) 잡아야 수렴이 잘 된다.
  // (반지름 0.4로 두면 실제 LPC 다항식에서 50회 반복으로는 수렴하지
  // 않아 포먼트가 엉뚱한 값으로 나오는 문제를 합성 신호 테스트로 확인함.)
  List<Cplx> roots = List.generate(n, (k) {
    final angle = 2 * pi * k / n + 0.5; // 대칭 배치로 인한 수렴 정체 방지용 오프셋.
    return Cplx(0.9 * cos(angle), 0.9 * sin(angle));
  });

  for (int iter = 0; iter < 50; iter++) {
    final newRoots = <Cplx>[];
    for (int i = 0; i < n; i++) {
      Cplx denom = const Cplx(1, 0);
      for (int j = 0; j < n; j++) {
        if (j != i) denom = denom * (roots[i] - roots[j]);
      }
      if (denom.abs() < 1e-12) {
        newRoots.add(roots[i]);
        continue;
      }
      newRoots.add(roots[i] - evalPoly(roots[i]) / denom);
    }
    roots = newRoots;
  }
  return roots;
}
/// waveform 중간 구간(32ms 프레임)에서 포먼트 주파수들(Hz, 오름차순)을
/// 뽑는다. 소리가 너무 짧거나 무음에 가까우면 빈 리스트를 반환한다.
List<double> estimateFormants(List<double> waveform, int sampleRate) {
  const frameMs = 32;
  final frameLen = (sampleRate * frameMs / 1000).round();
  if (waveform.length < frameLen) return const [];

  final start = (waveform.length - frameLen) ~/ 2;
  final frame = waveform.sublist(start, start + frameLen);

  // 프리엠퍼시스: 고주파를 살짝 강조해 포먼트가 더 뚜렷하게 드러나게 함.
  final pre = List<double>.filled(frame.length, 0.0);
  pre[0] = frame[0];
  for (int i = 1; i < frame.length; i++) {
    pre[i] = frame[i] - 0.97 * frame[i - 1];
  }

  final n = pre.length;
  for (int i = 0; i < n; i++) {
    pre[i] *= 0.54 - 0.46 * cos(2 * pi * i / (n - 1)); // Hamming window
  }

  final energy = pre.fold<double>(0, (s, v) => s + v * v);
  if (energy < 1e-6) return const []; // 거의 무음 -> 포먼트 추출 의미 없음.

  final order = (sampleRate / 1000).round() + 2; // 경험적 규칙 (16kHz -> 18차).
  final r = _autocorrelate(pre, order);
  final lpc = _levinsonDurbin(r, order); // [1, a1, ..., aOrder]

  final roots = _polynomialRoots(lpc);
  final freqs = <double>[];
  for (final root in roots) {
    if (root.im <= 0) continue; // 상반평면 근만 사용 (양의 주파수에 대응).
    final mag = root.abs;
    if (mag >= 0.995 || mag < 0.7) continue; // 단위원에 가깝고 과도하게 감쇠되지 않은 근만 포먼트로 인정.
    final freq = root.arg * sampleRate / (2 * pi);
    final bandwidth = -log(mag) * sampleRate / pi;
    if (freq > 90 && freq < sampleRate / 2 - 100 && bandwidth < 800) {
      freqs.add(freq);
    }
  }
  freqs.sort();
  return freqs;
}

/// 포먼트 간격(중앙값, Hz) — 성도 길이에 반비례하는 지표
/// (ΔF ≈ 음속 / (2 × 성도길이), Fitch 등 동물 음향학 연구에서 널리 쓰는
/// 식). 간격이 좁으면(사람 성인 성도 길이 ~17cm 기준 약 900~1200Hz 근처)
/// 사람 성도에서 난 소리, 간격이 그보다 훨씬 넓으면 고양이처럼 짧은
/// 성도에서 난 소리일 가능성이 높다고 본다.
///
/// 평균이 아니라 중앙값을 쓰는 이유: LPC 근 찾기 과정에서 가끔 섞여
/// 들어오는 가짜(허위) 포먼트 하나가 간격을 크게 왜곡할 수 있는데,
/// 중앙값은 이런 이상치 하나에 덜 민감하다 (합성 신호로 검증함).
double? formantDispersionHz(List<double> formants) {
  if (formants.length < 2) return null;
  final gaps = <double>[];
  for (int i = 1; i < formants.length; i++) {
    gaps.add(formants[i] - formants[i - 1]);
  }
  gaps.sort();
  final mid = gaps.length ~/ 2;
  if (gaps.length.isOdd) return gaps[mid];
  return (gaps[mid - 1] + gaps[mid]) / 2;
}

/// 이 값보다 포먼트 간격이 좁으면 "사람 성도에서 난 소리일 가능성이
/// 높다"고 본다. 사람 성인 평균 성도 길이(~17cm) 기준 추정 간격(~1000Hz)과
/// 고양이의 훨씬 짧은 성도 기준 추정 간격(~2300Hz) 사이의 중간값으로
/// 잡은 1차 근사치이며, 실제 고양이 녹음으로 검증/보정이 필요하다.
const double humanLikeFormantDispersionMaxHz = 1800.0;
