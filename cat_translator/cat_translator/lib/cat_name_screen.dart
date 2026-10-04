import 'package:flutter/material.dart';

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
                  backgroundColor: const Color(0xFFFFF3E0),
                  body: SafeArea(
                            child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 28),
                                        child: Column(
                                                      mainAxisAlignment: MainAxisAlignment.center,
                                                      children: [
                                                                      const Text('🐱', style: TextStyle(fontSize: 72)),
                                                                      const SizedBox(height: 20),
                                                                      const Text(
                                                                                        '우리 고양이 이름이 뭔가요?',
                                                                                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                                                                        textAlign: TextAlign.center,
                                                                                      ),
                                                                      const SizedBox(height: 8),
                                                                      const Text(
                                                                                        '채팅방에서 이 이름으로 불러드릴게요',
                                                                                        style: TextStyle(fontSize: 13, color: Colors.black54),
                                                                                        textAlign: TextAlign.center,
                                                                                      ),
                                                                      const SizedBox(height: 28),
                                                                      TextField(
                                                                                        controller: _controller,
                                                                                        textAlign: TextAlign.center,
                                                                                        autofocus: true,
                                                                                        onSubmitted: (_) => _start(),
                                                                                        decoration: InputDecoration(
                                                                                                            hintText: '예: 나비',
                                                                                                            filled: true,
                                                                                                            fillColor: Colors.white,
                                                                                                            contentPadding: const EdgeInsets.symmetric(
                                                                                                                                    horizontal: 16, vertical: 14),
                                                                                                            border: OutlineInputBorder(
                                                                                                                                  borderRadius: BorderRadius.circular(16),
                                                                                                                                  borderSide: BorderSide.none,
                                                                                                                                ),
                                                                                                          ),
                                                                                      ),
                                                                      const SizedBox(height: 20),
                                                                      SizedBox(
                                                                                        width: double.infinity,
                                                                                        child: FilledButton(
                                                                                                            style: FilledButton.styleFrom(
                                                                                                                                  backgroundColor: const Color(0xFFFF9933),
                                                                                                                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                                                                                                                  shape: RoundedRectangleBorder(
                                                                                                                                                          borderRadius: BorderRadius.circular(16),
                                                                                                                                                        ),
                                                                                                                                ),
                                                                                                            onPressed: _start,
                                                                                                            child: const Text(
                                                                                                                                  '시작하기',
                                                                                                                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                                                                                                                ),
                                                                                                          ),
                                                                                      ),
                                                                      TextButton(
                                                                                        onPressed: _start,
                                                                                        child: const Text(
                                                                                                            '나중에 정할게요',
                                                                                                            style: TextStyle(color: Colors.black45),
                                                                                                          ),
                                                                                      ),
                                                                    ],
                                                    ),
                                      ),
                          ),
                );
    }
}
