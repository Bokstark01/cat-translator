import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'cat_situation.dart';

/// 사용자가 "맞아요/아니에요"로 눌러준 피드백을 기기에 간단히 저장한다.
/// (추후 2단계 로드맵: 이 기록을 모아 고양이별 개인화 모델 학습에 사용)
class FeedbackEntry {
    final DateTime time;
    final CatSituation predicted;
    final bool wasCorrect;
    // "아니에요"를 고른 뒤 사용자가 직접 골라준 실제 상태 (정답).
    final CatSituation? correctedSituation;

    FeedbackEntry(this.time, this.predicted, this.wasCorrect,
                        [this.correctedSituation]);

    Map<String, dynamic> toJson() => {
              'time': time.toIso8601String(),
              'predicted': predicted.name,
              'correct': wasCorrect,
              if (correctedSituation != null) 'corrected': correctedSituation!.name,
    };

    static FeedbackEntry fromJson(Map<String, dynamic> json) => FeedbackEntry(
              DateTime.parse(json['time'] as String),
              CatSituation.values.byName(json['predicted'] as String),
              json['correct'] as bool,
              json['corrected'] != null
                  ? CatSituation.values.byName(json['corrected'] as String)
                  : null,
            );
}

class FeedbackStore {
    static const _key = 'cat_feedback_log_v1';

    Future<void> add(FeedbackEntry entry) async {
          final prefs = await SharedPreferences.getInstance();
          final list = prefs.getStringList(_key) ?? [];
          list.add(jsonEncode(entry.toJson()));
          if (list.length > 2000) {
                  list.removeRange(0, list.length - 2000);
          }
          await prefs.setStringList(_key, list);
    }

    Future<List<FeedbackEntry>> loadAll() async {
          final prefs = await SharedPreferences.getInstance();
          final list = prefs.getStringList(_key) ?? [];
          return list
                    .map((s) => FeedbackEntry.fromJson(jsonDecode(s) as Map<String, dynamic>))
                    .toList();
    }

    Future<({int correct, int total})> stats() async {
          final all = await loadAll();
          final correct = all.where((e) => e.wasCorrect).length;
          return (correct: correct, total: all.length);
    }
}
