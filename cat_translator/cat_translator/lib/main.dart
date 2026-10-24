import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import 'app_theme.dart';
import 'audio_classifier.dart';
import 'cat_cue.dart';
import 'cat_situation.dart';
import 'cat_sound_mapper.dart';
import 'feedback_store.dart';
import 'intro_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MobileAds.instance.initialize();
  runApp(const CatTranslatorApp());
}

/// 한국어 문장이 단어 중간("써보세/요")에서 줄바꿈되지 않도록,
/// 각 단어 글자 사이에 보이지 않는 연결 문자(U+2060)를 넣어 띄어쓰기에서만 끊기게 한다.
String keepWords(String text) {
  return text
      .split(' ')
      .map((w) => w.characters.join('\u2060'))
      .join(' ');
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

/// 한국어 보조사 "은/는"을 이름의 받침 유무에 따라 올바르게 붙여준다.
/// 예: "나비" -> "나비는", "구름이" -> "구름이는".
String withTopicParticle(String name) {
  if (name.isEmpty) return name;
  final lastChar = name.runes.last;
  const hangulBase = 0xAC00; // '가'
  const hangulEnd = 0xD7A3; // '힣'
  if (lastChar >= hangulBase && lastChar <= hangulEnd) {
    final hasBatchim = (lastChar - hangulBase) % 28 != 0;
    return hasBatchim ? '$name은' : '$name는';
  }
  return '$name는';
}

class CatTranslatorApp extends StatelessWidget {
  const CatTranslatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '냥냥이톡',
      theme: buildNyangTheme(),
      home: const IntroScreen(),
    );
  }
}

/// 채팅방 안의 한 줄: 고양이가 보낸 "말풍선" 메시지이거나,
/// 가운데 작게 뜨는 "시스템 알림" 메시지.
class ChatEntry {
  final bool isSystem;
  // 사용자가 "말 걸기"로 고양이에게 신호음을 들려준 메시지인 경우.
  final bool isUser;
  final CatSituation? situation;
  final CatCue? cue;
  final double confidence;
  final DateTime time;
  final String? systemText;
  // "아니에요" 선택 시 보여줄, 실제 상태일 확률이 높은 대안 후보 (상위 3개).
  final List<CatSituation> alternatives;
  bool? feedbackCorrect; // null = 아직 답 안 함
  // "아니에요"를 고른 뒤 사용자가 직접 골라준 실제 상태.
  CatSituation? correctedSituation;
  // "아니에요" 고른 뒤 "사람이 흉내낸 소리였어요"를 선택한 경우.
  bool isHumanMimicry = false;

  ChatEntry.system(String text)
      : isSystem = true,
        isUser = false,
        situation = null,
        cue = null,
        confidence = 0,
        time = DateTime.now(),
        systemText = text,
        alternatives = const [],
        feedbackCorrect = null,
        correctedSituation = null;

  ChatEntry.cat(CatSituation situation, double confidence,
      {this.alternatives = const []})
      : isSystem = false,
        isUser = false,
        situation = situation,
        cue = null,
        confidence = confidence,
        time = DateTime.now(),
        systemText = null,
        feedbackCorrect = null,
        correctedSituation = null;

  ChatEntry.user(CatCue cue)
      : isSystem = false,
        isUser = true,
        situation = null,
        cue = cue,
        confidence = 0,
        time = DateTime.now(),
        systemText = null,
        alternatives = const [],
        feedbackCorrect = null,
        correctedSituation = null;
}
class ChatHomePage extends StatefulWidget {
  const ChatHomePage({super.key, this.catName = '냥냥이'});

  /// 사용자가 인트로 다음 화면에서 입력한 고양이 이름.
  final String catName;

  @override
  State<ChatHomePage> createState() => _ChatHomePageState();
}

class _ChatHomePageState extends State<ChatHomePage>
    with WidgetsBindingObserver {
  final _recorder = AudioRecorder();
  final _classifier = AudioClassifier();
  final _tts = FlutterTts();
  final _featureExtractor = SimpleFeatureExtractor(16000);
  final _feedbackStore = FeedbackStore();
  final _scrollController = ScrollController();
  final _cuePlayer = AudioPlayer();

  StreamSubscription<Uint8List>? _micSub;
  final List<int> _pcmBuffer = [];
  static const int _sampleRate = 16000;

  bool _isListening = false;
  // 앱이 백그라운드로 가면서 듣기를 멈췄는지. 화면으로 돌아오면 다시 켠다.
  // (안드로이드 9+는 백그라운드 앱의 마이크 입력을 무음으로 막기 때문에,
  // 멈추지 않으면 "듣고 있어요"만 뜬 채 실제로는 아무것도 못 듣는다.)
  bool _resumeListeningOnForeground = false;
  // 생명주기 이벤트가 빠르게 연달아 올 때 멈춤/재시작이 겹치지 않도록 순서대로 처리한다.
  Future<void> _lifecycleTask = Future.value();
  bool _modelReady = false;
  String _headerStatus = '준비 중...';
  DateTime? _lastSpokenAt;
  CatSituation? _lastSpokenSituation;
  final List<DateTime> _recentDetectionTimes = [];
  int _consecutiveCatStreak = 0;
  DateTime? _lastCatWindowAt;

  final List<ChatEntry> _messages = [];

  // 화면 하단 배너 광고 (실 서비스용 광고 단위 ID 사용).
  BannerAd? _bannerAd;
  bool _isBannerReady = false;
  static const String _bannerAdUnitId =
      'ca-app-pub-9409942745407951/5953812982';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
      adUnitId: _bannerAdUnitId,
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

  Future<void> _startListening(
      {String startMessage = '듣기 시작! 소리를 기다리고 있어요 👂'}) async {
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
    _addSystemMessage(startMessage);
  }

  Future<void> _stopListening({String stopMessage = '듣기를 멈췄어요'}) async {
    await _micSub?.cancel();
    _micSub = null;
    await _recorder.stop();
    setState(() {
      _isListening = false;
      _headerStatus = '대기 중';
    });
    _addSystemMessage(stopMessage);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _lifecycleTask = _lifecycleTask.then((_) async {
          if (!mounted || !_isListening) return;
          _resumeListeningOnForeground = true;
          await _stopListening(stopMessage: '앱이 화면에서 벗어나서 듣기를 잠시 멈췄어요');
        });
        break;
      case AppLifecycleState.resumed:
        _lifecycleTask = _lifecycleTask.then((_) async {
          if (!mounted || !_resumeListeningOnForeground) return;
          _resumeListeningOnForeground = false;
          if (_isListening) return;
          await _startListening(startMessage: '다시 듣고 있어요 👂');
        });
        break;
      case AppLifecycleState.detached:
        break;
    }
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
    final catResult = pickCatSubLabel(
        scores, _classifier.labels, waveform, _sampleRate);

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
    final alternatives =
        topAlternativeSituations(catResult.subLabel, features, situation);
    _maybeSpeak(situation, catResult.confidence, alternatives);
  }

  void _maybeSpeak(
      CatSituation situation, double confidence, List<CatSituation> alternatives) {
    final now = DateTime.now();
    final sameAsLast = situation == _lastSpokenSituation;
    final cooledDown = _lastSpokenAt == null ||
        now.difference(_lastSpokenAt!) > const Duration(seconds: 6);

    if (sameAsLast && !cooledDown) return;
    if (!cooledDown) return;

    _lastSpokenAt = now;
    _lastSpokenSituation = situation;

    setState(() {
      _messages.add(
          ChatEntry.cat(situation, confidence, alternatives: alternatives));
    });
    _scrollToBottom();

    final phrase = kSituationInfo[situation]!.spokenPhrase;
    _tts.speak(phrase);
  }
  Future<void> _giveFeedback(ChatEntry entry, bool correct) async {
    if (entry.situation == null) return;
    if (correct) {
      await _feedbackStore.add(
          FeedbackEntry(DateTime.now(), entry.situation!, true));
    }
    if (!mounted) return;
    setState(() {
      entry.feedbackCorrect = correct;
    });
  }

  /// "아니에요" 선택 후, 사용자가 실제 상태를 골라준 경우의 처리.
  Future<void> _applyCorrection(
      ChatEntry entry, CatSituation chosen) async {
    if (entry.situation == null) return;
    await _feedbackStore.add(
        FeedbackEntry(DateTime.now(), entry.situation!, false, chosen));
    if (!mounted) return;
    setState(() {
      entry.correctedSituation = chosen;
    });
  }

  /// "아니에요" 선택 후, 사실은 사람이 흉내낸 소리였다고 알려준 경우.
  /// (진짜 고양이 상황이 아니므로 correctedSituation은 비워두고
  /// isHumanMimicry만 표시한다. 이 피드백은 추후 사람 목소리 판별
  /// 임계값을 보정하는 데 쓸 데이터로 저장된다.)
  Future<void> _markAsHumanMimicry(ChatEntry entry) async {
    if (entry.situation == null) return;
    await _feedbackStore.add(
        FeedbackEntry(DateTime.now(), entry.situation!, false, null, true));
    if (!mounted) return;
    setState(() {
      entry.isHumanMimicry = true;
    });
  }

  /// 상위 3개 선택지에 정답이 없을 때, 12가지 상황 전체 중에서
  /// 직접 골라볼 수 있는 목록을 바텀시트로 보여준다.
  Future<void> _showFullSituationPicker(ChatEntry entry) async {
    final chosen = await showModalBottomSheet<CatSituation>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final others = CatSituation.values
            .where((s) => s != entry.situation && s != CatSituation.unknown)
            .toList();
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${withTopicParticle(widget.catName)} 지금 어떤 상태인가요?',
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: NyangColors.ink),
                ),
                const SizedBox(height: 4),
                const Text(
                  '목록에 없는 상황이면 가장 가까운 걸로 골라주세요.',
                  style: TextStyle(fontSize: 12, color: NyangColors.muted),
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(ctx).size.height * 0.5),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: others.length,
                    itemBuilder: (context, index) {
                      final s = others[index];
                      final info = kSituationInfo[s]!;
                      return ListTile(
                        leading:
                            Text(info.emoji, style: const TextStyle(fontSize: 22)),
                        title: Text(info.koreanLabel),
                        onTap: () => Navigator.of(ctx).pop(s),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (chosen != null) {
      await _applyCorrection(entry, chosen);
    }
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
    WidgetsBinding.instance.removeObserver(this);
    _micSub?.cancel();
    _recorder.dispose();
    _classifier.close();
    _scrollController.dispose();
    _bannerAd?.dispose();
    _cuePlayer.dispose();
    super.dispose();
  }

  /// "말 걸기" 바텀시트에서 의도 하나를 고르면, 그에 맞는 합성 신호음을
  /// 재생하고 채팅방에 "나 -> 고양이" 메시지로 남긴다.
  Future<void> _sendCatCue(CatCue cue) async {
    try {
      await _cuePlayer.stop();
      await _cuePlayer.play(AssetSource(kCatCueInfo[cue]!.assetPath));
    } catch (e) {
      _addSystemMessage('소리를 재생하지 못했어요: $e');
    }
    if (!mounted) return;
    setState(() {
      _messages.add(ChatEntry.user(cue));
    });
    _scrollToBottom();
  }

  Future<void> _showCatCuePicker() async {
    final chosen = await showModalBottomSheet<CatCue>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final maxHeight = MediaQuery.of(ctx).size.height * 0.75;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '어떤 소리를 들려줄까요?',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: NyangColors.ink),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '실제 고양이 언어로 "번역"하는 기능은 아니에요. 주의를 끌거나\n'
                    '편안하게 해주는 데 도움이 될 수 있다고 알려진 소리예요 🐾',
                    style: TextStyle(
                        fontSize: 12, height: 1.5, color: NyangColors.muted),
                  ),
                  const SizedBox(height: 14),
                  LayoutBuilder(
                    builder: (context, c) {
                      // 두 칸이 시트 폭을 정확히 반씩 채우도록.
                      final tileW = (c.maxWidth - 12) / 2;
                      return Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          for (final cue in CatCue.values)
                            _cueTile(ctx, cue, tileW),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (chosen != null) {
      await _sendCatCue(chosen);
    }
  }

  Widget _cueTile(BuildContext ctx, CatCue cue, double width) {
    final info = kCatCueInfo[cue]!;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => Navigator.of(ctx).pop(cue),
      child: Container(
        width: width,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: NyangColors.lavenderLine),
          boxShadow: [
            BoxShadow(
              color: NyangColors.shadow.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(info.emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 6),
            Text(info.label,
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: NyangColors.ink)),
            const SizedBox(height: 4),
            Text(
              keepWords(info.description),
              style: const TextStyle(
                  fontSize: 11, height: 1.45, color: NyangColors.muted),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NyangColors.chatBottom,
      appBar: _buildChatAppBar(context),
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: NyangGradients.chatBackground),
        child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  // 아직 고양이 결과가 없을 때 보여주는 안내 (휑한 빈 화면 방지)
                  if (_messages.every((m) => m.isSystem))
                    Positioned.fill(child: _buildEmptyGuide()),
                  ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) =>
                        _buildEntry(_messages[index]),
                  ),
                ],
              ),
            ),
            _buildInputBar(),
            _buildBannerAd(),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildEmptyGuide() {
    return IgnorePointer(
      child: Align(
        alignment: const Alignment(0, 0.25),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Opacity(
              opacity: 0.9,
              child: Image.asset(
                'assets/images/cat_mascot.png',
                height: 120,
                filterQuality: FilterQuality.medium,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              _isListening
                  ? keepWords('${withTopicParticle(widget.catName)} 소리를 기다리는 중이에요')
                  : keepWords('아래 마이크를 누르면 ${widget.catName}의 소리를 듣고\n어떤 상황인지 짐작해 드려요'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 13, height: 1.6, color: NyangColors.muted),
            ),
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
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 64,
      titleSpacing: 14,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: NyangGradients.header,
          boxShadow: [
            BoxShadow(
              color: NyangColors.shadow.withValues(alpha: 0.12),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
      ),
      title: Row(
        children: [
          const MascotAvatar(radius: 21),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 인트로와 같은 동글체 (서브셋 글꼴에 '냥이톡' 포함)
              const Text('냥냥이톡',
                  style: TextStyle(
                      fontFamily: 'DongleIntro',
                      fontSize: 34,
                      height: 0.9,
                      color: Colors.white)),
              Text(_headerStatus,
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.88))),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: '채팅방 나가기',
          icon: Icon(Icons.logout_rounded,
              color: Colors.white.withValues(alpha: 0.9)),
          onPressed: _confirmExit,
        ),
        const SizedBox(width: 4),
      ],
    );
  }
  Widget _buildEntry(ChatEntry entry) {
    if (entry.isUser) {
      return _buildUserCueEntry(entry);
    }
    if (entry.isSystem) {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            entry.systemText ?? '',
            style: const TextStyle(color: NyangColors.inkSoft, fontSize: 12),
          ),
        ),
      );
    }

    final displaySituation = entry.correctedSituation ?? entry.situation;
    final info = kSituationInfo[displaySituation]!;
    final timeLabel = _formatTime(entry.time);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          entry.isHumanMimicry
              ? const CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.white,
                  child: Text('🧑', style: TextStyle(fontSize: 18)),
                )
              : const MascotAvatar(radius: 18),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 2, left: 2),
                  child: Text(
                    entry.isHumanMimicry
                        ? '사람 목소리 (오인식)'
                        : entry.correctedSituation != null
                            ? '${info.koreanLabel} (고쳐주신 답변)'
                            : info.koreanLabel,
                    style: const TextStyle(
                        fontSize: 11, color: NyangColors.muted),
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
                            topLeft: Radius.circular(6),
                            topRight: Radius.circular(20),
                            bottomLeft: Radius.circular(20),
                            bottomRight: Radius.circular(20),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: NyangColors.shadow.withValues(alpha: 0.12),
                              blurRadius: 14,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Text(
                          entry.isHumanMimicry
                              ? '🧑 어? 사람 목소리였네요! 더 똑똑해질게요냥'
                              : '${info.emoji} ${info.spokenPhrase}',
                          style: const TextStyle(
                              fontSize: 15,
                              height: 1.35,
                              color: NyangColors.ink),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(timeLabel,
                        style:
                            const TextStyle(fontSize: 10, color: NyangColors.muted)),
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
  /// 사용자가 "말 걸기"로 고양이에게 신호음을 보낸 메시지 (채팅방 오른쪽에 표시).
  Widget _buildUserCueEntry(ChatEntry entry) {
    final info = kCatCueInfo[entry.cue]!;
    final timeLabel = _formatTime(entry.time);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(timeLabel,
              style: const TextStyle(fontSize: 10, color: NyangColors.muted)),
          const SizedBox(width: 6),
          Flexible(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                gradient: NyangGradients.lavenderButton,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(6),
                ),
                boxShadow: [
                  BoxShadow(
                    color: NyangColors.lavender.withValues(alpha: 0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Text(
                '${info.emoji} "${info.label}" 소리를 들려줬어요',
                style: const TextStyle(
                    fontSize: 15, height: 1.3, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedbackRow(ChatEntry entry) {
    // 1) 아직 맞아요/아니에요를 누르지 않은 경우.
    if (entry.feedbackCorrect == null) {
      return Padding(
        padding: const EdgeInsets.only(left: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _feedbackChip(
              label: '👍 맞아요',
              color: NyangColors.lavenderTint,
              onTap: () => _giveFeedback(entry, true),
            ),
            const SizedBox(width: 6),
            _feedbackChip(
              label: '👎 아니에요',
              color: NyangColors.lavenderTint,
              onTap: () => _giveFeedback(entry, false),
            ),
          ],
        ),
      );
    }

    // 2) 맞아요를 누른 경우.
    if (entry.feedbackCorrect == true) {
      return const Padding(
        padding: EdgeInsets.only(left: 4),
        child: Text(
          '맞다고 알려주셨어요 💛',
          style: TextStyle(fontSize: 11, color: NyangColors.muted),
        ),
      );
    }

    // 3) 아니에요를 눌렀지만, 아직 실제 상태를 고르지 않은 경우
    //    -> "지금 어떤 상태인가요?" 질문 + 확률 높은 상위 3개 선택지.
    if (entry.correctedSituation == null && !entry.isHumanMimicry) {
      return Padding(
        padding: const EdgeInsets.only(left: 2, top: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${withTopicParticle(widget.catName)} 지금 어떤 상태인가요?',
              style: const TextStyle(fontSize: 11, color: NyangColors.muted),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final alt in entry.alternatives)
                  _feedbackChip(
                    label:
                        '${kSituationInfo[alt]!.emoji} ${kSituationInfo[alt]!.koreanLabel}',
                    color: NyangColors.lavenderTint,
                    onTap: () => _applyCorrection(entry, alt),
                  ),
                _feedbackChip(
                  label: '🔍 기타 (직접 선택)',
                  color: Colors.white,
                  onTap: () => _showFullSituationPicker(entry),
                ),
                _feedbackChip(
                  label: '🧑 사람이 흉내낸 소리예요',
                  color: Colors.white,
                  onTap: () => _markAsHumanMimicry(entry),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // 4) 아니에요 -> "사람이 흉내낸 소리예요"를 골라준 경우.
    if (entry.isHumanMimicry) {
      return const Padding(
        padding: EdgeInsets.only(left: 4),
        child: Text(
          '사람 목소리였다고 알려주셨어요, 더 잘 구별해볼게요 🧑',
          style: TextStyle(fontSize: 11, color: NyangColors.muted),
        ),
      );
    }

    // 5) 아니에요 -> 실제 상태까지 골라준 경우.
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        '${kSituationInfo[entry.correctedSituation]!.koreanLabel}(으)로 알려주셨어요, 더 배울게요냥',
        style: const TextStyle(fontSize: 11, color: NyangColors.muted),
      ),
    );
  }
  Widget _feedbackChip({
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: NyangColors.lavenderLine),
        ),
        child: Text(label,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: NyangColors.accentText)),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      // 흰 띠 없이 바탕 그라데이션이 이어지게 투명하게, 아래쪽은 마이크 그림자가
      // 광고에 잘리지 않도록 여유를 둔다.
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 16),
      child: SafeArea(
        top: false,
        bottom: false,
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: _isListening ? null : _showCatCuePicker,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: NyangColors.lavenderLine),
                    boxShadow: [
                      BoxShadow(
                        color: NyangColors.shadow.withValues(alpha: 0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _isListening
                              ? '${widget.catName}의 소리를 듣고 있어요...'
                              : (_modelReady
                                  ? '눌러서 고양이에게 소리 들려주기'
                                  : '모델 준비 중...'),
                          style: const TextStyle(
                              color: NyangColors.muted, fontSize: 14),
                        ),
                      ),
                      if (!_isListening) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.campaign_outlined,
                            size: 20, color: NyangColors.lavenderSoft),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _modelReady ? _toggleListening : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutBack,
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: _isListening
                      ? NyangGradients.listening
                      : NyangGradients.lavenderButton,
                  boxShadow: [
                    BoxShadow(
                      color: (_isListening ? NyangColors.rose : NyangColors.lavender)
                          .withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Icon(
                  _isListening ? Icons.stop_rounded : Icons.mic_rounded,
                  color: Colors.white,
                  size: 26,
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
