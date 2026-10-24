import 'package:flutter/material.dart';

/// 냥냥이톡 화면 색·모양 모음 (B안 「라벤더 그라데이션」).
/// 인트로·앱 아이콘과 같은 연보라를 바탕으로, 포인트는 살구→로즈 그라데이션.
class NyangColors {
  NyangColors._();

  // 연보라 (인트로 배경·헤더)
  static const lavenderTop = Color(0xFFC4B7F2);
  static const lavenderBottom = Color(0xFFAE9DEA);
  static const lavender = Color(0xFF8E7AE6);
  static const lavenderSoft = Color(0xFFB3A3F0);
  static const lavenderTint = Color(0xFFF1EDFC);
  static const lavenderLine = Color(0xFFE7E1FA);

  // 채팅방 바탕 (위는 옅은 보라, 아래로 갈수록 거의 흰색)
  static const chatTop = Color(0xFFEDE8FB);
  static const chatBottom = Color(0xFFF8F5FD);
  static const sheet = Color(0xFFFBFAFF);

  // 글자
  static const ink = Color(0xFF3D3373);
  static const inkSoft = Color(0xFF6A6290);
  static const muted = Color(0xFF8A82B0);
  static const accentText = Color(0xFF5B4FA8);

  // 포인트 (인트로 글자와 같은 살구 → 로즈)
  static const peach = Color(0xFFFF8C5F);
  static const rose = Color(0xFFD6448C);

  static const shadow = Color(0xFF5B4FA8);
}

class NyangGradients {
  NyangGradients._();

  static const header = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [NyangColors.lavenderTop, NyangColors.lavenderBottom],
  );

  static const chatBackground = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [NyangColors.chatTop, NyangColors.chatBottom],
  );

  /// 내가 보낸 말풍선 · 마이크 버튼
  static const lavenderButton = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [NyangColors.lavenderSoft, NyangColors.lavender],
  );

  /// 듣는 중(녹음 중) 마이크 버튼
  static const listening = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [NyangColors.peach, NyangColors.rose],
  );
}

/// 마스코트 얼굴 동그라미 (헤더·고양이 말풍선 옆 프로필)
class MascotAvatar extends StatelessWidget {
  const MascotAvatar({super.key, this.radius = 18});

  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      padding: EdgeInsets.all(radius * 0.08),
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: NyangColors.shadow.withValues(alpha: 0.16),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipOval(
        child: Image.asset(
          'assets/images/cat_face.png',
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}

ThemeData buildNyangTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: NyangColors.lavender,
    primary: NyangColors.lavender,
    surface: NyangColors.sheet,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: NyangColors.chatBottom,
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: NyangColors.sheet,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: Color(0xFFD8D2EC),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: NyangColors.sheet,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(24)),
      ),
      titleTextStyle: TextStyle(
          color: NyangColors.ink, fontSize: 18, fontWeight: FontWeight.w700),
      contentTextStyle: TextStyle(color: NyangColors.inkSoft, fontSize: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: NyangColors.lavender,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: NyangColors.accentText),
    ),
    listTileTheme: const ListTileThemeData(
      textColor: NyangColors.ink,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
    ),
  );
}
