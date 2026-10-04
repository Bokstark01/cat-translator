import 'dart:math';
import 'cat_situation.dart';
import 'voice_discriminator.dart';

/// YAMNet(AudioSet) 라벨 중 고양이 소리와 관련된 하위 분류.
/// (업무보고서 1,2에서 조사한 고양이 발성 연구를 바탕으로 한 1차 규칙)
enum CatSubLabel { purr, hiss, growl, caterwaul, meow, generalCat, none }

class AudioFeatures {
  final double rms; // 음량 (0~1 근처로 정규화된 평균 에너지)
  final double pitchHz; // 추정 음높이 (영교차율 기반 근사치)
  final double durationMs; // 이번 발성이 이어진 길이
  final int repetitionCount; // 최근 몇 초 내 반복 횟수
  final int hourOfDay; // 0~23

  AudioFeatures({
    required this.rms,
    required this.pitchHz,
    required this.durationMs,
    required this.repetitionCount,
    required this.hourOfDay,
  });
}

/// YAMNet 점수 벡터 + 라벨 목록에서 "고양이 관련 하위 라벨"과 신뢰도를 뽑아낸다.
/// 사람이 고양이 소리를 흉내 낸 경우를 걸러내기 위한 진단 정보도 함께
/// 담는다 (humanVoiceScore / isPurrBiphonic / formantDispersionHz).
class CatLabelResult {
  final CatSubLabel subLabel;
  final double confidence;
  final bool isCatSound;
  // --- 아래는 "사람이 흉내낸 소리" 판별용 진단 정보 (디버깅/피드백 로깅용) ---
  final double humanVoiceScore; // 같은 추론에서 나온 사람 목소리 계열 최고 점수.
  final bool? isPurrBiphonic; // purr일 때만 계산됨. null=판정 불가.
  final double? formantDispersionHz; // meow 계열 애매한 경우에만 계산됨.

  CatLabelResult(
    this.subLabel,
    this.confidence,
    this.isCatSound, {
    this.humanVoiceScore = 0,
    this.isPurrBiphonic,
    this.formantDispersionHz,
  });
}

/// 사람 목소리 점수가 고양이 점수의 이 비율 이상이면 "사람이 낸 소리"로
/// 보고 거부한다. 1.0이면 사람 목소리 점수가 고양이 점수를 넘어서야만
/// 거부하는 것이고, 1.0보다 작을수록(여기서는 0.9) 더 보수적으로(사람
/// 쪽에 더 유리하게) 판정한다 — 사람이 흉내 낸 "야옹" 소리는 보통
/// Speech/Shout류 점수가 Meow 점수보다 훨씬 높게 나오기 때문에, 비슷한
/// 수준이기만 해도 의심하는 쪽이 오탐을 줄이는 데 유리하다.
const double _humanVoiceRejectionRatio = 0.9;

CatLabelResult pickCatSubLabel(
  List<double> scores,
  List<String> labels,
  List<double> waveform,
  int sampleRate,
) {
  // AudioSet(YAMNet) 라벨 중 고양이와 직접 관련된 항목들.
  const purrNames = {"purr"};
  const hissNames = {"hiss"};
  const growlNames = {"growling"};
  const caterwaulNames = {"caterwaul"};
  const meowNames = {"meow"};
  const generalCatNames = {"cat", "domestic animals, pets"};

  double bestScore = 0;
  CatSubLabel bestLabel = CatSubLabel.none;
  double humanVoiceScore = 0;

  for (int i = 0; i < scores.length && i < labels.length; i++) {
    final name = labels[i].toLowerCase().trim();
    final score = scores[i];
    CatSubLabel? candidate;
    if (purrNames.contains(name)) {
      candidate = CatSubLabel.purr;
    } else if (hissNames.contains(name)) {
      candidate = CatSubLabel.hiss;
    } else if (growlNames.contains(name)) {
      candidate = CatSubLabel.growl;
    } else if (caterwaulNames.contains(name)) {
      candidate = CatSubLabel.caterwaul;
    } else if (meowNames.contains(name)) {
      candidate = CatSubLabel.meow;
    } else if (generalCatNames.contains(name)) {
      candidate = CatSubLabel.generalCat;
    } else if (humanVoiceLabelNames.contains(name)) {
      // 같은 추론 결과 안에서 "사람 목소리" 계열 최고 점수도 함께 추적.
      // (사람이 고양이 소리를 흉내 내도 결국 이 라벨들 중 하나가
      // 같이 높게 나오는 경우가 많다.)
      if (score > humanVoiceScore) humanVoiceScore = score;
    }
    if (candidate != null && score > bestScore) {
      bestScore = score;
      bestLabel = candidate;
    }
  }

  // 임계값: 너무 낮으면 "고양이 소리 아님"으로 처리.
  const threshold = 0.15;
  bool isCat = bestScore >= threshold && bestLabel != CatSubLabel.none;

  // 1차 필터: 사람 목소리 라벨이 고양이 라벨과 비슷하거나 더 우세하면
  // 바로 "사람이 낸 소리"로 보고 거부한다. (추가 연산 없이 같은
  // YAMNet 출력만으로 판정 가능 — 가장 비용 대비 효과가 큰 필터.)
  if (isCat && humanVoiceScore >= bestScore * _humanVoiceRejectionRatio) {
    isCat = false;
  }

  bool? purrBiphonic;
  double? dispersion;

  if (isCat && bestLabel == CatSubLabel.purr) {
    // 2차 필터(purr 전용): 그르렁 소리의 이중음화(biphonation) 여부로
    // 한 번 더 검증한다. 사람이 흉내 낸(허밍 등) 소리는 거의 항상
    // 단일 음원(배음 구조)만 보이는 반면, 진짜 고양이 그르렁은
    // 독립된 두 진동이 겹치는 경우가 많다. 판정이 애매하면(null)
    // 보수적으로 그대로 둔다 — 잘못 걸러내는 것보다는 낫다고 봄.
    purrBiphonic = isPurrBiphonic(waveform, sampleRate);
    if (purrBiphonic == false && humanVoiceScore > 0.05) {
      isCat = false;
    }
  }

  if (isCat &&
      (bestLabel == CatSubLabel.meow ||
          bestLabel == CatSubLabel.generalCat) &&
      humanVoiceScore >= bestScore * 0.5 &&
      humanVoiceScore < bestScore * _humanVoiceRejectionRatio) {
    // 2차 필터(meow 전용): 사람 목소리 점수가 "꽤 있지만 아직 1차
    // 필터 기준까지는 아닌" 애매한 구간에서만, 조금 더 무거운
    // 포먼트 간격 분석을 추가로 돌려본다. (매 윈도우마다 돌리지
    // 않고 애매할 때만 계산해 배터리 소모를 아낀다.)
    final formants = estimateFormants(waveform, sampleRate);
    dispersion = formantDispersionHz(formants);
    if (dispersion != null && dispersion < humanLikeFormantDispersionMaxHz) {
      isCat = false;
    }
  }

  return CatLabelResult(
    bestLabel,
    bestScore,
    isCat,
    humanVoiceScore: humanVoiceScore,
    isPurrBiphonic: purrBiphonic,
    formantDispersionHz: dispersion,
  );
}
/// 고양이 소리임이 확인된 뒤, 하위 라벨 + 음향 특징으로
/// 12가지 상황 중 하나로 매핑한다. (규칙 기반 1차 버전)
///
/// 참고: 이 규칙은 보고서 1/2에서 정리한 학계 연구와 MeowTalk류 선행
/// 서비스의 분류 기준을 바탕으로 만든 1차 근사치이며, 추후 자체 데이터로
/// 학습한 모델로 교체/보완할 예정입니다 (로드맵 2단계).
CatSituation mapToSituation(CatSubLabel subLabel, AudioFeatures f) {
  switch (subLabel) {
    case CatSubLabel.purr:
      // 그르렁 소리: 보통 편안함, 단 아플 때도 그르렁거리는 경우가 있어
      // 아주 길고(>8초) 낮은 에너지로 반복되면 고통 신호로도 본다.
      if (f.durationMs > 8000 && f.rms < 0.2) {
        return CatSituation.pain;
      }
      return CatSituation.content;

    case CatSubLabel.hiss:
      // 하악질: 에너지가 매우 높으면 위협, 낮으면 두려움/방어.
      return f.rms > 0.5 ? CatSituation.threatTerritory : CatSituation.fearDefense;

    case CatSubLabel.growl:
      // 으르렁: 반복/지속되면 다른 고양이와의 다툼, 1회성이면 경계.
      return f.repetitionCount >= 2 ? CatSituation.fighting : CatSituation.threatTerritory;

    case CatSubLabel.caterwaul:
      // 길게 뽑는 울음: 피치가 불규칙하게 크게 흔들리면 싸움, 비교적
      // 일정하게 긴 울음이면 발정기 신호로 본다.
      return f.pitchHz > 900 ? CatSituation.mating : CatSituation.fighting;

    case CatSubLabel.meow:
    case CatSubLabel.generalCat:
      return _mapMeow(f);

    case CatSubLabel.none:
      return CatSituation.unknown;
  }
}

CatSituation _mapMeow(AudioFeatures f) {
  // 분석 창이 ~1초 단위라서 durationMs는 "같은 발성이 몇 초째 이어지고
  // 있는지"(1초 단위 누적값)로 들어온다. 이를 초 단위로 환산해서 사용.
  final isNight = f.hourOfDay >= 22 || f.hourOfDay < 6;
  final streakSeconds = (f.durationMs / 1000).round();

  // 밤에 2초 이상 이어지며 반복도 잦음 -> 야간 울음/분리불안.
  if (isNight && f.repetitionCount >= 3 && streakSeconds >= 2) {
    return CatSituation.nightYowling;
  }

  // 짧은 소리가 쉴 새 없이 여러 번 반복 -> 채터링(사냥 본능).
  if (f.repetitionCount >= 5 && streakSeconds <= 1) {
    return CatSituation.huntingChatter;
  }

  // 아주 높은 피치로 짧게 -> 새끼를 부르거나 새끼가 부르는 소리.
  if (f.pitchHz > 1000 && streakSeconds <= 1 && f.repetitionCount <= 2) {
    return CatSituation.motherKitten;
  }

  // 에너지 낮게 2초 이상 길게 끄는 소리 -> 고통/아픔 가능성.
  if (streakSeconds >= 2 && f.rms < 0.18) {
    return CatSituation.pain;
  }

  // 반복이 잦고(2회 이상) 에너지가 큼 -> 배고픔/밥 요구.
  if (f.repetitionCount >= 2 && f.rms > 0.3) {
    return CatSituation.hungry;
  }

  // 짧게 한두 번만 울고 그침 -> 인사.
  if (f.repetitionCount <= 1 && streakSeconds <= 1) {
    return CatSituation.greeting;
  }

  // 반복이 적당하고 에너지가 중간 정도 -> 만족/편안함.
  if (f.repetitionCount <= 2 && f.rms.between(0.15, 0.3)) {
    return CatSituation.content;
  }

  // 그 외 -> 관심 요구 (기본값, 이제 도달 빈도가 많이 줄어듦).
  return CatSituation.wantsAttention;
}

extension on double {
  bool between(double lo, double hi) => this >= lo && this <= hi;
}
/// "아니에요" 피드백을 받았을 때, 실제 상태일 확률이 높은 대안을 보여주기
/// 위한 1차 근사 점수. 진짜 통계적 확률은 아니고, 음향 특징이 각 상황의
/// 판정 규칙에 얼마나 가까운지를 0~1 사이 점수로 매긴 것이다.
/// (로드맵 2단계: 이 피드백을 모아 실제 확률 모델로 교체 예정)
List<CatSituation> topAlternativeSituations(
  CatSubLabel subLabel,
  AudioFeatures f,
  CatSituation excluding,
) {
  final scored = _scoreCandidates(subLabel, f);
  scored.removeWhere((entry) => entry.key == excluding);
  scored.sort((a, b) => b.value.compareTo(a.value));
  return scored.take(3).map((e) => e.key).toList();
}

double _clamp01(double v) => v.clamp(0.0, 1.0);

List<MapEntry<CatSituation, double>> _scoreCandidates(
    CatSubLabel subLabel, AudioFeatures f) {
  switch (subLabel) {
    case CatSubLabel.purr:
      return [
        MapEntry(CatSituation.content, 1.0),
        MapEntry(CatSituation.pain,
            (f.durationMs > 6000 && f.rms < 0.25) ? 0.8 : 0.3),
        const MapEntry(CatSituation.wantsAttention, 0.4),
      ];

    case CatSubLabel.hiss:
      return [
        MapEntry(CatSituation.threatTerritory, f.rms > 0.4 ? 1.0 : 0.5),
        MapEntry(CatSituation.fearDefense, f.rms <= 0.4 ? 1.0 : 0.5),
        const MapEntry(CatSituation.fighting, 0.3),
      ];

    case CatSubLabel.growl:
      return [
        MapEntry(CatSituation.fighting, f.repetitionCount >= 2 ? 1.0 : 0.4),
        MapEntry(
            CatSituation.threatTerritory, f.repetitionCount < 2 ? 1.0 : 0.4),
        const MapEntry(CatSituation.fearDefense, 0.3),
      ];

    case CatSubLabel.caterwaul:
      return [
        MapEntry(CatSituation.mating, f.pitchHz > 800 ? 1.0 : 0.4),
        MapEntry(CatSituation.fighting, f.pitchHz <= 800 ? 1.0 : 0.4),
        const MapEntry(CatSituation.nightYowling, 0.4),
      ];

    case CatSubLabel.meow:
    case CatSubLabel.generalCat:
      final isNight = f.hourOfDay >= 22 || f.hourOfDay < 6;
      final streakSeconds = (f.durationMs / 1000).round();
      return [
        MapEntry(
            CatSituation.nightYowling,
            (isNight ? 1.0 : 0.15) *
                _clamp01(f.repetitionCount / 3) *
                _clamp01(streakSeconds / 2)),
        MapEntry(
            CatSituation.huntingChatter,
            _clamp01(f.repetitionCount / 5) *
                (streakSeconds <= 1 ? 1.0 : 0.3)),
        MapEntry(
            CatSituation.motherKitten,
            _clamp01(f.pitchHz / 1000) *
                (streakSeconds <= 1 ? 1.0 : 0.3) *
                (f.repetitionCount <= 2 ? 1.0 : 0.3)),
        MapEntry(
            CatSituation.pain,
            _clamp01(streakSeconds / 2) *
                (1 - _clamp01((f.rms - 0.18) / 0.3))),
        MapEntry(CatSituation.hungry,
            _clamp01(f.repetitionCount / 2) * _clamp01(f.rms / 0.3)),
        MapEntry(
            CatSituation.greeting,
            (f.repetitionCount <= 1 ? 1.0 : 0.3) *
                (streakSeconds <= 1 ? 1.0 : 0.3)),
        MapEntry(
            CatSituation.content,
            (f.repetitionCount <= 2 ? 1.0 : 0.3) *
                (f.rms.between(0.15, 0.3) ? 1.0 : 0.3)),
        const MapEntry(CatSituation.wantsAttention, 0.35),
      ];

    case CatSubLabel.none:
      return [const MapEntry(CatSituation.unknown, 1.0)];
  }
}

/// 매우 단순한 음향 특징 추출기 (영교차율 기반 피치 근사 + RMS).
/// 실시간 성능을 위해 FFT 대신 가벼운 연산만 사용한다.
class SimpleFeatureExtractor {
  final int sampleRate;
  SimpleFeatureExtractor(this.sampleRate);

  double rms(List<double> samples) {
    if (samples.isEmpty) return 0;
    double sumSq = 0;
    for (final s in samples) {
      sumSq += s * s;
    }
    return sqrt(sumSq / samples.length);
  }

  /// 영교차율을 이용한 대략적인 음높이(Hz) 추정.
  double approxPitchHz(List<double> samples) {
    if (samples.length < 2) return 0;
    int crossings = 0;
    for (int i = 1; i < samples.length; i++) {
      if ((samples[i - 1] < 0 && samples[i] >= 0) ||
          (samples[i - 1] >= 0 && samples[i] < 0)) {
        crossings++;
      }
    }
    final seconds = samples.length / sampleRate;
    final zcr = crossings / seconds; // 초당 교차 횟수
    return zcr / 2; // 사인파 기준 교차 2회 = 1주기
  }
}
