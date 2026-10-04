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

/// 상황별 분위기 그룹 (화면 색상 톤을 정할 때 사용).
enum SituationMood { happy, needy, caution, danger, playful, unknown }

class SituationInfo {
    final String koreanLabel;
    final String spokenPhrase; // TTS로 읽어줄 문장 (고양이가 직접 말하는 느낌의 귀여운 말투)
    final String emoji;
    final SituationMood mood;

    const SituationInfo(this.koreanLabel, this.spokenPhrase, this.emoji, this.mood);
}

const Map<CatSituation, SituationInfo> kSituationInfo = {
    CatSituation.greeting:
        SituationInfo("인사/반가움", "주인님 오셨다냥! 반가워요냥~", "😺", SituationMood.happy),
    CatSituation.wantsAttention:
        SituationInfo("관심요구", "저 좀 봐주세요냥~", "🥺", SituationMood.needy),
    CatSituation.hungry:
        SituationInfo("배고픔/밥요구", "배고파요냥... 밥 주세요냥!", "🍖", SituationMood.needy),
    CatSituation.huntingChatter: SituationInfo(
            "사냥본능/채터링", "저거 잡고 싶다냥! 두근두근해요냥~", "😼", SituationMood.playful),
    CatSituation.content:
        SituationInfo("만족/편안함", "완전 편안하다냥~ 기분 좋아요냥", "😻", SituationMood.happy),
    CatSituation.fearDefense: SituationInfo(
            "두려움/경계방어", "무서워요냥... 살살 다가와 주세요냥", "😨", SituationMood.caution),
    CatSituation.threatTerritory: SituationInfo(
            "위협/영역방어", "더 가까이 오지 마세요냥! 경고하는 거예요냥", "😾", SituationMood.danger),
    CatSituation.pain:
        SituationInfo("고통/아픔", "어딘가 아픈 것 같아요냥... 살펴봐 주세요냥", "🤕", SituationMood.danger),
    CatSituation.fighting: SituationInfo(
            "영역다툼/싸움", "저리 비켜요냥! 여긴 제 구역이에요냥", "💢", SituationMood.danger),
    CatSituation.mating:
        SituationInfo("발정기 짝짓기 신호", "짝을 찾고 있어요냥~ 누구 없나요냥", "💕", SituationMood.playful),
    CatSituation.motherKitten: SituationInfo(
            "어미-새끼 소통", "아가야, 엄마 여기 있다냥~", "🐾", SituationMood.happy),
    CatSituation.nightYowling: SituationInfo(
            "분리불안/고령묘 야간울음", "혼자 있으니까 무서워요냥... 같이 있어주세요냥", "🌙", SituationMood.caution),
    CatSituation.unknown: SituationInfo(
            "분류 불가", "무슨 소리인지 아직 잘 모르겠어요냥...", "❓", SituationMood.unknown),
};
