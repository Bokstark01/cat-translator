import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'main.dart';

/// 인트로 애니메이션 다음에 보여주는 화면.
/// 사용자에게 고양이 이름을 입력받아 채팅방 전체에서 그 이름으로 부른다.
class CatNameScreen extends StatefulWidget {
  const CatNameScreen({super.key});

  @override
  State<CatNameScreen> createState() => _CatNameScreenState();
}

class _CatNameScreenState extends State<CatNameScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _start() {
    final name = _controller.text.trim();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ChatHomePage(catName: name.isEmpty ? '냥냥이' : name),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NyangColors.chatTop,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [NyangColors.lavenderTop, NyangColors.chatBottom],
            stops: [0.0, 0.62],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/images/cat_mascot.png',
                    height: 150,
                    filterQuality: FilterQuality.medium,
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    '우리 고양이 이름이 뭔가요?',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                      color: NyangColors.ink,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '채팅방에서 이 이름으로 불러드릴게요',
                    style: TextStyle(fontSize: 13, color: NyangColors.muted),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: NyangColors.shadow.withValues(alpha: 0.10),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _controller,
                      textAlign: TextAlign.center,
                      autofocus: true,
                      onSubmitted: (_) => _start(),
                      style: const TextStyle(
                          fontSize: 16, color: NyangColors.ink),
                      cursorColor: NyangColors.lavender,
                      decoration: InputDecoration(
                        hintText: '예: 나비',
                        hintStyle: const TextStyle(color: Color(0xFFB9B2D6)),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 16),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: const BorderSide(
                              color: NyangColors.lavenderSoft, width: 1.4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _GradientButton(label: '시작하기', onTap: _start),
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: _start,
                    child: const Text(
                      '나중에 정할게요',
                      style: TextStyle(color: NyangColors.muted),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 연보라 그라데이션 + 은은한 그림자의 둥근 버튼 (눌렀을 때 살짝 작아짐).
class _GradientButton extends StatefulWidget {
  const _GradientButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<_GradientButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutBack,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: NyangGradients.lavenderButton,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: NyangColors.lavender.withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Text(
            widget.label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
