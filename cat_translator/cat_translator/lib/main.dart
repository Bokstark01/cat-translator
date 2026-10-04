import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import 'audio_classifier.dart';
import 'cat_situation.dart';
import 'cat_sound_mapper.dart';
import 'feedback_store.dart';
import 'intro_screen.dart';

void main() {
      WidgetsFlutterBinding.ensureInitialized();
      MobileAds.instance.initialize();
      runApp(const CatTranslatorApp());
}

/// 한국어 주격 조사 "이/가"를 이름의 받침 유무에 따라 올바르게 붙여준다.
/// 예: "나비" -> "나비가", "구름이" -> "구름이가".
String withSubjectParticle(String name) {
      if (name.isEmpty) return name;
      final lastChar = name.runes.last;
      const hangulBase = 0xAC00; // '가'
      const hangulEnd = 0xD7A3; // '힣'
      if (lastChar >= hangulBase && lastChar <= hangulEnd) {
              final hasBatchim = (lastChar - hangulBase) % 28 != 0;
              return hasBatchim ? '$name이' : '$name가';
      }
      return '$name가';
}

class CatTranslatorApp extends StatelessWidget {
      const CatTranslatorApp({super.key});

      @override
      Widget build(BuildContext context) {
              return MaterialApp(
                        title: '냥냥이톡',
                        theme: ThemeData(
                                    colorSchemeSeed: const Color(0xFFFF9933),
                                    useMaterial3: true,
                                  ),
                        home: const IntroScreen(),
                      );
      }
}

/// 채팅방 안의 한 줄: 고양이가 보낸 "말풍선" 메시지이거나,
/// 가운데 작게 뜨는 "시스템 알림" 메시지.
class ChatEntry {
      final bool isSystem;
      final CatSituation? situation;
      final double confidence;
      final DateTime time;
      final String? systemText;
      bool? feedbackCorrect; // null = 아직 답 안 함

      ChatEntry.system(String text)
                : isSystem = true,
            situation = null,
            confidence = 0,
            time = DateTime.now(),
            systemText = text,
            feedbackCorrect = null;

      ChatEntry.cat(CatSituation situation, double confidence)
                : isSystem = false,
            situation = situation,
            confidence = confidence,
            time = DateTime.now(),
            systemText = null,
            feedbackCorrect = null;
}

class ChatHomePage extends StatefulWidget {
      const ChatHomePage({super.key, this.catName = '냥냥이'});

      /// 사용자가 인트로 다음 화면에서 입력한 고양이 이름.
      final String catName;

      @override
      State<ChatHomePage> createState() => _ChatHomePageState();
}

class _ChatHomePageState extends State<ChatHomePage> {
      final _recorder = AudioRecorder();
      final _classifier = AudioClassifier();
      final _tts = FlutterTts();
      final _featureExtractor = SimpleFeatureExtractor(16000);
      final _feedbackStore = FeedbackStore();
      final _scrollController = ScrollController();

      StreamSubscription<Uint8List>? _micSub;
      final List<int> _pcmBuffer = [];
      static const int _sampleRate = 16000;

      bool _isListening = false;
      bool _modelReady = false;
      String _headerStatus = '준비 중...';
      DateTime? _lastSpokenAt;
      CatSituation? _lastSpokenSituation;
      final List<DateTime> _recentDetectionTimes = [];
      int _consecutiveCatStreak = 0;
      DateTime? _lastCatWindowAt;

      final List<ChatEntry> _messages = [];

      // 화면 하단 배너 광고 (테스트 광고 ID 사용).
      BannerAd? _bannerAd;
      bool _isBannerReady = false;
      static const String _testBannerAdUnitId =
                'ca-app-pub-3940256099942544/6300978111';

      @override
      void initState() {
              super.initState();
              _messages.add(
                        ChatEntry.system('${withSubjectParticle(widget.catName)} 채팅방에 들어왔어요 🐾'),
                      );
              _init();
              _loadBannerAd();
      }

      Future<void> _init() async {
              _tts.setLanguage('ko-KR');
              try {
                        await _classifier.load();
                        setState(() {
                                    _modelReady = true;
                                    _headerStatus = '대기 중';
                        });
              } catch (e) {
                        setState(() {
                                    _headerStatus = '모델 로드 실패';
                        });
                        _addSystemMessage('모델을 불러오지 못했어요: $e');
              }
      }

      void _loadBannerAd() {
              _bannerAd = BannerAd(
                        adUnitId: _testBannerAdUnitId,
                        size: AdSize.banner,
                        request: const AdRequest(),
                        listener: BannerAdListener(
                                    onAdLoaded: (ad) {
                                                  if (!mounted) return;
                                                  setState(() => _isBannerReady = true);
                                    },
                                    onAdFailedToLoad: (ad, error) {
                                                  ad.dispose();
                                    },
                                  ),
                      )..load();
      }

      void _addSystemMessage(String text) {
              setState(() {
                        _messages.add(ChatEntry.system(text));
              });
              _scrollToBottom();
      }

      void _scrollToBottom() {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!_scrollController.hasClients) return;
                        _scrollController.animateTo(
                                    _scrollController.position.maxScrollExtent,
                                    duration: const Duration(milliseconds: 250),
                                    curve: Curves.easeOut,
                                  );
              });
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
                        _addSystemMessage('마이크 권한이 필요해요');
                        return;
              }

              if (!await _recorder.hasPermission()) {
                        _addSystemMessage('마이크 권한이 필요해요');
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
                        _headerStatus = '듣고 있어요...';
              });
              _addSystemMessage('듣기 시작! 소리를 기다리고 있어요 👂');
      }

      Future<void> _stopListening() async {
              await _micSub?.cancel();
              _micSub = null;
              await _recorder.stop();
              setState(() {
                        _isListening = false;
                        _headerStatus = '대기 중';
              });
              _addSystemMessage('듣기를 멈췄어요');
      }

      void _onAudioChunk(Uint8List bytes) {
              final byteData = ByteData.sublistView(bytes);
              for (int i = 0; i + 1 < bytes.length; i += 2) {
                        _pcmBuffer.add(byteData.getInt16(i, Endian.little));
              }

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
                        _consecutiveCatStreak = 0;
                        return;
              }

              final now = DateTime.now();
              _recentDetectionTimes.add(now);
              _recentDetectionTimes.removeWhere(
                          (t) => now.difference(t) > const Duration(seconds: 6));

              if (_lastCatWindowAt != null &&
                          now.difference(_lastCatWindowAt!) <=
                              const Duration(milliseconds: 1500)) {
                        _consecutiveCatStreak += 1;
              } else {
                        _consecutiveCatStreak = 1;
              }
              _lastCatWindowAt = now;

              final features = AudioFeatures(
                        rms: _featureExtractor.rms(waveform),
                        pitchHz: _featureExtractor.approxPitchHz(waveform),
                        durationMs: (_consecutiveCatStreak * 1000).toDouble(),
                        repetitionCount: _recentDetectionTimes.length,
                        hourOfDay: now.hour,
                      );

              final situation = mapToSituation(catResult.subLabel, features);
              _maybeSpeak(situation, catResult.confidence);
      }

      void _maybeSpeak(CatSituation situation, double confidence) {
              final now = DateTime.now();
              final sameAsLast = situation == _lastSpokenSituation;
              final cooledDown = _lastSpokenAt == null ||
                          now.difference(_lastSpokenAt!) > const Duration(seconds: 6);

              if (sameAsLast && !cooledDown) return;
              if (!cooledDown) return;

              _lastSpokenAt = now;
              _lastSpokenSituation = situation;

              setState(() {
                        _messages.add(ChatEntry.cat(situation, confidence));
              });
              _scrollToBottom();

              final phrase = kSituationInfo[situation]!.spokenPhrase;
              _tts.speak(phrase);
      }

      Future<void> _giveFeedback(ChatEntry entry, bool correct) async {
              if (entry.situation == null) return;
              await _feedbackStore.add(
                          FeedbackEntry(DateTime.now(), entry.situation!, correct));
              if (!mounted) return;
              setState(() {
                        entry.feedbackCorrect = correct;
              });
      }

      Future<void> _confirmExit() async {
              final shouldExit = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                                    title: const Text('냥냥이톡 나가기'),
                                    content: const Text('채팅방을 나가고 앱을 종료할까요?'),
                                    actions: [
                                                  TextButton(
                                                                  onPressed: () => Navigator.of(ctx).pop(false),
                                                                  child: const Text('취소'),
                                                                ),
                                                  FilledButton(
                                                                  onPressed: () => Navigator.of(ctx).pop(true),
                                                                  child: const Text('나가기'),
                                                                ),
                                                ],
                                  ),
                      );
              if (shouldExit == true) {
                        await _stopListeningQuietly();
                        SystemNavigator.pop();
              }
      }

      Future<void> _stopListeningQuietly() async {
              if (_isListening) {
                        await _micSub?.cancel();
                        _micSub = null;
                        await _recorder.stop();
              }
      }

      @override
      void dispose() {
              _micSub?.cancel();
              _recorder.dispose();
              _classifier.close();
              _scrollController.dispose();
              _bannerAd?.dispose();
              super.dispose();
      }

      @override
      Widget build(BuildContext context) {
              return Scaffold(
                        backgroundColor: const Color(0xFFE9E3D8),
                        appBar: _buildChatAppBar(context),
                        body: SafeArea(
                                    child: Column(
                                                  children: [
                                                                  Expanded(
                                                                                    child: ListView.builder(
                                                                                                        controller: _scrollController,
                                                                                                        padding:
                                                                                                            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                                                                                        itemCount: _messages.length,
                                                                                                        itemBuilder: (context, index) => _buildEntry(_messages[index]),
                                                                                                      ),
                                                                                  ),
                                                                  _buildInputBar(),
                                                                  _buildBannerAd(),
                                                                ],
                                                ),
                                  ),
                      );
      }

      Widget _buildBannerAd() {
              if (!_isBannerReady || _bannerAd == null) {
                        return const SizedBox.shrink();
              }
              return Container(
                        width: double.infinity,
                        color: Colors.white,
                        alignment: Alignment.center,
                        child: SizedBox(
                                    width: _bannerAd!.size.width.toDouble(),
                                    height: _bannerAd!.size.height.toDouble(),
                                    child: AdWidget(ad: _bannerAd!),
                                  ),
                      );
      }

      PreferredSizeWidget _buildChatAppBar(BuildContext context) {
              return AppBar(
                        backgroundColor: const Color(0xFFFFB84D),
                        elevation: 1,
                        titleSpacing: 8,
                        title: Row(
                                    children: [
                                                  const CircleAvatar(
                                                                  radius: 18,
                                                                  backgroundColor: Colors.white,
                                                                  child: Text('🐱', style: TextStyle(fontSize: 20)),
                                                                ),
                                                  const SizedBox(width: 10),
                                                  Column(
                                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                                  mainAxisSize: MainAxisSize.min,
                                                                  children: [
                                                                                    const Text('냥냥이톡',
                                                                                                                 style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                                                                    Text(_headerStatus,
                                                                                                           style: const TextStyle(fontSize: 12, color: Colors.black54)),
                                                                                  ],
                                                                ),
                                                ],
                                  ),
                        actions: [
                                    IconButton(
                                                  tooltip: '채팅방 나가기',
                                                  icon: const Icon(Icons.exit_to_app),
                                                  onPressed: _confirmExit,
                                                ),
                                  ],
                      );
      }

      Widget _buildEntry(ChatEntry entry) {
              if (entry.isSystem) {
                        return Center(
                                    child: Container(
                                                  margin: const EdgeInsets.symmetric(vertical: 8),
                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                  decoration: BoxDecoration(
                                                                  color: Colors.black.withValues(alpha: 0.35),
                                                                  borderRadius: BorderRadius.circular(14),
                                                                ),
                                                  child: Text(
                                                                  entry.systemText ?? '',
                                                                  style: const TextStyle(color: Colors.white, fontSize: 12),
                                                                ),
                                                ),
                                  );
              }

              final info = kSituationInfo[entry.situation]!;
              final timeLabel = _formatTime(entry.time);

              return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                                  CircleAvatar(
                                                                  radius: 18,
                                                                  backgroundColor: Colors.white,
                                                                  child: Text(info.emoji, style: const TextStyle(fontSize: 18)),
                                                                ),
                                                  const SizedBox(width: 8),
                                                  Flexible(
                                                                  child: Column(
                                                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                                                    children: [
                                                                                                        Padding(
                                                                                                                              padding: const EdgeInsets.only(bottom: 2, left: 2),
                                                                                                                              child: Text(
                                                                                                                                                      info.koreanLabel,
                                                                                                                                                      style: const TextStyle(fontSize: 11, color: Colors.black54),
                                                                                                                                                    ),
                                                                                                                            ),
                                                                                                        Row(
                                                                                                                              crossAxisAlignment: CrossAxisAlignment.end,
                                                                                                                              mainAxisSize: MainAxisSize.min,
                                                                                                                              children: [
                                                                                                                                                      Flexible(
                                                                                                                                                                                child: Container(
                                                                                                                                                                                                            padding: const EdgeInsets.symmetric(
                                                                                                                                                                                                                                            horizontal: 14, vertical: 10),
                                                                                                                                                                                                            decoration: BoxDecoration(
                                                                                                                                                                                                                                          color: Colors.white,
                                                                                                                                                                                                                                          borderRadius: const BorderRadius.only(
                                                                                                                                                                                                                                                                          topLeft: Radius.circular(4),
                                                                                                                                                                                                                                                                          topRight: Radius.circular(16),
                                                                                                                                                                                                                                                                          bottomLeft: Radius.circular(16),
                                                                                                                                                                                                                                                                          bottomRight: Radius.circular(16),
                                                                                                                                                                                                                                                                        ),
                                                                                                                                                                                                                                          boxShadow: [
                                                                                                                                                                                                                                                                          BoxShadow(
                                                                                                                                                                                                                                                                                                            color: Colors.black.withValues(alpha: 0.08),
                                                                                                                                                                                                                                                                                                            blurRadius: 3,
                                                                                                                                                                                                                                                                                                            offset: const Offset(0, 1),
                                                                                                                                                                                                                                                                                                          ),
                                                                                                                                                                                                                                                                        ],
                                                                                                                                                                                                                                        ),
                                                                                                                                                                                                            child: Text(
                                                                                                                                                                                                                                          '${info.emoji} ${info.spokenPhrase}',
                                                                                                                                                                                                                                          style: const TextStyle(fontSize: 15, height: 1.3),
                                                                                                                                                                                                                                        ),
                                                                                                                                                                                                          ),
                                                                                                                                                                              ),
                                                                                                                                                      const SizedBox(width: 6),
                                                                                                                                                      Text(timeLabel,
                                                                                                                                                                                   style:
                                                                                                                                                                                       const TextStyle(fontSize: 10, color: Colors.black45)),
                                                                                                                                                    ],
                                                                                                                            ),
                                                                                                        const SizedBox(height: 4),
                                                                                                        _buildFeedbackRow(entry),
                                                                                                      ],
                                                                                  ),
                                                                ),
                                                ],
                                  ),
                      );
      }

      Widget _buildFeedbackRow(ChatEntry entry) {
              if (entry.feedbackCorrect != null) {
                        return Padding(
                                    padding: const EdgeInsets.only(left: 4),
                                    child: Text(
                                                  entry.feedbackCorrect! ? '맞다고 알려주셨어요 💛' : '아니라고 알려주셨어요, 더 배울게요냥',
                                                  style: const TextStyle(fontSize: 11, color: Colors.black45),
                                                ),
                                  );
              }
              return Padding(
                        padding: const EdgeInsets.only(left: 2),
                        child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                                  _feedbackChip(
                                                                  label: '👍 맞아요',
                                                                  color: const Color(0xFFDFF5E3),
                                                                  onTap: () => _giveFeedback(entry, true),
                                                                ),
                                                  const SizedBox(width: 6),
                                                  _feedbackChip(
                                                                  label: '👎 아니에요',
                                                                  color: const Color(0xFFFCE1E1),
                                                                  onTap: () => _giveFeedback(entry, false),
                                                                ),
                                                ],
                                  ),
                      );
      }

      Widget _feedbackChip({
              required String label,
              required Color color,
              required VoidCallback onTap,
      }) {
              return InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: onTap,
                        child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                                  color: color,
                                                  borderRadius: BorderRadius.circular(14),
                                                ),
                                    child: Text(label, style: const TextStyle(fontSize: 12)),
                                  ),
                      );
      }

      Widget _buildInputBar() {
              return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: const BoxDecoration(
                                    color: Colors.white,
                                    border: Border(top: BorderSide(color: Color(0xFFE0E0E0))),
                                  ),
                        child: SafeArea(
                                    top: false,
                                    bottom: false,
                                    child: Row(
                                                  children: [
                                                                  Expanded(
                                                                                    child: Container(
                                                                                                        padding:
                                                                                                            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                                                                                        decoration: BoxDecoration(
                                                                                                                              color: const Color(0xFFF3F3F3),
                                                                                                                              borderRadius: BorderRadius.circular(20),
                                                                                                                            ),
                                                                                                        child: Text(
                                                                                                                              _isListening
                                                                                                                                  ? '${widget.catName}의 소리를 듣고 있어요...'
                                                                                                                                  : (_modelReady ? '마이크 버튼을 눌러 듣기를 시작하세요' : '모델 준비 중...'),
                                                                                                                              style: const TextStyle(color: Colors.black54, fontSize: 13),
                                                                                                                            ),
                                                                                                      ),
                                                                                  ),
                                                                  const SizedBox(width: 10),
                                                                  GestureDetector(
                                                                                    onTap: _modelReady ? _toggleListening : null,
                                                                                    child: CircleAvatar(
                                                                                                        radius: 24,
                                                                                                        backgroundColor:
                                                                                                            _isListening ? Colors.redAccent : const Color(0xFFFFB84D),
                                                                                                        child: Icon(
                                                                                                                              _isListening ? Icons.stop : Icons.mic,
                                                                                                                              color: Colors.white,
                                                                                                                            ),
                                                                                                      ),
                                                                                  ),
                                                                ],
                                                ),
                                  ),
                      );
      }

      String _formatTime(DateTime t) {
              final hour24 = t.hour;
              final isAm = hour24 < 12;
              final hour12raw = hour24 % 12;
              final hour12 = hour12raw == 0 ? 12 : hour12raw;
              final minute = t.minute.toString().padLeft(2, '0');
              return '${isAm ? '오전' : '오후'} $hour12:$minute';
      }
}
