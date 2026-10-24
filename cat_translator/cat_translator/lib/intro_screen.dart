import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import 'cat_name_screen.dart';

/// 앱 시작 인트로 (약 2초, 화면을 탭하면 바로 건너뜀).
///
/// 화면 중앙에 마스코트 고양이가 스프링처럼 통 하고 나타난 뒤
/// 말하듯 고개를 까딱이며 몸을 살짝 늘였다 줄이고,
/// 그 사이 흰 말풍선이 스프링 움직임으로 떠오른다.
class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key});

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

/// 실제 스프링 물리(질량·강성·감쇠)로 움직이는 곡선.
/// [Curves.elasticOut]보다 덜 출렁이고 자연스럽게 멈춘다.
class _SpringCurve extends Curve {
  const _SpringCurve({this.stiffness = 180, this.damping = 14});

  final double stiffness;
  final double damping;

  @override
  double transformInternal(double t) {
    final sim = SpringSimulation(
      SpringDescription(mass: 1, stiffness: stiffness, damping: damping),
      0,
      1,
      0,
    );
    // 곡선 구간(0~1)을 스프링 시간 0.9초로 펼친다.
    return sim.x(t * 0.9);
  }
}

class _IntroScreenState extends State<IntroScreen>
    with SingleTickerProviderStateMixin {
  static const _total = Duration(milliseconds: 2000);
  static const _mascot = AssetImage('assets/images/cat_mascot.png');

  // 아이콘 말풍선과 같은 연보라 (#BEB0F0) 기준, 위아래로 아주 옅은 그라데이션.
  static const _bgTop = Color(0xFFC4B7F2);
  static const _bgBottom = Color(0xFFB6A6EC);
  // 글자 그라데이션 (살구 → 로즈)
  static const _textGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFF8C5F), Color(0xFFD6448C)],
  );

  late final AnimationController _controller;
  late final Animation<double> _catIn;
  late final Animation<double> _bubbleIn;
  late final Animation<double> _titleIn;
  bool _left = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _total);

    // 0.00~0.40: 고양이가 살짝 작은 크기에서 스프링으로 통 하고 등장.
    _catIn = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.40, curve: _SpringCurve()),
    );
    // 0.34~0.80: 말하는 도중 흰 말풍선이 스프링으로 떠오름.
    _bubbleIn = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.34, 0.80,
          curve: _SpringCurve(stiffness: 220, damping: 15)),
    );

    // 0.52~0.95: "냥냥이톡" 타이틀이 고양이 아래에서 살짝 떠오르며 나타남.
    _titleIn = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.52, 0.95,
          curve: _SpringCurve(stiffness: 160, damping: 16)),
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) _goNext();
    });
    _controller.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 첫 프레임에 그림이 비어 보이지 않도록 미리 불러온다.
    precacheImage(_mascot, context);
  }

  void _goNext() {
    if (_left || !mounted) return;
    _left = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (_, __, ___) => const CatNameScreen(),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 말하는 동작의 세기. 0.25~0.85 구간에서 서서히 커졌다가 잦아든다.
  double _talkEnvelope(double t) {
    if (t <= 0.25 || t >= 0.85) return 0;
    final p = (t - 0.25) / 0.60;
    return math.sin(p * math.pi);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    // 고양이 크기는 화면 폭의 70% (태블릿에서도 너무 커지지 않게 최대 300).
    final catSize = math.min(size.width * 0.70, 300.0);
    final catH = catSize * 1.1; // 그림 비율(약 0.91:1)에 맞춘 높이
    final boxW = catSize * 1.2;
    final bubbleZone = catSize * 0.32; // 고양이 머리 위 말풍선 자리
    final titleZone = catSize * 0.38; // 고양이 아래 타이틀 자리
    final boxH = bubbleZone + catH + catSize * 0.06 + titleZone;

    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _goNext, // 탭하면 건너뛰기
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_bgTop, _bgBottom],
            ),
          ),
          child: Center(
            child: SizedBox(
              width: boxW,
              height: boxH,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final t = _controller.value;
                  final catIn = _catIn.value;
                  final bubbleIn = _bubbleIn.value;

                  // 말하기: 3번 정도 "냐-옹" 하듯 몸을 늘였다 줄이고 고개를 까딱.
                  final env = _talkEnvelope(t);
                  final beat = math.sin(t * math.pi * 2 * 3.2).abs();
                  final talkScaleY = 1 + 0.045 * env * beat;
                  final talkScaleX = 1 - 0.025 * env * beat;
                  final tilt = 0.05 * env * math.sin(t * math.pi * 2 * 1.6);

                  final appear = 0.86 + 0.14 * catIn;
                  final catOpacity = (catIn * 1.6).clamp(0.0, 1.0);
                  final bubbleOpacity = (bubbleIn * 2).clamp(0.0, 1.0);
                  final titleIn = _titleIn.value;
                  final titleOpacity = (titleIn * 1.8).clamp(0.0, 1.0);

                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // 바닥 그림자
                      Positioned(
                        left: (boxW - catSize * 0.62) / 2,
                        bottom: titleZone,
                        child: Opacity(
                          opacity: catOpacity,
                          child: Transform.scale(
                            scaleX: talkScaleX,
                            child: Container(
                              width: catSize * 0.62,
                              height: catSize * 0.07,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(catSize),
                                color: const Color(0xFF4A3D96)
                                    .withValues(alpha: 0.18),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF5B4FA8)
                                        .withValues(alpha: 0.12),
                                    blurRadius: 16,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      // 마스코트 고양이
                      Positioned(
                        left: (boxW - catSize) / 2,
                        bottom: titleZone + catSize * 0.03,
                        child: Opacity(
                          opacity: catOpacity,
                          child: Transform.scale(
                            scale: appear,
                            alignment: Alignment.bottomCenter,
                            child: Transform.rotate(
                              angle: tilt,
                              alignment: Alignment.bottomCenter,
                              child: Transform.scale(
                                scaleX: talkScaleX,
                                scaleY: talkScaleY,
                                alignment: Alignment.bottomCenter,
                                child: Image(
                                  image: _mascot,
                                  width: catSize,
                                  height: catH,
                                  fit: BoxFit.contain,
                                  filterQuality: FilterQuality.medium,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      // 흰 말풍선 (고양이 머리 오른쪽 위, 꼬리가 고양이를 향함)
                      Positioned(
                        left: boxW * 0.48,
                        top: 0,
                        child: Opacity(
                          opacity: bubbleOpacity,
                          child: Transform.translate(
                            offset: Offset(0, 12 * (1 - bubbleIn)),
                            child: Transform.scale(
                              scale: 0.5 + 0.5 * bubbleIn,
                              alignment: Alignment.bottomLeft,
                              child: const _SpeechBubble(
                                text: '안냥!',
                                gradient: _textGradient,
                              ),
                            ),
                          ),
                        ),
                      ),
                      // "냥냥이톡" 타이틀 (고양이 아래)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Opacity(
                          opacity: titleOpacity,
                          child: Transform.translate(
                            offset: Offset(0, 16 * (1 - titleIn)),
                            child: const _GradientTitle(
                              text: '냥냥이톡',
                              gradient: _textGradient,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 꼬리가 왼쪽 아래(고양이 쪽)를 향하는 흰 말풍선.
class _SpeechBubble extends StatelessWidget {
  const _SpeechBubble({required this.text, required this.gradient});

  final String text;
  final Gradient gradient;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const _BubblePainter(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 22),
        child: ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => gradient.createShader(bounds),
          child: Text(
            text,
            style: const TextStyle(
              fontFamily: 'DongleIntro',
              fontSize: 46,
              height: 1.0,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

/// 흰 테두리 + 옅은 보라 그림자 위에 그라데이션 글자를 얹은 스티커풍 타이틀.
class _GradientTitle extends StatelessWidget {
  const _GradientTitle({required this.text, required this.gradient});

  final String text;
  final Gradient gradient;

  static const _style = TextStyle(
    fontFamily: 'DongleIntro',
    fontSize: 64,
    height: 1.0,
  );

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // 흰 테두리 (그림자 포함)
        Text(
          text,
          textAlign: TextAlign.center,
          style: _style.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 7
              ..strokeJoin = StrokeJoin.round
              ..color = Colors.white,
            shadows: const [
              Shadow(
                color: Color(0x404A3D96),
                blurRadius: 10,
                offset: Offset(0, 3),
              ),
            ],
          ),
        ),
        // 그라데이션 글자
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => gradient.createShader(bounds),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: _style.copyWith(color: Colors.white),
          ),
        ),
      ],
    );
  }
}

class _BubblePainter extends CustomPainter {
  const _BubblePainter();

  @override
  void paint(Canvas canvas, Size size) {
    const tailH = 14.0;
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height - tailH),
      const Radius.circular(24),
    );
    final path = Path()
      ..addRRect(body)
      ..moveTo(22, size.height - tailH - 1)
      ..quadraticBezierTo(18, size.height - 4, 8, size.height)
      ..quadraticBezierTo(30, size.height - 6, 46, size.height - tailH - 1)
      ..close();

    // 은은한 보랏빛 그림자
    canvas.drawShadow(
        path.shift(const Offset(0, 2)), const Color(0x665B4FA8), 10, false);
    canvas.drawPath(path, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
