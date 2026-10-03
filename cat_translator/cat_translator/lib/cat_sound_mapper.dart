import 'dart:math';
import 'cat_situation.dart';

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
class CatLabelResult {
  final CatSubLabel subLabel;
  final double confidence;
  final bool isCatSound;

  CatLabelResult(this.subLabel, this.confidence, this.isCatSound);
}

CatLabelResult pickCatSubLabel(List<double> scores, List<String> labels) {
  // AudioSet(YAMNet) 라벨 중 고양이와 직접 관련된 항목들.
  const purrNames = {"purr"};
  const hissNames = {"hiss"};
  const growlNames = {"growling"};
  const caterwaulNames = {"caterwaul"};
  const meowNames = {"meow"};
  const generalCatNames = {"cat", "domestic animals, pets"};

  double bestScore = 0;
  CatSubLabel bestLabel = CatSubLabel.none;

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
    }
    if (candidate != null && score > bestScore) {
      bestScore = score;
      bestLabel = candidate;
    }
  }

  // 임계값: 너무 낮으면 "고양이 소리 아님"으로 처리.
  const threshold = 0.15;
  final isCat = bestScore >= threshold && bestLabel != CatSubLabel.none;
  return CatLabelResult(bestLabel, bestScore, isCat);
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
  // 밤 시간대(22시~6시)에 길게 반복되는 울음 -> 야간 울음/분리불안.
  final isNight = f.hourOfDay >= 22 || f.hourOfDay < 6;
  if (isNight && f.repetitionCount >= 3 && f.durationMs > 1500) {
    return CatSituation.nightYowling;
  }

  // 아주 빠르게 반복되는 짧고 높은 '클릭형' 소리 -> 채터링(사냥 본능).
  if (f.repetitionCount >= 4 && f.durationMs < 400) {
    return CatSituation.huntingChatter;
  }

  // 매우 높은 피치 + 아주 짧음 -> 새끼 또는 새끼를 부르는 소리.
  if (f.pitchHz > 1200 && f.durationMs < 600) {
    return CatSituation.motherKitten;
  }

  // 낮은 피치 + 길게 끌며 + 에너지 낮음 -> 고통/아픔 가능성.
  if (f.pitchHz < 400 && f.durationMs > 1200 && f.rms < 0.25) {
    return CatSituation.pain;
  }

  // 짧고 음높이가 끝에서 살짝 올라가는 느낌(근사: 중간 피치) + 반복 적음 -> 인사.
  if (f.repetitionCount <= 1 && f.durationMs < 700 && f.pitchHz.between(400, 900)) {
    return CatSituation.greeting;
  }

  // 반복이 잦고 점점 커지는 느낌(에너지 중간 이상) -> 배고픔/밥 요구.
  if (f.repetitionCount >= 2 && f.rms > 0.35) {
    return CatSituation.hungry;
  }

  // 그 외 일반적인 야옹 -> 관심 요구 (가장 흔한 기본값).
  return CatSituation.wantsAttention;
}

extension on double {
  bool between(double lo, double hi) => this >= lo && this <= hi;
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
