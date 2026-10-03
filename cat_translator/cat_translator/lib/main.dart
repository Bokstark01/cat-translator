import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import 'audio_classifier.dart';
import 'cat_situation.dart';
import 'cat_sound_mapper.dart';
import 'feedback_store.dart';

void main() {
  runApp(const CatTranslatorApp());
}

class CatTranslatorApp extends StatelessWidget {
  const CatTranslatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '고양이 번역',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFFFF9933),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _recorder = AudioRecorder();
  final _classifier = AudioClassifier();
  final _tts = FlutterTts();
  final _featureExtractor = SimpleFeatureExtractor(16000);
  final _feedbackStore = FeedbackStore();

  StreamSubscription<Uint8List>? _micSub;
  final List<int> _pcmBuffer = [];
  static const int _sampleRate = 16000;

  bool _isListening = false;
  bool _modelReady = false;
  String _status = '준비 중...';
  CatSituation? _lastSituation;
  double _lastConfidence = 0;
  DateTime? _lastSpokenAt;
  CatSituation? _lastSpokenSituation;
  final List<DateTime> _recentDetectionTimes = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _tts.setLanguage('ko-KR');
    try {
      await _classifier.load();
      setState(() {
        _modelReady = true;
        _status = '모델 준비 완료. 시작 버튼을 눌러주세요.';
      });
    } catch (e) {
      setState(() {
        _status = '모델을 불러오지 못했어요: $e';
      });
    }
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _stopListening();
    } else {
      await _startListening();
    }
  }

  Future<void> _startListening() async {
    if (!_modelReady) return;

    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      setState(() => _status = '마이크 권한이 필요해요.');
      return;
    }

    if (!await _recorder.hasPermission()) {
      setState(() => _status = '마이크 권한이 필요해요.');
      return;
    }

    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _sampleRate,
        numChannels: 1,
      ),
    );

    _pcmBuffer.clear();
    _micSub = stream.listen(_onAudioChunk);

    setState(() {
      _isListening = true;
      _status = '고양이 소리를 듣고 있어요...';
    });
  }

  Future<void> _stopListening() async {
    await _micSub?.cancel();
    _micSub = null;
    await _recorder.stop();
    setState(() {
      _isListening = false;
      _status = '멈췄어요. 다시 시작하려면 버튼을 눌러주세요.';
    });
  }

  void _onAudioChunk(Uint8List bytes) {
    // PCM16LE -> Int16 샘플로 변환해 버퍼에 쌓는다.
    final byteData = ByteData.sublistView(bytes);
    for (int i = 0; i + 1 < bytes.length; i += 2) {
      _pcmBuffer.add(byteData.getInt16(i, Endian.little));
    }

    // 약 1초(16000 샘플)가 모이면 한 번 분류를 돌린다.
    const windowSize = _sampleRate;
    while (_pcmBuffer.length >= windowSize) {
      final windowInts = _pcmBuffer.sublist(0, windowSize);
      _pcmBuffer.removeRange(0, windowSize);
      final waveform =
          windowInts.map((s) => s / 32768.0).toList(growable: false);
      _processWindow(waveform);
    }
  }

  void _processWindow(List<double> waveform) {
    final scores = _classifier.classify(waveform);
    final catResult = pickCatSubLabel(scores, _classifier.labels);

    if (!catResult.isCatSound) {
      return; // 고양이 소리가 아니면 조용히 무시.
    }

    final now = DateTime.now();
    _recentDetectionTimes.add(now);
    _recentDetectionTimes.removeWhere(
        (t) => now.difference(t) > const Duration(seconds: 6));

    final features = AudioFeatures(
      rms: _featureExtractor.rms(waveform),
      pitchHz: _featureExtractor.approxPitchHz(waveform),
      durationMs: 1000,
      repetitionCount: _recentDetectionTimes.length,
      hourOfDay: now.hour,
    );

    final situation = mapToSituation(catResult.subLabel, features);

    setState(() {
      _lastSituation = situation;
      _lastConfidence = catResult.confidence;
    });

    _maybeSpeak(situation);
  }

  void _maybeSpeak(CatSituation situation) {
    final now = DateTime.now();
    final sameAsLast = situation == _lastSpokenSituation;
    final cooledDown = _lastSpokenAt == null ||
        now.difference(_lastSpokenAt!) > const Duration(seconds: 6);

    if (sameAsLast && !cooledDown) return;
    if (!cooledDown) return;

    _lastSpokenAt = now;
    _lastSpokenSituation = situation;
    final phrase = kSituationInfo[situation]!.spokenPhrase;
    _tts.speak(phrase);
  }

  Future<void> _giveFeedback(bool correct) async {
    if (_lastSituation == null) return;
    await _feedbackStore.add(FeedbackEntry(DateTime.now(), _lastSituation!, correct));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(correct ? '고마워요! 기록했어요.' : '알려줘서 고마워요, 더 나아질게요.')),
    );
  }

  @override
  void dispose() {
    _micSub?.cancel();
    _recorder.dispose();
    _classifier.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final info = _lastSituation != null ? kSituationInfo[_lastSituation!] : null;

    return Scaffold(
      appBar: AppBar(title: const Text('고양이 번역')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_status, style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 24),
              Expanded(
                child: Center(
                  child: info == null
                      ? const Text('아직 감지된 소리가 없어요.',
                          style: TextStyle(fontSize: 18))
                      : Card(
                          elevation: 3,
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(info.koreanLabel,
                                    style: const TextStyle(
                                        fontSize: 26, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 12),
                                Text(info.spokenPhrase,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 18)),
                                const SizedBox(height: 8),
                                Text(
                                    '신뢰도: ${(_lastConfidence * 100).toStringAsFixed(0)}%',
                                    style: const TextStyle(color: Colors.grey)),
                                const SizedBox(height: 16),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    ElevatedButton(
                                      onPressed: () => _giveFeedback(true),
                                      child: const Text('맞아요'),
                                    ),
                                    const SizedBox(width: 12),
                                    OutlinedButton(
                                      onPressed: () => _giveFeedback(false),
                                      child: const Text('아니에요'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _modelReady ? _toggleListening : null,
                icon: Icon(_isListening ? Icons.stop : Icons.mic),
                label: Text(_isListening ? '그만 듣기' : '듣기 시작'),
              ),
              const SizedBox(height: 8),
              const Text(
                '앱을 열어둔 상태에서만 소리를 듣고 번역해요.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
