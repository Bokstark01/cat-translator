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
clas
