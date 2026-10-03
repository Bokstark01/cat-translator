/// 고양이 울음소리 상황 분류 (업무보고서 1,2에서 정리한 12가지 상황)
enum CatSituation {
  greeting, // 인사/반가움
  wantsAttention, // 관심요구
  hungry, // 배고픔/밥요구
  huntingChatter, // 사냥본능/채터링
  content, // 만족/편안함
  fearDefense, // 두려움/경계방어
  threatTerritory, // 위협/영역방어
  pain, // 고통/아픔
  fighting, // 영역다툼/싸움
  mating, // 발정기 짝짓기 신호
  motherKitten, // 어미-새끼 소통
  nightYowling, // 분리불안/고령묘 야간울음
  unknown, // 분류 실패 (고양이 소리는 맞지만 특정 못함)
}

class SituationInfo {
  final String koreanLabel;
  final String spokenPhrase; // TTS로 읽어줄 문장 (고양이 입장에서 하는 말)

  const SituationInfo(this.koreanLabel, this.spokenPhrase);
}

const Map<CatSituation, SituationInfo> kSituationInfo = {
  CatSituation.greeting: SituationInfo("인사/반가움", "주인님, 반가워요! 왔다는 걸 알리는 소리예요."),
  CatSituation.wantsAttention: SituationInfo("관심요구", "저 좀 봐주세요! 관심을 달라는 소리예요."),
  CatSituation.hungry: SituationInfo("배고픔/밥요구", "배고파요, 밥 주세요!"),
  CatSituation.huntingChatter: SituationInfo("사냥본능/채터링", "저거 잡고 싶어요! 사냥 본능이 올라온 소리예요."),
  CatSituation.content: SituationInfo("만족/편안함", "지금 너무 편안하고 좋아요."),
  CatSituation.fearDefense: SituationInfo("두려움/경계방어", "무서워요, 조심스럽게 거리를 둬주세요."),
  CatSituation.threatTerritory: SituationInfo("위협/영역방어", "더 가까이 오면 안 돼요! 경고하는 소리예요."),
  CatSituation.pain: SituationInfo("고통/아픔", "어딘가 아픈 것 같아요. 살펴봐 주세요."),
  CatSituation.fighting: SituationInfo("영역다툼/싸움", "다른 고양이와 신경전을 벌이는 소리예요."),
  CatSituation.mating: SituationInfo("발정기 짝짓기 신호", "짝을 찾는 신호 소리예요."),
  CatSituation.motherKitten: SituationInfo("어미-새끼 소통", "새끼와 어미가 서로 부르는 소리예요."),
  CatSituation.nightYowling: SituationInfo("분리불안/고령묘 야간울음", "혼자 있어서 불안하거나, 밤에 불안해서 우는 소리예요."),
  CatSituation.unknown: SituationInfo("분류 불가", "고양이 소리인 것 같지만, 정확한 상황은 아직 판단하기 어려워요."),
};
