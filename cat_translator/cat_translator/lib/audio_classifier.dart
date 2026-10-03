import 'dart:async';
import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';

/// YAMNet(AudioSet 사전학습) TFLite 모델을 읽어서, 1초 안팎의 오디오
/// 버퍼를 넣으면 521개 AudioSet 클래스에 대한 점수를 돌려준다.
///
/// 모델/라벨 파일은 커밋되어 있지 않고, GitHub Actions 빌드 시
/// tools/fetch_model.py 가 내려받아 assets/models/ 에 넣어준다.
class AudioClassifier {
  Interpreter? _interpreter;
  List<String> _labels = [];
  int _inputLength = 15600; // YAMNet 기본 입력 길이(약 0.975초 @16kHz)
  int _scoreOutputIndex = 0;
  int _numClasses = 521;

  bool get isReady => _interpreter != null && _labels.isNotEmpty;
  List<String> get labels => _labels;
  int get inputLength => _inputLength;

  Future<void> load() async {
    final interpreter =
        await Interpreter.fromAsset('assets/models/yamnet.tflite');

    // 입력 텐서 길이 확인 (모델에 맞춰 자동으로 맞춘다).
    try {
      final inputShape = interpreter.getInputTensor(0).shape;
      final total = inputShape.fold<int>(1, (a, b) => a * (b <= 0 ? 1 : b));
      if (total > 0) _inputLength = total;
    } catch (_) {
      // 기본값(15600) 유지
    }

    // 출력 텐서 중 "클래스 점수" 텐서를 찾는다 (라벨 수와 가장 비슷한 마지막 차원).
    int bestIndex = 0;
    int bestDiff = 1 << 30;
    for (int i = 0; i < 8; i++) {
      try {
        final shape = interpreter.getOutputTensor(i).shape;
        final last = shape.isNotEmpty ? shape.last : 0;
        final diff = (last - 521).abs();
        if (diff < bestDiff) {
          bestDiff = diff;
          bestIndex = i;
          _numClasses = last;
        }
      } catch (_) {
        break;
      }
    }
    _scoreOutputIndex = bestIndex;

    final labelsText =
        await rootBundle.loadString('assets/models/yamnet_labels.txt');
    _labels = labelsText
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    _interpreter = interpreter;
  }

  /// waveform: -1.0~1.0 범위로 정규화된 16kHz mono PCM 샘플들.
  /// 모델 입력 길이에 맞춰 자르거나 0으로 채운 뒤 추론한다.
  List<double> classify(List<double> waveform) {
    final interpreter = _interpreter;
    if (interpreter == null) return List.filled(_numClasses, 0);

    final input = List<double>.filled(_inputLength, 0.0);
    final n = waveform.length < _inputLength ? waveform.length : _inputLength;
    for (int i = 0; i < n; i++) {
      input[i] = waveform[i];
    }

    final output =
        List.generate(1, (_) => List<double>.filled(_numClasses, 0.0));

    try {
      interpreter.run(input, output);
      return output[0];
    } catch (_) {
      // 입력 텐서가 1차원 그대로를 요구하는 모델도 있어 한 번 더 시도.
      try {
        final flatOutput = List<double>.filled(_numClasses, 0.0);
        interpreter.runForMultipleInputs([input], {_scoreOutputIndex: flatOutput});
        return flatOutput;
      } catch (_) {
        return List.filled(_numClasses, 0.0);
      }
    }
  }

  void close() {
    _interpreter?.close();
    _interpreter = null;
  }
}
