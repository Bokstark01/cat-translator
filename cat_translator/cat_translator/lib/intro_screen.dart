import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'cat_name_screen.dart';

/// 앱 시작 시 채팅 화면으로 넘어가기 전에 보여주는 인트로 애니메이션.
/// 화면 중앙에 집사(사람)가 서 있고, 맞은편에서 고양이가 달려와
/// 집사에게 말을 건 뒤 "냥냥이톡" 타이틀이 나타난다.
class IntroScreen extends StatefulWidget {
      const IntroScreen({super.key});

      @override
      State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen>
        with SingleTickerProviderStateMixin {
      late final AnimationController _controller;
      late final Animation<double> _catRun;
      late final Animation<double> _bubbleIn;
      late final Animation<double> _titleIn;

      @override
      void initState() {
              super.initState();

              _controller = AnimationController(
                        vsync: this,
                        duration: const Duration(milliseconds: 2600),
                      );

              // 0.0~0.55: 고양이가 화면 오른쪽에서 집사 쪽으로 달려온다.
              _catRun = CurvedAnimation(
                        parent: _controller,
                        curve: const Interval(0.0, 0.55, curve: Curves.easeOutCubic),
                      );
              // 0.55~0.78: 도착한 고양이가 말풍선으로 인사를 건넨다.
              _bubbleIn = CurvedAnimation(
                        parent: _controller,
                        curve: const Interval(0.55, 0.78, curve: Curves.easeOut),
                      );
              // 0.78~1.0: "냥냥이톡" 타이틀이 나타난다.
              _titleIn = CurvedAnimation(
                        parent: _controller,
                        curve: const Interval(0.78, 1.0, curve: Curves.easeOutBack),
                      );

              _controller.forward();
              _controller.addStatusListener((status) {
                        if (status == AnimationStatus.completed) {
                                    Future.delayed(const Duration(milliseconds: 700), () {
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
              final groundY = size.height * 0.38;

              return Scaffold(
                        backgroundColor: const Color(0xFFFFF3E0),
                        body: AnimatedBuilder(
                                    animation: _controller,
                                    builder: (context, child) {
                                                  final startX = size.width + 60;
                                                  final endX = size.width * 0.58;
                                                  final catX = startX - (startX - endX) * _catRun.value;
                                                  // 걸음걸이처럼 보이도록 뛰는 동안 위아래로 통통 튀고
                                                  // 살짝 좌우로 기우뚱거리는 움직임을 더한다.
                                                  final walkCycle = _catRun.value * math.pi * 10;
                                                  final catBounce = math.sin(walkCycle).abs() * 6;
                                                  final catTilt = math.sin(walkCycle) * 0.05;
                                                  final bubbleOpacity = _bubbleIn.value.clamp(0.0, 1.0);
                                                  final titleOpacity = _titleIn.value.clamp(0.0, 1.0);

                                                  return Stack(
                                                                  children: [
                                                                                    // 바닥을 암시하는 옅은 선.
                                                                                    Positioned(
                                                                                                        left: 0,
                                                                                                        right: 0,
                                                                                                        top: groundY + 46,
                                                                                                        child: Container(height: 1, color: Colors.black12),
                                                                                                      ),

                                                                                    // 집사(사람) - 화면 중앙에 고정.
                                                                                    Positioned(
                                                                                                        left: size.width * 0.34,
                                                                                                        top: groundY - 40,
                                                                                                        child: const Text('🧍', style: TextStyle(fontSize: 64)),
                                                                                                      ),

                                                                                    // 고양이 - 오른쪽에서 집사 쪽으로 걸어온다.
                                                                                    // 머리는 기본적으로 왼쪽(집사 방향)을 보고 있으므로
                                                                                    // 좌우 반전 없이 그대로 사용하고, 통통 튀는 걸음과
                                                                                    // 살짝 기우뚱거리는 움직임만 더해 자연스럽게 만든다.
                                                                                    Positioned(
                                                                                                        left: catX,
                                                                                                        top: groundY - 6 - catBounce,
                                                                                                        child: Transform.rotate(
                                                                                                                              angle: catTilt,
                                                                                                                              child: const Text('🐈', style: TextStyle(fontSize: 48)),
                                                                                                                            ),
                                                                                                      ),

                                                                                    // 도착한 고양이가 건네는 말풍선.
                                                                                    Positioned(
                                                                                                        left: size.width * 0.48,
                                                                                                        top: groundY - 78,
                                                                                                        child: Opacity(
                                                                                                                              opacity: bubbleOpacity,
                                                                                                                              child: Transform.scale(
                                                                                                                                                      scale: 0.7 + 0.3 * bubbleOpacity,
                                                                                                                                                      child: Container(
                                                                                                                                                                                padding:
                                                                                                                                                                                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                                                                                                                                                                decoration: BoxDecoration(
                                                                                                                                                                                                            color: Colors.white,
                                                                                                                                                                                                            borderRadius: BorderRadius.circular(14),
                                                                                                                                                                                                            boxShadow: const [
                                                                                                                                                                                                                                          BoxShadow(
                                                                                                                                                                                                                                                                          color: Colors.black26,
                                                                                                                                                                                                                                                                          blurRadius: 4,
                                                                                                                                                                                                                                                                          offset: Offset(0, 2),
                                                                                                                                                                                                                                                                        ),
                                                                                                                                                                                                                                        ],
                                                                                                                                                                                                          ),
                                                                                                                                                                                child: const Text(
                                                                                                                                                                                                            '집사님! 저 왔어요냥~',
                                                                                                                                                                                                            style:
                                                                                                                                                                                                                TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                                                                                                                                                                                          ),
                                                                                                                                                                              ),
                                                                                                                                                    ),
                                                                                                                            ),
                                                                                                      ),

                                                                                    // "냥냥이톡" 타이틀.
                                                                                    Align(
                                                                                                        alignment: const Alignment(0, 0.55),
                                                                                                        child: Opacity(
                                                                                                                              opacity: titleOpacity,
                                                                                                                              child: Transform.scale(
                                                                                                                                                      scale: 0.85 + 0.15 * titleOpacity,
                                                                                                                                                      child: const Text(
                                                                                                                                                                                '냥냥이톡',
                                                                                                                                                                                style: TextStyle(
                                                                                                                                                                                                            fontSize: 40,
                                                                                                                                                                                                            fontWeight: FontWeight.bold,
                                                                                                                                                                                                            color: Color(0xFFFF9933),
                                                                                                                                                                                                          ),
                                                                                                                                                                              ),
                                                                                                                                                    ),
                                                                                                                            ),
                                                                                                      ),
                                                                                  ],
                                                                );
                                    },
                                  ),
                      );
      }
}
