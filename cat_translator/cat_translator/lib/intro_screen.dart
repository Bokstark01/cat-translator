import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'cat_name_screen.dart';

/// 앱 시작 시 채팅 화면으로 넘어가기 전에 보여주는 인트로 애니메이션.
/// 화면 중앙에 집사(사람)가 서 있고, 맞은편에서 고양이가 달려와
/// 집사에게 말을 건 뒤 "냥냥이톡" 타이틀이 나타난다.
///
/// 이모지 대신 직접 그린(CustomPainter) 벡터 캐릭터를 사용해서
/// 해상도에 관계없이 또렷하고, 달리기/꼬리 흔들기/숨쉬기/눈 깜빡임 같은
/// 자연스러운 움직임을 세밀하게 제어한다.
class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key});

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _sceneIn;
  late final Animation<double> _catRun;
  late final Animation<double> _catLand;
  late final Animation<double> _bubbleIn;
  late final Animation<double> _titleIn;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3400),
    );

    // 0.00~0.10: 배경/집사가 부드럽게 페이드인.
    _sceneIn = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.10, curve: Curves.easeOut),
    );
    // 0.08~0.60: 고양이가 화면 오른쪽에서 집사 쪽으로 달려온다.
    _catRun = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.08, 0.60, curve: Curves.easeInOutCubic),
    );
    // 0.60~0.76: 도착한 고양이가 통통 튀며 착지(스쿼시&스트레치).
    _catLand = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.60, 0.76, curve: Curves.easeOut),
    );
    // 0.74~0.90: 말풍선이 통통 튀듯 나타난다.
    _bubbleIn = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.74, 0.90, curve: Curves.elasticOut),
    );
    // 0.88~1.0: "냥냥이톡" 타이틀 등장.
    _titleIn = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.88, 1.0, curve: Curves.easeOutBack),
    );

    _controller.forward();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        Future.delayed(const Duration(milliseconds: 750), () {
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const CatNameScreen()),
          );
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final groundY = size.height * 0.42;

    return Scaffold(
      backgroundColor: const Color(0xFFFFE9CC),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final t = _controller.value;
          final sceneOpacity = _sceneIn.value.clamp(0.0, 1.0);

          // --- 고양이 달리기 ---
          final isRunning = t < 0.60;
          final runProgress = _catRun.value.clamp(0.0, 1.0);
          final startX = size.width + 80;
          final endX = size.width * 0.58;
          final catX = startX - (startX - endX) * runProgress;
          final strideSpeed = 11.0;
          final legPhase = runProgress * math.pi * strideSpeed;
          final runBounce = isRunning ? math.sin(legPhase).abs() * 7 : 0.0;

          // --- 착지 스쿼시 & 스트레치 (한 번 눌렸다 퍼지는 펄스) ---
          final landT = _catLand.value.clamp(0.0, 1.0);
          final squash = isRunning ? 0.0 : math.sin(landT * math.pi);

          // --- 꼬리는 처음부터 끝까지 살랑살랑 ---
          final tailPhase = t * math.pi * 7;

          // --- 말풍선 / 타이틀 ---
          final bubbleOpacity = _bubbleIn.value.clamp(0.0, 1.0);
          final titleOpacity = _titleIn.value.clamp(0.0, 1.0);

          // --- 집사(사람) 숨쉬기 + 눈 깜빡임 ---
          final breathe = math.sin(t * math.pi * 2.4) * 3;
          final blink = (t > 0.24 && t < 0.29) || (t > 0.92 && t < 0.97);

          final catScaleY = 1.0 - squash * 0.22;
          final catScaleX = 1.0 + squash * 0.16;

          return Opacity(
            opacity: sceneOpacity,
            child: Stack(
              children: [
                _Background(size: size, groundY: groundY, progress: t),

                // 집사 그림자
                Positioned(
                  left: size.width * 0.30 + 14,
                  top: groundY + 4,
                  child: _ShadowOval(width: 64, opacity: 0.16),
                ),
                // 집사(사람)
                Positioned(
                  left: size.width * 0.30,
                  top: groundY - 152 + breathe,
                  child: CustomPaint(
                    size: const Size(96, 154),
                    painter: _PersonPainter(blink: blink),
                  ),
                ),

                // 고양이 그림자 (착지 시 살짝 커짐)
                Positioned(
                  left: catX + 6,
                  top: groundY + 28,
                  child: _ShadowOval(width: 54 + squash * 14, opacity: 0.18),
                ),
                // 고양이
                Positioned(
                  left: catX,
                  top: groundY - 58 - runBounce,
                  child: Transform.scale(
                    alignment: Alignment.bottomCenter,
                    scaleX: catScaleX,
                    scaleY: catScaleY,
                    child: CustomPaint(
                      size: const Size(78, 58),
                      painter: _CatPainter(
                        legPhase: legPhase,
                        running: isRunning,
                        tailPhase: tailPhase,
                        excited: !isRunning,
                      ),
                    ),
                  ),
                ),

                // 말풍선
                Positioned(
                  left: size.width * 0.50,
                  top: groundY - 158,
                  child: Opacity(
                    opacity: bubbleOpacity,
                    child: Transform.scale(
                      alignment: Alignment.bottomLeft,
                      scale: 0.6 + 0.4 * bubbleOpacity,
                      child: const _SpeechBubble(text: '집사님! 저 왔어요냥~'),
                    ),
                  ),
                ),

                // "냥냥이톡" 타이틀.
                Align(
                  alignment: const Alignment(0, 0.72),
                  child: Opacity(
                    opacity: titleOpacity,
                    child: Transform.scale(
                      scale: 0.85 + 0.15 * titleOpacity,
                      child: const _TitleLockup(),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 은은한 그러데이션 하늘 + 해 + 구름 + 발바닥 무늬 장식 + 바닥선.
class _Background extends StatelessWidget {
  const _Background(
      {required this.size, required this.groundY, required this.progress});

  final Size size;
  final double groundY;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          width: size.width,
          height: size.height,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFFF3E0), Color(0xFFFFE0B2)],
            ),
          ),
        ),
        // 해.
        Positioned(
          right: -30,
          top: 40,
          child: Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFFFD180).withValues(alpha: 0.55),
            ),
          ),
        ),
        // 구름 두 개 (은은하게 떠다니는 느낌).
        Positioned(
          left: 24 + math.sin(progress * math.pi) * 6,
          top: 70,
          child: _cloud(0.5),
        ),
        Positioned(
          left: size.width * 0.55 + math.cos(progress * math.pi) * 8,
          top: 110,
          child: _cloud(0.35),
        ),
        // 바닥 그림자 선.
        Positioned(
          left: 0,
          right: 0,
          top: groundY + 46,
          child: Container(
            height: 2,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.black.withValues(alpha: 0.0),
                  Colors.black.withValues(alpha: 0.10),
                  Colors.black.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ),
        // 발바닥 무늬 장식 (아주 옅게).
        Positioned(
          left: size.width * 0.14,
          top: groundY - 170,
          child: Opacity(
            opacity: 0.18,
            child: Transform.rotate(
              angle: -0.3,
              child: const Icon(Icons.pets, size: 22, color: Color(0xFFFF9933)),
            ),
          ),
        ),
        Positioned(
          left: size.width * 0.22,
          top: groundY - 140,
          child: Opacity(
            opacity: 0.14,
            child: Transform.rotate(
              angle: -0.2,
              child: const Icon(Icons.pets, size: 16, color: Color(0xFFFF9933)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _cloud(double opacity) {
    return Opacity(
      opacity: opacity,
      child: const Icon(Icons.cloud, size: 46, color: Colors.white),
    );
  }
}

class _ShadowOval extends StatelessWidget {
  const _ShadowOval({required this.width, required this.opacity});
  final double width;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: width * 0.28,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: opacity),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _SpeechBubble extends StatelessWidget {
  const _SpeechBubble({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BubbleTailPainter(),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 6,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Color(0xFF6B4A2B),
          ),
        ),
      ),
    );
  }
}

/// 말풍선 아래쪽에 작은 꼬리(삼각형)를 그려준다.
class _BubbleTailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;
    final path = Path()
      ..moveTo(18, size.height - 2)
      ..lineTo(28, size.height - 2)
      ..lineTo(16, size.height + 10)
      ..close();
    canvas.drawShadow(path, Colors.black, 2, false);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TitleLockup extends StatelessWidget {
  const _TitleLockup();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.pets, color: Color(0xFFFF9933), size: 22),
            SizedBox(width: 6),
            Text(
              '냥냥이톡',
              style: TextStyle(
                fontSize: 42,
                fontWeight: FontWeight.w900,
                color: Color(0xFFFF9933),
                shadows: [
                  Shadow(
                    color: Colors.black26,
                    offset: Offset(0, 2),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
            SizedBox(width: 6),
            Icon(Icons.pets, color: Color(0xFFFF9933), size: 22),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '고양이의 마음을 들어보세요',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF8A5A2B).withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }
}

/// 집사(사람) 캐릭터. 둥글둥글한 플랫 일러스트 스타일로 그려서
/// 이모지보다 또렷하고 자연스럽게 보이도록 한다.
class _PersonPainter extends CustomPainter {
  _PersonPainter({required this.blink});
  final bool blink;

  static const _skin = Color(0xFFFFD9B3);
  static const _hair = Color(0xFF6B4A2B);
  static const _sweater = Color(0xFFFF9933);
  static const _sweaterShade = Color(0xFFE67E22);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 다리/신발.
    final shoePaint = Paint()..color = const Color(0xFF4A3524);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.22, h * 0.90, w * 0.22, h * 0.10),
          const Radius.circular(6)),
      shoePaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.56, h * 0.90, w * 0.22, h * 0.10),
          const Radius.circular(6)),
      shoePaint,
    );

    // 바지(살짝 보이는 부분).
    final pantsPaint = Paint()..color = const Color(0xFF7A6248);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.20, h * 0.80, w * 0.24, h * 0.14),
          const Radius.circular(8)),
      pantsPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.56, h * 0.80, w * 0.24, h * 0.14),
          const Radius.circular(8)),
      pantsPaint,
    );

    // 몸통(스웨터) - 둥근 사다리꼴 느낌의 RRect.
    final bodyRect = Rect.fromLTWH(w * 0.10, h * 0.42, w * 0.80, h * 0.44);
    final bodyPaint = Paint()..color = _sweater;
    canvas.drawRRect(
      RRect.fromRectAndCorners(bodyRect,
          topLeft: const Radius.circular(34),
          topRight: const Radius.circular(34),
          bottomLeft: const Radius.circular(18),
          bottomRight: const Radius.circular(18)),
      bodyPaint,
    );
    // 스웨터 라인 장식.
    final linePaint = Paint()
      ..color = _sweaterShade
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(w * 0.16, h * 0.62),
      Offset(w * 0.84, h * 0.62),
      linePaint,
    );

    // 팔 (환영하듯 살짝 벌림).
    final armPaint = Paint()..color = _sweater;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(w * -0.02, h * 0.46, w * 0.20, h * 0.30),
          const Radius.circular(14)),
      armPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.82, h * 0.46, w * 0.20, h * 0.30),
          const Radius.circular(14)),
      armPaint,
    );
    final handPaint = Paint()..color = _skin;
    canvas.drawCircle(Offset(w * 0.06, h * 0.76), w * 0.08, handPaint);
    canvas.drawCircle(Offset(w * 0.94, h * 0.76), w * 0.08, handPaint);

    // 목.
    final neckPaint = Paint()..color = _skin;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.42, h * 0.36, w * 0.16, h * 0.12),
          const Radius.circular(6)),
      neckPaint,
    );

    // 얼굴.
    final faceCenter = Offset(w * 0.5, h * 0.22);
    final faceRadius = w * 0.30;
    final facePaint = Paint()..color = _skin;
    canvas.drawCircle(faceCenter, faceRadius, facePaint);

    // 머리카락 (뒤쪽 볼륨 + 앞머리).
    final hairPaint = Paint()..color = _hair;
    canvas.drawArc(
      Rect.fromCircle(center: faceCenter, radius: faceRadius * 1.08),
      math.pi,
      math.pi,
      true,
      hairPaint,
    );
    final bangs = Path()
      ..moveTo(faceCenter.dx - faceRadius, faceCenter.dy - faceRadius * 0.15)
      ..quadraticBezierTo(
        faceCenter.dx - faceRadius * 0.3,
        faceCenter.dy - faceRadius * 0.95,
        faceCenter.dx,
        faceCenter.dy - faceRadius * 0.75,
      )
      ..quadraticBezierTo(
        faceCenter.dx + faceRadius * 0.4,
        faceCenter.dy - faceRadius * 1.0,
        faceCenter.dx + faceRadius,
        faceCenter.dy - faceRadius * 0.15,
      )
      ..lineTo(faceCenter.dx + faceRadius, faceCenter.dy - faceRadius * 0.5)
      ..quadraticBezierTo(
        faceCenter.dx,
        faceCenter.dy - faceRadius * 1.25,
        faceCenter.dx - faceRadius,
        faceCenter.dy - faceRadius * 0.5,
      )
      ..close();
    canvas.drawPath(bangs, hairPaint);

    // 볼 홍조.
    final blushPaint = Paint()
      ..color = const Color(0xFFFF8A80).withValues(alpha: 0.45);
    canvas.drawCircle(
        Offset(faceCenter.dx - faceRadius * 0.55, faceCenter.dy + faceRadius * 0.15),
        faceRadius * 0.16,
        blushPaint);
    canvas.drawCircle(
        Offset(faceCenter.dx + faceRadius * 0.55, faceCenter.dy + faceRadius * 0.15),
        faceRadius * 0.16,
        blushPaint);

    // 눈 (깜빡임 지원).
    final eyePaint = Paint()..color = const Color(0xFF3E2A1A);
    final eyeY = faceCenter.dy - faceRadius * 0.05;
    final eyeDx = faceRadius * 0.38;
    if (blink) {
      final blinkPaint = Paint()
        ..color = const Color(0xFF3E2A1A)
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(faceCenter.dx - eyeDx - 5, eyeY),
          Offset(faceCenter.dx - eyeDx + 5, eyeY), blinkPaint);
      canvas.drawLine(Offset(faceCenter.dx + eyeDx - 5, eyeY),
          Offset(faceCenter.dx + eyeDx + 5, eyeY), blinkPaint);
    } else {
      canvas.drawCircle(
          Offset(faceCenter.dx - eyeDx, eyeY), faceRadius * 0.11, eyePaint);
      canvas.drawCircle(
          Offset(faceCenter.dx + eyeDx, eyeY), faceRadius * 0.11, eyePaint);
      final highlight = Paint()..color = Colors.white;
      canvas.drawCircle(
          Offset(faceCenter.dx - eyeDx + 2, eyeY - 2), faceRadius * 0.04,
          highlight);
      canvas.drawCircle(
          Offset(faceCenter.dx + eyeDx + 2, eyeY - 2), faceRadius * 0.04,
          highlight);
    }

    // 웃는 입.
    final mouthPaint = Paint()
      ..color = const Color(0xFF8A4B32)
      ..strokeWidth = 2.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final mouthPath = Path()
      ..moveTo(faceCenter.dx - faceRadius * 0.22, faceCenter.dy + faceRadius * 0.38)
      ..quadraticBezierTo(
        faceCenter.dx,
        faceCenter.dy + faceRadius * 0.58,
        faceCenter.dx + faceRadius * 0.22,
        faceCenter.dy + faceRadius * 0.38,
      );
    canvas.drawPath(mouthPath, mouthPaint);
  }

  @override
  bool shouldRepaint(covariant _PersonPainter oldDelegate) =>
      oldDelegate.blink != blink;
}

/// 고양이 캐릭터. 달릴 때는 다리가 교차로 움직이고 꼬리가 살랑거리며,
/// 도착한 뒤에는(눈이 동그래지고) 반가운 표정을 짓는다.
class _CatPainter extends CustomPainter {
  _CatPainter({
    required this.legPhase,
    required this.running,
    required this.tailPhase,
    required this.excited,
  });

  final double legPhase;
  final bool running;
  final double tailPhase;
  final bool excited;

  static const _fur = Color(0xFFFFB84D);
  static const _furShade = Color(0xFFF28C28);
  static const _cream = Color(0xFFFFF3E0);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 고양이는 왼쪽(집사 방향)을 바라본다. 머리는 왼쪽 30% 지점.
    final bodyRect = Rect.fromLTWH(w * 0.18, h * 0.28, w * 0.62, h * 0.46);

    // --- 꼬리 (뒤쪽, 몸통보다 먼저 그려서 몸에 가려지게) ---
    final tailAngle = math.sin(tailPhase) * 0.6;
    final tailBase = Offset(w * 0.78, h * 0.42);
    final tailPaint = Paint()
      ..color = _fur
      ..strokeWidth = w * 0.11
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final tailEnd = Offset(
      tailBase.dx + math.cos(-0.9 + tailAngle) * w * 0.34,
      tailBase.dy - math.sin(1.2 + tailAngle) * h * 0.55,
    );
    final tailControl = Offset(tailBase.dx + w * 0.18, tailBase.dy - h * 0.25);
    final tailPath = Path()
      ..moveTo(tailBase.dx, tailBase.dy)
      ..quadraticBezierTo(
          tailControl.dx, tailControl.dy, tailEnd.dx, tailEnd.dy);
    canvas.drawPath(tailPath, tailPaint);

    // --- 다리 (달릴 때 교차, 도착 후엔 짧게 모음) ---
    final legPaint = Paint()..color = _furShade;
    final legW = w * 0.09;
    final legH = h * 0.26;
    final frontLegX = w * 0.30;
    final backLegX = w * 0.58;
    final legSwing = running ? math.sin(legPhase) * (w * 0.07) : 0.0;
    final legSwing2 = running ? math.sin(legPhase + math.pi) * (w * 0.07) : 0.0;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(frontLegX + legSwing, h * 0.62, legW, legH),
          const Radius.circular(5)),
      legPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(backLegX + legSwing2, h * 0.62, legW, legH),
          const Radius.circular(5)),
      legPaint,
    );

    // --- 몸통 ---
    final bodyPaint = Paint()..color = _fur;
    canvas.drawOval(bodyRect, bodyPaint);
    // 배(크림색) 패치.
    final bellyPaint = Paint()..color = _cream;
    canvas.drawOval(
      Rect.fromLTWH(bodyRect.left + bodyRect.width * 0.18,
          bodyRect.top + bodyRect.height * 0.42, bodyRect.width * 0.55,
          bodyRect.height * 0.5),
      bellyPaint,
    );

    // --- 머리 ---
    final headCenter = Offset(w * 0.22, h * 0.26);
    final headR = w * 0.22;
    final headPaint = Paint()..color = _fur;
    canvas.drawCircle(headCenter, headR, headPaint);

    // 귀 (쫑긋, 달릴 때 살짝 뒤로 눕고 도착 시 쫑긋 세움).
    final earTilt = running ? 0.35 : 0.1;
    _drawEar(canvas, headCenter, headR, -1, earTilt);
    _drawEar(canvas, headCenter, headR, 1, earTilt);

    // 주둥이(흰 부분).
    final muzzlePaint = Paint()..color = _cream;
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(headCenter.dx - headR * 0.35, headCenter.dy + headR * 0.25),
          width: headR * 0.95,
          height: headR * 0.65),
      muzzlePaint,
    );

    // 코.
    final nosePaint = Paint()..color = const Color(0xFFE91E63);
    final nosePath = Path()
      ..moveTo(headCenter.dx - headR * 0.62, headCenter.dy + headR * 0.08)
      ..lineTo(headCenter.dx - headR * 0.48, headCenter.dy + headR * 0.08)
      ..lineTo(headCenter.dx - headR * 0.55, headCenter.dy + headR * 0.20)
      ..close();
    canvas.drawPath(nosePath, nosePaint);

    // 눈 (달릴 땐 기분 좋게 감은 호, 도착하면 반짝이는 동그란 눈).
    final eyeY = headCenter.dy - headR * 0.05;
    if (excited) {
      final eyePaint = Paint()..color = const Color(0xFF2D1B0E);
      canvas.drawCircle(
          Offset(headCenter.dx - headR * 0.58, eyeY), headR * 0.16, eyePaint);
      canvas.drawCircle(
          Offset(headCenter.dx - headR * 0.08, eyeY - headR * 0.1),
          headR * 0.16, eyePaint);
      final sparkle = Paint()..color = Colors.white;
      canvas.drawCircle(
          Offset(headCenter.dx - headR * 0.58 + 1.5, eyeY - 1.5),
          headR * 0.05, sparkle);
      canvas.drawCircle(
          Offset(headCenter.dx - headR * 0.08 + 1.5, eyeY - headR * 0.1 - 1.5),
          headR * 0.05, sparkle);
    } else {
      final happyPaint = Paint()
        ..color = const Color(0xFF2D1B0E)
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
          Rect.fromCenter(
              center: Offset(headCenter.dx - headR * 0.58, eyeY),
              width: headR * 0.3,
              height: headR * 0.3),
          0.15,
          2.8,
          false,
          happyPaint);
      canvas.drawArc(
          Rect.fromCenter(
              center: Offset(headCenter.dx - headR * 0.08, eyeY - headR * 0.1),
              width: headR * 0.3,
              height: headR * 0.3),
          0.15,
          2.8,
          false,
          happyPaint);
    }

    // 수염.
    final whiskerPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    for (final dy in [-0.06, 0.0, 0.06]) {
      canvas.drawLine(
        Offset(headCenter.dx - headR * 0.75, headCenter.dy + headR * (0.15 + dy)),
        Offset(headCenter.dx - headR * 1.25, headCenter.dy + headR * (0.05 + dy * 1.6)),
        whiskerPaint,
      );
    }
  }

  void _drawEar(Canvas canvas, Offset headCenter, double headR, int side, double tilt) {
    final outerPaint = Paint()..color = _fur;
    final innerPaint = Paint()..color = const Color(0xFFFFCBA4);
    final baseX = headCenter.dx + side * headR * 0.45;
    final baseY = headCenter.dy - headR * 0.75;
    final tipX = baseX + side * headR * 0.25 - tilt * headR * side;
    final tipY = baseY - headR * 0.55;
    final outer = Path()
      ..moveTo(baseX - headR * 0.22, baseY + headR * 0.15)
      ..lineTo(tipX, tipY)
      ..lineTo(baseX + headR * 0.22, baseY + headR * 0.15)
      ..close();
    canvas.drawPath(outer, outerPaint);
    final inner = Path()
      ..moveTo(baseX - headR * 0.10, baseY + headR * 0.08)
      ..lineTo(tipX - side * headR * 0.03, tipY + headR * 0.12)
      ..lineTo(baseX + headR * 0.10, baseY + headR * 0.08)
      ..close();
    canvas.drawPath(inner, innerPaint);
  }

  @override
  bool shouldRepaint(covariant _CatPainter oldDelegate) => true;
}
