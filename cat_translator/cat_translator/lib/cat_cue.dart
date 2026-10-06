/// "말 걸기" 기능: 자유 문장을 고양이 언어로 "번역"하는 건 과학적으로
/// 불가능하므로(고양이는 사람처럼 단어 기반 언어가 없음), 미리 정해둔
/// 의도 목록 중 하나를 사용자가 고르면 그 의도에 맞게 합성한 신호음을
/// 들려주는 방식으로 구현한다.
///
/// 아래 각 소리는 실제 고양이 울음소리를 녹음/번역한 것이 아니라,
/// 고양이의 주의를 끌거나 편안하게 하는 데 도움이 될 수 있다고 알려진
/// 특징(높은 피치의 짹짹거리는 소리, 낮고 느린 톤, 짧고 또렷한 벨소리 등)을
/// 참고해 100% 합성한 효과음이다. (tools/generate_cat_cue_sounds.py 참고)
enum CatCue {
  callAttention, // 이리 와 (부르기)
  praise, // 착하다/애정 표현
  feedingCue, // 밥 시간 신호
  warning, // 안 돼/하지 마
  calm, // 괜찮아/안심
  play, // 놀자
}

class CatCueInfo {
  final String label;
  final String emoji;
  final String description; // 이 소리를 들려주면 기대할 수 있는 효과(과장 없이)
  final String assetPath;

  const CatCueInfo(this.label, this.emoji, this.description, this.assetPath);
}

const Map<CatCue, CatCueInfo> kCatCueInfo = {
  CatCue.callAttention: CatCueInfo(
    '이리 와',
    '📣',
    '새끼를 부르는 소리와 비슷한 고주파 트릴이에요. 주의를 끄는 데 도움이 될 수 있어요.',
    'sounds/call_attention.wav',
  ),
  CatCue.praise: CatCueInfo(
    '착하다',
    '💛',
    '그르렁거리는 느낌의 낮은 허밍이에요. 편안하고 다정한 분위기를 낼 때 써보세요.',
    'sounds/praise.wav',
  ),
  CatCue.feedingCue: CatCueInfo(
    '밥 시간',
    '🍖',
    '밝고 또렷한 벨소리예요. 밥 줄 때마다 반복해서 들려주면 "이 소리 = 밥"으로 학습시킬 수 있어요.',
    'sounds/feeding_cue.wav',
  ),
  CatCue.warning: CatCueInfo(
    '안 돼',
    '✋',
    '짧고 날카로운 신호음이에요. 하던 행동을 잠깐 멈추게 하고 싶을 때 써보세요.',
    'sounds/warning.wav',
  ),
  CatCue.calm: CatCueInfo(
    '괜찮아',
    '🌙',
    '느리고 낮은 톤이에요. 긴장했을 때 차분한 분위기를 만들어주는 데 도움이 될 수 있어요.',
    'sounds/calm.wav',
  ),
  CatCue.play: CatCueInfo(
    '놀자',
    '🧶',
    '통통 튀는 리듬의 짧은 음이에요. 놀이를 시작하고 싶을 때 들려주세요.',
    'sounds/play.wav',
  ),
};
