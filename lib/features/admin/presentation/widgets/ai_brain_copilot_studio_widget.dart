import 'package:al_mraay/core/constants/ai_models.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/localization/locale_provider.dart';
import '../../../../core/services/ai_brain_copilot_service.dart';
import '../../../../core/services/ai_directives_service.dart';
import '../../../../core/services/ai_model_config_service.dart';
import '../../../../core/services/voice_recording_service.dart';
import '../../../../core/utils/clipboard_image_helper.dart';
import '../../../../core/utils/responsive.dart';
import '../../domain/ai_directive_model.dart';
import 'ai_model_switcher_dialog.dart';
import '../../../../core/services/firebase_scope.dart';

class AiBrainCoPilotStudioWidget extends ConsumerStatefulWidget {
  final String? initialInvoiceContext;
  final Uint8List? initialInvoiceImage;
  final String? initialInvoiceImageUrl;
  final List<String>? initialInvoiceImageUrls;

  const AiBrainCoPilotStudioWidget({
    super.key,
    this.initialInvoiceContext,
    this.initialInvoiceImage,
    this.initialInvoiceImageUrl,
    this.initialInvoiceImageUrls,
  });

  @override
  ConsumerState<AiBrainCoPilotStudioWidget> createState() => _AiBrainCoPilotStudioWidgetState();
}

class _AiBrainCoPilotStudioWidgetState extends ConsumerState<AiBrainCoPilotStudioWidget> {
  ColorScheme get colorScheme => Theme.of(context).colorScheme;

  final TextEditingController _promptController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<AiBrainChatMessage> _messages = [];
  final List<Uint8List> _selectedImages = [];
  bool _isLoading = false;
  bool _isDownloadingInitialImages = false;

  // Clipboard paste subscription
  StreamSubscription? _clipboardPasteSub;

  // Voice recording & playback state
  AudioPlayer? _audioPlayer;
  String? _playingMessageId;
  bool _isPlayingAudio = false;
  Duration _playbackPosition = Duration.zero;
  Duration _playbackDuration = Duration.zero;
  StreamSubscription? _playerStateSub;
  StreamSubscription? _playerPositionSub;
  StreamSubscription? _playerDurationSub;
  StreamSubscription? _playerCompleteSub;

  bool _isRecordingVoice = false;
  Duration _recordingDuration = Duration.zero;
  StreamSubscription<Duration>? _recordDurationSub;
  bool _isTranscribingVoice = false;

  // Draft voice note attachment
  VoiceRecordingResult? _draftVoiceNote;

  @override
  void initState() {
    super.initState();
    _initAudioPlayer();
    _clipboardPasteSub = listenToClipboardImagePaste(_handlePastedImageBytes);
    // Seed initial welcome message
    _messages.add(
      AiBrainChatMessage(
        id: 'welcome_msg',
        isUser: false,
        text: 'مرحباً بك في **استوديو حوكمة وتعليم عقل الذكاء الاصطناعي (AI Brain Studio)** 🧠⚡\n\n'
            'أنا هنا لمساعدتك في فحص وتشخيص صور بونات الكاشير، وفهم أسباب قبولها أو رفضها، واستيعاب القواعد والتوجيهات والماركات الجديدة التي تمليها عليّ باللغة الطبيعية.\n\n'
            'يمكنك رفع صورة بون، أو التحدث بالصوت 🎙️، أو كتابة تعليماتك وسأقوم بصياغة **معيار حوكمة رسمي (AIR Directive)** واعتماده سحابياً فوراً بنقرة واحدة.',
        timestamp: DateTime.now(),
      ),
    );

    // If pre-loaded from an invoice shortcut
    if (widget.initialInvoiceImage != null) {
      _selectedImages.add(widget.initialInvoiceImage!);
    } else {
      _fetchInitialImages();
    }

    if (widget.initialInvoiceContext != null && widget.initialInvoiceContext!.isNotEmpty) {
      _promptController.text = 'برجاء فحص هذا البون وتشخيص سبب الرفض:\n${widget.initialInvoiceContext}';
    }
  }

  Future<void> _fetchInitialImages() async {
    final urls = <String>[];
    if (widget.initialInvoiceImageUrls != null && widget.initialInvoiceImageUrls!.isNotEmpty) {
      urls.addAll(widget.initialInvoiceImageUrls!);
    } else if (widget.initialInvoiceImageUrl != null && widget.initialInvoiceImageUrl!.isNotEmpty) {
      urls.add(widget.initialInvoiceImageUrl!);
    }

    if (urls.isEmpty) return;

    setState(() => _isDownloadingInitialImages = true);

    for (final url in urls) {
      if (url.startsWith('http')) {
        try {
          final res = await http.get(Uri.parse(url));
          if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
            if (mounted) {
              setState(() {
                _selectedImages.add(res.bodyBytes);
              });
            }
          }
        } catch (e) {
          debugPrint('Error fetching initial image from URL: $e');
        }
      }
    }

    if (mounted) {
      setState(() => _isDownloadingInitialImages = false);
    }
  }

  void _initAudioPlayer() {
    _audioPlayer = AudioPlayer();
    _playerStateSub = _audioPlayer?.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlayingAudio = state == PlayerState.playing;
        });
      }
    });
    _playerPositionSub = _audioPlayer?.onPositionChanged.listen((pos) {
      if (mounted) {
        setState(() {
          _playbackPosition = pos;
        });
      }
    });
    _playerDurationSub = _audioPlayer?.onDurationChanged.listen((dur) {
      if (mounted) {
        setState(() {
          _playbackDuration = dur;
        });
      }
    });
    _playerCompleteSub = _audioPlayer?.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _isPlayingAudio = false;
          _playbackPosition = Duration.zero;
          _playingMessageId = null;
        });
      }
    });
  }

  Future<void> _playPauseVoiceMessage(AiBrainChatMessage msg) async {
    if (_audioPlayer == null) return;

    if (_playingMessageId == msg.id && _isPlayingAudio) {
      await _audioPlayer?.pause();
      return;
    }

    if (_playingMessageId == msg.id && !_isPlayingAudio) {
      await _audioPlayer?.resume();
      return;
    }

    try {
      await _audioPlayer?.stop();
      _playingMessageId = msg.id;
      _playbackPosition = Duration.zero;

      if (msg.audioPath != null && msg.audioPath!.isNotEmpty) {
        if (kIsWeb) {
          await _audioPlayer?.play(UrlSource(msg.audioPath!));
        } else {
          await _audioPlayer?.play(DeviceFileSource(msg.audioPath!));
        }
      } else if (msg.audioBytes != null && msg.audioBytes!.isNotEmpty) {
        await _audioPlayer?.play(BytesSource(msg.audioBytes!));
      }
    } catch (e) {
      debugPrint('Error playing voice message: $e');
    }
  }

  Future<void> _startVoiceRecording() async {
    final recordingService = ref.read(voiceRecordingServiceProvider);
    final strings = AppStrings.of(ref);

    final permitted = await recordingService.hasPermission();
    if (!permitted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(strings.micPermissionDenied, style: GoogleFonts.cairo()),
            backgroundColor: colorScheme.onErrorContainer,
          ),
        );
      }
      return;
    }

    final success = await recordingService.startRecording();
    if (success) {
      _recordDurationSub?.cancel();
      _recordDurationSub = recordingService.durationStream.listen((dur) {
        if (mounted) {
          setState(() {
            _recordingDuration = dur;
          });
        }
      });

      setState(() {
        _isRecordingVoice = true;
        _recordingDuration = Duration.zero;
      });
    }
  }

  Future<void> _cancelVoiceRecording() async {
    _recordDurationSub?.cancel();
    final recordingService = ref.read(voiceRecordingServiceProvider);
    await recordingService.cancelRecording();
    if (mounted) {
      setState(() {
        _isRecordingVoice = false;
        _recordingDuration = Duration.zero;
      });
    }
  }

  Future<void> _finishRecordingAndSendVoiceNote() async {
    _recordDurationSub?.cancel();
    final recordingService = ref.read(voiceRecordingServiceProvider);
    final strings = AppStrings.of(ref);

    setState(() {
      _isRecordingVoice = false;
    });

    final result = await recordingService.stopRecording();
    if (result == null || result.bytes.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(strings.recordingTooShort, style: GoogleFonts.cairo()),
            backgroundColor: colorScheme.onSecondaryFixedVariant,
          ),
        );
      }
      return;
    }

    final text = _promptController.text.trim();
    final userImages = List<Uint8List>.from(_selectedImages);

    final userMessage = AiBrainChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      isUser: true,
      text: text.isNotEmpty
          ? text
          : (strings.isAr ? '🎙️ تسجيل صوتي مرسل إلى عقل الذكاء الاصطناعي' : '🎙️ Voice note sent to AI Brain'),
      attachedImages: userImages,
      audioBytes: result.bytes,
      audioPath: result.path,
      audioMimeType: result.mimeType,
      audioDuration: result.duration,
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.add(userMessage);
      _promptController.clear();
      _selectedImages.clear();
      _isLoading = true;
    });

    _scrollToBottom();

    final copilotService = ref.read(aiBrainCoPilotServiceProvider);
    final currentDirectives = ref.read(aiDirectivesStreamProvider).value ?? [];

    final aiReply = await copilotService.sendMessage(
      prompt: text,
      images: userImages,
      audioBytes: result.bytes,
      audioMimeType: result.mimeType,
      history: _messages,
      currentDirectives: currentDirectives,
      referenceInvoiceContext: widget.initialInvoiceContext,
    );

    if (aiReply.voiceTranscription != null && aiReply.voiceTranscription!.isNotEmpty) {
      userMessage.voiceTranscription = aiReply.voiceTranscription;
    }

    if (mounted) {
      setState(() {
        _messages.add(aiReply);
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  Future<void> _finishRecordingAndDictateToText() async {
    _recordDurationSub?.cancel();
    final recordingService = ref.read(voiceRecordingServiceProvider);
    final copilotService = ref.read(aiBrainCoPilotServiceProvider);

    setState(() {
      _isRecordingVoice = false;
      _isTranscribingVoice = true;
    });

    final result = await recordingService.stopRecording();
    if (result == null || result.bytes.isEmpty) {
      if (mounted) {
        setState(() {
          _isTranscribingVoice = false;
        });
      }
      return;
    }

    final transcribedText = await copilotService.transcribeAudioOnly(
      audioBytes: result.bytes,
      audioMimeType: result.mimeType,
    );

    if (mounted) {
      setState(() {
        _isTranscribingVoice = false;
        if (transcribedText.isNotEmpty) {
          if (_promptController.text.trim().isNotEmpty) {
            _promptController.text = '${_promptController.text.trim()} $transcribedText';
          } else {
            _promptController.text = transcribedText;
          }
        }
      });
    }
  }

  void _handlePastedImageBytes(Uint8List bytes) {
    if (!mounted) return;
    setState(() {
      _selectedImages.add(bytes);
    });
    final strings = AppStrings.of(ref);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.paste_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                strings.pasteImageSuccess,
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12.5),
              ),
            ),
          ],
        ),
        backgroundColor: colorScheme.primary,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _stopRecordingAndKeepDraft() async {
    _recordDurationSub?.cancel();
    final recordingService = ref.read(voiceRecordingServiceProvider);
    final strings = AppStrings.of(ref);

    setState(() {
      _isRecordingVoice = false;
    });

    final result = await recordingService.stopRecording();
    if (result == null || result.bytes.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(strings.recordingTooShort, style: GoogleFonts.cairo()),
            backgroundColor: colorScheme.onSecondaryFixedVariant,
          ),
        );
      }
      return;
    }

    if (mounted) {
      setState(() {
        _draftVoiceNote = result;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  strings.isAr
                      ? 'تم إيقاف التسجيل وحفظ الفويس كمسودة مرفقة جاهزة للإرسال مع الرسالة 🎙️'
                      : 'Voice recording saved as draft attachment 🎙️',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12.5),
                ),
              ),
            ],
          ),
          backgroundColor: colorScheme.tertiary,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  Future<void> _removeDraftVoiceNote() async {
    if (_playingMessageId == 'draft_voice_note') {
      await _audioPlayer?.stop();
      _playingMessageId = null;
      _isPlayingAudio = false;
    }
    if (mounted) {
      setState(() {
        _draftVoiceNote = null;
      });
    }
  }

  Future<void> _playPauseDraftVoiceNote() async {
    if (_audioPlayer == null || _draftVoiceNote == null) return;
    const draftId = 'draft_voice_note';

    if (_playingMessageId == draftId && _isPlayingAudio) {
      await _audioPlayer?.pause();
      return;
    }

    if (_playingMessageId == draftId && !_isPlayingAudio) {
      await _audioPlayer?.resume();
      return;
    }

    try {
      await _audioPlayer?.stop();
      _playingMessageId = draftId;
      _playbackPosition = Duration.zero;

      final path = _draftVoiceNote!.path;
      if (path.isNotEmpty) {
        if (kIsWeb) {
          await _audioPlayer?.play(UrlSource(path));
        } else {
          await _audioPlayer?.play(DeviceFileSource(path));
        }
      } else if (_draftVoiceNote!.bytes.isNotEmpty) {
        await _audioPlayer?.play(BytesSource(_draftVoiceNote!.bytes));
      }
    } catch (e) {
      debugPrint('Error playing draft audio: $e');
      if (mounted) {
        setState(() {
          _isPlayingAudio = false;
          _playingMessageId = null;
        });
      }
    }
  }

  @override
  void dispose() {
    _clipboardPasteSub?.cancel();
    _recordDurationSub?.cancel();
    _playerStateSub?.cancel();
    _playerPositionSub?.cancel();
    _playerDurationSub?.cancel();
    _playerCompleteSub?.cancel();
    _audioPlayer?.dispose();
    _promptController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final pickedFiles = await picker.pickMultiImage();
      if (pickedFiles.isNotEmpty) {
        for (final file in pickedFiles) {
          final bytes = await file.readAsBytes();
          if (bytes.isNotEmpty) {
            setState(() {
              _selectedImages.add(bytes);
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error picking images: $e');
    }
  }

  void _removeSelectedImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

  Future<void> _handleSendMessage([String? customPrompt]) async {
    final text = (customPrompt ?? _promptController.text).trim();
    final hasImages = _selectedImages.isNotEmpty;
    final hasDraftVoice = _draftVoiceNote != null && _draftVoiceNote!.bytes.isNotEmpty;

    if (text.isEmpty && !hasImages && !hasDraftVoice) return;

    final strings = AppStrings.of(ref);
    final userImages = List<Uint8List>.from(_selectedImages);
    final voiceNote = _draftVoiceNote;

    final userMessage = AiBrainChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      isUser: true,
      text: text.isNotEmpty
          ? text
          : (voiceNote != null
              ? (strings.isAr ? '🎙️ تسجيل صوتي مرسل إلى عقل الذكاء الاصطناعي' : '🎙️ Voice note sent to AI Brain')
              : ''),
      attachedImages: userImages,
      audioBytes: voiceNote?.bytes,
      audioPath: voiceNote?.path,
      audioMimeType: voiceNote?.mimeType,
      audioDuration: voiceNote?.duration,
      timestamp: DateTime.now(),
    );

    // Stop playback if previewing draft
    if (_playingMessageId == 'draft_voice_note') {
      await _audioPlayer?.stop();
      _playingMessageId = null;
      _isPlayingAudio = false;
    }

    setState(() {
      _messages.add(userMessage);
      _promptController.clear();
      _selectedImages.clear();
      _draftVoiceNote = null;
      _isLoading = true;
    });

    _scrollToBottom();

    final copilotService = ref.read(aiBrainCoPilotServiceProvider);
    final currentDirectives = ref.read(aiDirectivesStreamProvider).value ?? [];

    final aiReply = await copilotService.sendMessage(
      prompt: text,
      images: userImages,
      audioBytes: voiceNote?.bytes,
      audioMimeType: voiceNote?.mimeType,
      history: _messages,
      currentDirectives: currentDirectives,
      referenceInvoiceContext: widget.initialInvoiceContext,
    );

    if (aiReply.voiceTranscription != null && aiReply.voiceTranscription!.isNotEmpty) {
      userMessage.voiceTranscription = aiReply.voiceTranscription;
    }

    if (mounted) {
      setState(() {
        _messages.add(aiReply);
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 200,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutQuad,
        );
      }
    });
  }

  Future<void> _handleDeployDirective(AiBrainChatMessage message, AiDirectiveModel directive) async {
    setState(() {
      message.isSaving = true;
    });

    try {
      final copilotService = ref.read(aiBrainCoPilotServiceProvider);
      await copilotService.deployDirective(directive);

      if (mounted) {
        setState(() {
          message.isSaving = false;
          message.isDirectiveSaved = true;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: colorScheme.tertiary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'تم اعتماد وتثبيت المعيار (${directive.id}) بنجاح في عقل الذكاء الاصطناعي!',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          message.isSaving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Theme.of(context).colorScheme.error,
            content: Text('تعذر اعتماد المعيار: $e', style: GoogleFonts.cairo()),
          ),
        );
      }
    }
  }

  Future<void> _handleSimulateDryRun(AiBrainChatMessage message, AiDirectiveModel directive) async {
    setState(() {
      message.isSimulating = true;
    });

    try {
      final copilotService = ref.read(aiBrainCoPilotServiceProvider);
      // Collect images to test: selected images, initial invoice images, or attached images
      final testImages = <Uint8List>[];
      if (_selectedImages.isNotEmpty) {
        testImages.addAll(_selectedImages);
      } else if (widget.initialInvoiceImage != null) {
        testImages.add(widget.initialInvoiceImage!);
      } else if (message.attachedImages.isNotEmpty) {
        testImages.addAll(message.attachedImages);
      }

      // Context to test
      final contextText = (widget.initialInvoiceContext != null && widget.initialInvoiceContext!.isNotEmpty)
          ? widget.initialInvoiceContext!
          : (directive.exampleInput.isNotEmpty
              ? 'بند تجريبي: ${directive.exampleInput}'
              : 'فاتورة تجريبية لمطابقة شروط العرض');

      final result = await copilotService.simulateReceiptDryRun(
        images: testImages,
        invoiceContext: contextText,
        directive: directive,
      );

      if (mounted) {
        setState(() {
          message.isSimulating = false;
          message.simulationResult = result;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          message.isSimulating = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Theme.of(context).colorScheme.error,
            content: Text('تعذر إتمام المحاكاة التجريبية: $e', style: GoogleFonts.cairo()),
          ),
        );
      }
    }
  }

  Future<void> _handleAnalyzeRejectionTrends() async {
    final isAr = ref.read(localeProvider).languageCode == 'ar';
    final userMessage = AiBrainChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      isUser: true,
      text: isAr
          ? '📊 تحليل اتجاهات الرفض: افحص أحدث البونات المرفوضة في النظام وحدد الأنماط المتكررة واقترح معايير ذكية لحلها.'
          : '📊 Analyze Rejection Trends: Inspect recent rejected receipts, identify patterns, and propose directives.',
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.add(userMessage);
      _isLoading = true;
    });

    _scrollToBottom();

    try {
      // Query recent rejected receipts from Firestore
      final snap = await scopedFirestore()
          .collection('receipts_transactions')
          .where('isValid', isEqualTo: false)
          .limit(20)
          .get();

      List<Map<String, dynamic>> rejectedList = snap.docs.map((d) => d.data()).toList();

      // If empty or index not ready, fallback to general limit query
      if (rejectedList.isEmpty) {
        final fallbackSnap = await scopedFirestore()
            .collection('receipts_transactions')
            .limit(25)
            .get();
        rejectedList = fallbackSnap.docs
            .map((d) => d.data())
            .where((data) => data['isValid'] == false || data['status'] == 'rejected')
            .toList();
      }

      final copilotService = ref.read(aiBrainCoPilotServiceProvider);
      final analysisText = await copilotService.analyzeRejectionTrends(rejectedList);

      if (mounted) {
        setState(() {
          _messages.add(
            AiBrainChatMessage(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              isUser: false,
              text: analysisText,
              timestamp: DateTime.now(),
              durationSeconds: 2.1,
              modelNameUsed: ref.read(aiModelConfigStreamProvider).valueOrNull?.effectivePrimaryModel,
            ),
          );
          _isLoading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add(
            AiBrainChatMessage(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              isUser: false,
              text: 'تعذر سحب أو تحليل بيانات البونات المرفوضة: $e',
              timestamp: DateTime.now(),
            ),
          );
          _isLoading = false;
        });
        _scrollToBottom();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isAr = ref.isArabic;
    final currentDirectives = ref.watch(aiDirectivesStreamProvider).value ?? [];

    return M3ResponsiveBuilder(
      builder: (context, layout) {
        final studioColumn = Column(
          children: [
            // 1. Studio Status & Quick Chips Toolbar
            _buildStudioHeaderBar(colorScheme, isAr, currentDirectives.length),

            // 2. Chat Messages Viewport
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: EdgeInsets.symmetric(
                  horizontal: layout.isDesktop ? M3Spacing.md : M3Spacing.sm,
                  vertical: M3Spacing.sm,
                ),
                itemCount: _messages.length + (_isLoading ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _messages.length && _isLoading) {
                    return _buildAiThinkingIndicator(colorScheme, isAr);
                  }
                  final msg = _messages[index];
                  return _buildChatMessageItem(msg, colorScheme, isAr);
                },
              ),
            ),

            // 3. Image Previews Strip (if images attached or downloading)
            if (_isDownloadingInitialImages)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: M3Spacing.sm,
                  vertical: M3Spacing.xs,
                ),
                color:
                    colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: M3Spacing.xs),
                    Text(
                      isAr
                          ? 'جاري جلب صورة البون للاستوديو...'
                          : 'Fetching receipt image...',
                      style: GoogleFonts.cairo(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            if (_selectedImages.isNotEmpty)
              _buildAttachedImagesStrip(colorScheme),

            // 3.4. Draft Voice Note Strip (if recording saved as draft)
            if (_draftVoiceNote != null)
              _buildDraftVoiceNoteStrip(
                  colorScheme, isAr, AppStrings.of(ref)),

            // 3.5. Transcribing audio indicator banner
            if (_isTranscribingVoice)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: M3Spacing.sm,
                  vertical: M3Spacing.xs,
                ),
                color:
                    colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: M3Spacing.xs),
                    Text(
                      AppStrings.of(ref).transcribingAudio,
                      style: GoogleFonts.cairo(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),

            // 4. Message Input Bar or Voice Recording Bar
            if (_isRecordingVoice)
              _buildVoiceRecordingBar(colorScheme, isAr, AppStrings.of(ref))
            else
              _buildMessageInputBar(colorScheme, isAr, AppStrings.of(ref)),
          ],
        );

        if (!layout.isDesktop) {
          return studioColumn;
        }

        return M3ContentBoundary(
          maxWidth: 1440.0,
          padding: EdgeInsets.symmetric(
            horizontal: layout.margin,
            vertical: M3Spacing.sm,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.shadow.withValues(alpha: 0.03),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: studioColumn,
          ),
        );
      },
    );
  }

  Widget _buildStudioHeaderBar(ColorScheme colorScheme, bool isAr, int directivesCount) {
    final modelConfig = ref.watch(aiModelConfigStreamProvider).valueOrNull;
    final activeModelName = modelConfig?.effectivePrimaryModel ?? AiModels.defaultPrimary;
    final activeMode = modelConfig?.mode ?? AiAgentMode.standardVision;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Dynamic AI Model & Agent Mode interactive badge
              Tooltip(
                message: isAr ? 'انقر لتبديل نموذج الذكاء الاصطناعي ونمط الوكيل' : 'Click to switch AI model & agent mode',
                child: InkWell(
                  onTap: () => AiModelSwitcherDialog.show(context),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: colorScheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: colorScheme.tertiaryFixedDim),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: colorScheme.tertiary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$activeModelName • ${isAr ? activeMode.labelAr : activeMode.labelEn}',
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onTertiaryContainer,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.tune_rounded, size: 13, color: colorScheme.onTertiaryContainer),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isAr ? '$directivesCount معياراً معتمداً' : '$directivesCount Active Directives',
                  style: GoogleFonts.cairo(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
                tooltip: isAr ? 'مسح المحادثة' : 'Clear Chat',
                onPressed: () {
                  setState(() {
                    _messages.clear();
                    _messages.add(
                      AiBrainChatMessage(
                        id: 'welcome_reset',
                        isUser: false,
                        text: 'تم مسح المحادثة. أنا جاهز لتشخيص بوناتك واستيعاب معاييرك الجديدة.',
                        timestamp: DateTime.now(),
                      ),
                    );
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ActionChip(
                  avatar: Icon(Icons.analytics_rounded, size: 15, color: colorScheme.primary),
                  label: Text(
                    isAr ? '📊 تحليل اتجاهات الرفض (Trends)' : '📊 Rejection Trends',
                    style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.bold, color: colorScheme.primary),
                  ),
                  backgroundColor: colorScheme.primary.withValues(alpha: 0.08),
                  side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.3)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  onPressed: _isLoading ? null : _handleAnalyzeRejectionTrends,
                ),
                const SizedBox(width: 8),
                _buildQuickActionChip('🔍 تشخيص بون مرفوض', 'برجاء فحص هذا البون وتحديد سبب عدم أهليته بالعرض بدقة.', colorScheme),
                const SizedBox(width: 8),
                _buildQuickActionChip('🏷️ تعليم ماركة فرعية', 'أريد تعليم الذكاء الاصطناعي بأن علامة تجارية فرعية تتبع شركة راعية محددة.', colorScheme),
                const SizedBox(width: 8),
                _buildQuickActionChip('⚖️ حوكمة خصومات البون', 'اشرح لي كيف يتعامل الذكاء الاصطناعي مع الخصومات واقتصاديات القطعة الواحدة.', colorScheme),
                const SizedBox(width: 8),
                _buildQuickActionChip('🛡️ استثناء فروع السلاسل', 'كيف يتم فك شفرة الفروع المتطابقة وتجنب تكرار أسماء الفروع؟', colorScheme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionChip(String label, String promptText, ColorScheme colorScheme) {
    return ActionChip(
      label: Text(label, style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.bold)),
      backgroundColor: colorScheme.surface,
      side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onPressed: () => _handleSendMessage(promptText),
    );
  }

  Widget _buildChatMessageItem(AiBrainChatMessage msg, ColorScheme colorScheme, bool isAr) {
    final isUser = msg.isUser;

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [colorScheme.primary, colorScheme.onPrimaryFixedVariant],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.primary.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(Icons.psychology_rounded, size: 20, color: Colors.white),
            ),
            const SizedBox(width: 12),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                // Attached Images (if any)
                if (msg.attachedImages.isNotEmpty) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: msg.attachedImages.map((img) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: 100,
                          height: 120,
                          decoration: BoxDecoration(
                            border: Border.all(color: colorScheme.outlineVariant),
                          ),
                          child: Image.memory(img, fit: BoxFit.cover),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                ],

                // Message Text / Voice Bubble
                Container(
                  padding: const EdgeInsets.all(16),
                  constraints: const BoxConstraints(maxWidth: 720),
                  decoration: BoxDecoration(
                    color: isUser
                        ? colorScheme.primary
                        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isUser ? 16 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 16),
                    ),
                    border: Border.all(
                      color: isUser
                          ? Colors.transparent
                          : colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Voice Note Player (if audio attached)
                      if (msg.audioBytes != null || msg.audioPath != null)
                        _buildVoiceNoteCard(msg, colorScheme, isAr, isUser),

                      if (msg.text.isNotEmpty &&
                          !(msg.audioBytes != null &&
                              (msg.text.startsWith('🎙️ تسجيل صوتي') ||
                                  msg.text.startsWith('🎙️ Voice note')))) ...[
                        SelectableText(
                          msg.text,
                          style: GoogleFonts.cairo(
                            fontSize: 13.5,
                            height: 1.6,
                            color: isUser ? colorScheme.onPrimary : colorScheme.onSurface,
                          ),
                        ),
                      ],
                      // Latency & Model Telemetry Pill (for AI responses)
                      if (!isUser && (msg.durationSeconds != null || msg.modelNameUsed != null)) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: colorScheme.surface.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.bolt_rounded, size: 13, color: colorScheme.tertiary),
                              const SizedBox(width: 4),
                              Text(
                                '${msg.modelNameUsed ?? "Gemini"} • ${msg.durationSeconds != null ? "${msg.durationSeconds!.toStringAsFixed(1)}s" : "< 1s"}',
                                style: GoogleFonts.sourceCodePro(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                isAr ? '• فحص مباشر' : '• live telemetry',
                                style: GoogleFonts.cairo(
                                  fontSize: 9.5,
                                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Directive Proposal Card (if AI suggested a new rule)
                if (msg.suggestedDirective != null) ...[
                  const SizedBox(height: 12),
                  _buildDirectiveProposalCard(msg, msg.suggestedDirective!, colorScheme, isAr),
                ],
              ],
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 12),
            CircleAvatar(
              radius: 18,
              backgroundColor: colorScheme.primaryContainer,
              child: Icon(Icons.person_rounded, size: 20, color: colorScheme.onPrimaryContainer),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDirectiveProposalCard(
    AiBrainChatMessage msg,
    AiDirectiveModel directive,
    ColorScheme colorScheme,
    bool isAr,
  ) {
    final cat = directive.category;

    return Container(
      constraints: const BoxConstraints(maxWidth: 720),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.5), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: AIR ID + Category Chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.06),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(15),
                topRight: Radius.circular(15),
              ),
              border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3))),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    directive.id,
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: cat.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: cat.color.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(cat.icon, size: 13, color: cat.color),
                      const SizedBox(width: 4),
                      Text(
                        cat.getLabel(isAr),
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: cat.color,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  directive.code,
                  style: GoogleFonts.sourceCodePro(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Text(
                  directive.getTitle(isAr),
                  style: GoogleFonts.cairo(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  directive.getDescription(isAr),
                  style: GoogleFonts.cairo(fontSize: 13, height: 1.5, color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),

                // Logic Steps Box
                if (directive.logicAr.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isAr ? 'خطوات المعالجة المنطقية الخوارزمية:' : 'Algorithmic Logic Steps:',
                          style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.bold, color: colorScheme.primary),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          directive.getLogic(isAr),
                          style: GoogleFonts.cairo(fontSize: 12, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                // Before / After Examples
                if (directive.exampleInput.isNotEmpty) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: colorScheme.primaryFixedDim),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isAr ? 'قبل تطبيق القاعدة (مدخل):' : 'Before / Input:',
                                style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.onSecondaryContainer),
                              ),
                              const SizedBox(height: 2),
                              Text(directive.exampleInput, style: GoogleFonts.cairo(fontSize: 11.5)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: colorScheme.tertiaryContainer,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: colorScheme.tertiaryFixedDim),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isAr ? 'بعد تطبيق القاعدة (المخرج):' : 'After / Output:',
                                style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.onTertiaryContainer),
                              ),
                              const SizedBox(height: 2),
                              Text(directive.exampleOutput, style: GoogleFonts.cairo(fontSize: 11.5)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],

                // Simulation Result Box (if dry-run was executed)
                if (msg.simulationResult != null) ...[
                  _buildSimulationResultBox(msg.simulationResult!, colorScheme, isAr),
                  const SizedBox(height: 12),
                ],

                // Action Row: Dry Run Simulation + One-Click Deploy
                Row(
                  children: [
                    // Dry-run Simulation Button
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: msg.isSimulating ? null : () => _handleSimulateDryRun(msg, directive),
                        icon: msg.isSimulating
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.science_rounded, size: 16),
                        label: Text(
                          msg.isSimulating
                              ? (isAr ? 'جاري الفحص...' : 'Simulating...')
                              : (isAr ? 'محاكاة فحص البون 🧪' : 'Dry-Run Test 🧪'),
                          style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colorScheme.primary,
                          side: BorderSide(color: colorScheme.primary),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Deploy Button
                    Expanded(
                      flex: msg.isDirectiveSaved ? 1 : 2,
                      child: msg.isDirectiveSaved
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              decoration: BoxDecoration(
                                color: colorScheme.tertiaryContainer,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: colorScheme.tertiaryFixedDim),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.check_circle_rounded, color: colorScheme.tertiary, size: 18),
                                  const SizedBox(width: 6),
                                  Text(
                                    isAr ? 'معتمد في السحابة ✅' : 'Deployed ✅',
                                    style: GoogleFonts.cairo(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.onTertiaryContainer,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : FilledButton.icon(
                              onPressed: msg.isSaving ? null : () => _handleDeployDirective(msg, directive),
                              icon: msg.isSaving
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.cloud_upload_rounded, size: 18),
                              label: Text(
                                isAr
                                    ? 'اعتماد سحابي فوراً'
                                    : 'Deploy to Cloud',
                                style: GoogleFonts.cairo(fontSize: 12.5, fontWeight: FontWeight.bold),
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: colorScheme.primary,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimulationResultBox(Map<String, dynamic> res, ColorScheme colorScheme, bool isAr) {
    final isEligible = res['isEligible'] == true;
    final summary = res['summary']?.toString() ?? '';
    final explanation = res['explanation']?.toString() ?? '';
    final estimatedPrize = res['estimatedPrize']?.toString() ?? '';
    final matchedItems = (res['matchedItems'] as List?)?.map((e) => e.toString()).toList() ?? [];

    final statusColor = isEligible ? colorScheme.tertiary : colorScheme.onSecondaryFixedVariant;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(isEligible ? Icons.check_circle_rounded : Icons.info_rounded, color: statusColor, size: 18),
              const SizedBox(width: 8),
              Text(
                isAr
                    ? (isEligible ? 'نتيجة المحاكاة: مؤهل ومستوفٍ للشروط ✅' : 'نتيجة المحاكاة: غير مؤهل ⚠️')
                    : (isEligible ? 'Dry-Run: Eligible & Verified ✅' : 'Dry-Run: Not Eligible ⚠️'),
                style: GoogleFonts.cairo(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: statusColor,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Dry-Run In-Memory',
                  style: GoogleFonts.sourceCodePro(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor),
                ),
              ),
            ],
          ),
          if (summary.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(summary, style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold)),
          ],
          if (explanation.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(explanation, style: GoogleFonts.cairo(fontSize: 11.5, color: colorScheme.onSurfaceVariant)),
          ],
          if (estimatedPrize.isNotEmpty && estimatedPrize != 'غير محدد') ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  isAr ? 'الهدية التقديرية:' : 'Estimated Prize:',
                  style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.primary),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    estimatedPrize,
                    style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.onPrimaryContainer),
                  ),
                ),
              ],
            ),
          ],
          if (matchedItems.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: matchedItems.map((item) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    item,
                    style: GoogleFonts.cairo(fontSize: 10.5, fontWeight: FontWeight.bold, color: colorScheme.onTertiaryContainer),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAiThinkingIndicator(ColorScheme colorScheme, bool isAr) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.psychology_rounded, size: 20, color: colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Text(
                  isAr ? 'عقل الذكاء الاصطناعي يقوم بالفحص والتفكير...' : 'AI Brain is analyzing and reasoning...',
                  style: GoogleFonts.cairo(fontSize: 12, color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttachedImagesStrip(ColorScheme colorScheme) {
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4))),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _selectedImages.length,
        itemBuilder: (context, index) {
          return Stack(
            children: [
              Container(
                margin: const EdgeInsets.only(right: 8),
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colorScheme.primary),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: Image.memory(_selectedImages[index], fit: BoxFit.cover),
                ),
              ),
              Positioned(
                top: 2,
                right: 10,
                child: GestureDetector(
                  onTap: () => _removeSelectedImage(index),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Colors.black87,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close_rounded, size: 12, color: Colors.white),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildVoiceNoteCard(
    AiBrainChatMessage msg,
    ColorScheme colorScheme,
    bool isAr,
    bool isUser,
  ) {
    final isThisPlaying = _playingMessageId == msg.id && _isPlayingAudio;
    final totalSec = msg.audioDuration?.inSeconds ?? 0;
    final currentSec = (_playingMessageId == msg.id) ? _playbackPosition.inSeconds : 0;

    final minStr = (currentSec ~/ 60).toString().padLeft(2, '0');
    final secStr = (currentSec % 60).toString().padLeft(2, '0');
    final totalMinStr = (totalSec ~/ 60).toString().padLeft(2, '0');
    final totalSecStr = (totalSec % 60).toString().padLeft(2, '0');

    final progress = (totalSec > 0 && _playingMessageId == msg.id && _playbackDuration.inMilliseconds > 0)
        ? (_playbackPosition.inMilliseconds / _playbackDuration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isUser
            ? Colors.white.withValues(alpha: 0.15)
            : colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isUser
              ? Colors.white.withValues(alpha: 0.3)
              : colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Play / Pause circular action button
              Material(
                color: isUser ? Colors.white : colorScheme.primary,
                shape: const CircleBorder(),
                elevation: 1,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _playPauseVoiceMessage(msg),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Icon(
                      isThisPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      size: 20,
                      color: isUser ? colorScheme.primary : Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Waveform and progress bar
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.graphic_eq_rounded,
                          size: 16,
                          color: isUser ? Colors.white : colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isAr ? 'تسجيل صوتي' : 'Voice Note',
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isUser ? Colors.white : colorScheme.primary,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '$minStr:$secStr / $totalMinStr:$totalSecStr',
                          style: GoogleFonts.sourceCodePro(
                            fontSize: 10.5,
                            color: isUser ? Colors.white70 : colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 4,
                        backgroundColor: isUser
                            ? Colors.white.withValues(alpha: 0.25)
                            : colorScheme.outlineVariant.withValues(alpha: 0.3),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isUser ? Colors.white : colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (msg.voiceTranscription != null && msg.voiceTranscription!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isUser
                    ? Colors.black.withValues(alpha: 0.15)
                    : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isUser
                      ? Colors.white.withValues(alpha: 0.2)
                      : colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.subtitles_rounded, size: 14, color: colorScheme.tertiary),
                      const SizedBox(width: 6),
                      Text(
                        isAr ? 'تفريغ الصوت الذكي (Gemini Transcription):' : 'Spoken Voice Transcription:',
                        style: GoogleFonts.cairo(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.tertiary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    '"${msg.voiceTranscription}"',
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      height: 1.4,
                      color: isUser ? Colors.white.withValues(alpha: 0.95) : colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVoiceRecordingBar(ColorScheme colorScheme, bool isAr, AppStrings strings) {
    final minStr = (_recordingDuration.inSeconds ~/ 60).toString().padLeft(2, '0');
    final secStr = (_recordingDuration.inSeconds % 60).toString().padLeft(2, '0');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: colorScheme.error.withValues(alpha: 0.4))),
        boxShadow: [
          BoxShadow(
            color: colorScheme.error.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            // Cancel button
            Tooltip(
              message: strings.cancelRecording,
              child: InkWell(
                onTap: _cancelVoiceRecording,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.delete_outline_rounded, color: colorScheme.onErrorContainer, size: 22),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Live timer and animated sound wave bars
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: colorScheme.error.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    // Pulsing Red Recording Indicator
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0.3, end: 1.0),
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeInOut,
                      builder: (context, val, child) {
                        return Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: colorScheme.error,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: colorScheme.error.withValues(alpha: val * 0.6),
                                blurRadius: 6,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 10),

                    // Timer
                    Text(
                      '$minStr:$secStr',
                      style: GoogleFonts.sourceCodePro(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onErrorContainer,
                      ),
                    ),
                    const SizedBox(width: 14),

                    // Waveform visual bars
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(8, (i) {
                          final h = 6.0 + ((i * 3 + _recordingDuration.inSeconds * 4) % 18);
                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            width: 3,
                            height: h,
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          );
                        }),
                      ),
                    ),

                    // Recording status
                    Text(
                      isAr ? 'تحدث بوضوح...' : 'Speak now...',
                      style: GoogleFonts.cairo(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),

            // Stop & Keep Draft button (إيقاف وحفظ لمواصلة الشات)
            Tooltip(
              message: strings.stopAndKeepDraft,
              child: ElevatedButton.icon(
                onPressed: _stopRecordingAndKeepDraft,
                icon: const Icon(Icons.stop_circle_rounded, size: 18),
                label: Text(
                  isAr ? 'إيقاف وحفظ' : 'Stop & Keep',
                  style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.secondary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  elevation: 1,
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Dictate to Text button
            Tooltip(
              message: strings.dictateToText,
              child: OutlinedButton.icon(
                onPressed: _finishRecordingAndDictateToText,
                icon: const Icon(Icons.translate_rounded, size: 16),
                label: Text(
                  isAr ? 'تحويل لنص' : 'To Text',
                  style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colorScheme.primary,
                  side: BorderSide(color: colorScheme.primary),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Send Voice Note directly
            Tooltip(
              message: strings.sendVoiceNote,
              child: IconButton.filled(
                icon: const Icon(Icons.send_rounded, size: 20),
                onPressed: _finishRecordingAndSendVoiceNote,
                style: IconButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDraftVoiceNoteStrip(ColorScheme colorScheme, bool isAr, AppStrings strings) {
    if (_draftVoiceNote == null) return const SizedBox.shrink();

    final isThisPlaying = _playingMessageId == 'draft_voice_note' && _isPlayingAudio;
    final totalSec = _draftVoiceNote!.duration.inSeconds;
    final currentSec = (_playingMessageId == 'draft_voice_note') ? _playbackPosition.inSeconds : 0;

    final minStr = (currentSec ~/ 60).toString().padLeft(2, '0');
    final secStr = (currentSec % 60).toString().padLeft(2, '0');
    final totalMinStr = (totalSec ~/ 60).toString().padLeft(2, '0');
    final totalSecStr = (totalSec % 60).toString().padLeft(2, '0');

    final progress = (totalSec > 0 && _playingMessageId == 'draft_voice_note' && _playbackDuration.inMilliseconds > 0)
        ? (_playbackPosition.inMilliseconds / _playbackDuration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.08),
        border: Border(
          top: BorderSide(color: colorScheme.primary.withValues(alpha: 0.3)),
          bottom: BorderSide(color: colorScheme.primary.withValues(alpha: 0.15)),
        ),
      ),
      child: Row(
        children: [
          // Play / Pause circular action button
          Material(
            color: colorScheme.primary,
            shape: const CircleBorder(),
            elevation: 1,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _playPauseDraftVoiceNote,
              child: Padding(
                padding: const EdgeInsets.all(7.0),
                child: Icon(
                  isThisPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: 18,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Waveform icon and draft label
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.graphic_eq_rounded, size: 16, color: colorScheme.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        strings.draftVoiceNoteLabel,
                        style: GoogleFonts.cairo(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$minStr:$secStr / $totalMinStr:$totalSecStr',
                      style: GoogleFonts.sourceCodePro(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: isThisPlaying ? progress : 0.0,
                    minHeight: 4,
                    backgroundColor: colorScheme.primary.withValues(alpha: 0.2),
                    valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),

          // Delete draft voice note button
          Tooltip(
            message: strings.removeDraftVoiceNote,
            child: InkWell(
              onTap: _removeDraftVoiceNote,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.close_rounded, size: 16, color: colorScheme.onErrorContainer),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageInputBar(ColorScheme colorScheme, bool isAr, AppStrings strings) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5))),
      ),
      child: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              icon: const Icon(Icons.add_photo_alternate_rounded, size: 24),
              color: colorScheme.primary,
              tooltip: isAr ? 'إرفاق صورة بون (أو الصق مباشرة Ctrl+V)' : 'Attach Receipt Image (or Paste Ctrl+V)',
              onPressed: _isLoading || _isTranscribingVoice ? null : _pickImage,
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.mic_rounded, size: 24),
              color: colorScheme.primary,
              tooltip: strings.voiceRecordTooltip,
              onPressed: _isLoading || _isTranscribingVoice ? null : _startVoiceRecording,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                ),
                child: TextField(
                  controller: _promptController,
                  maxLines: 4,
                  minLines: 1,
                  style: GoogleFonts.cairo(fontSize: 13.5),
                  decoration: InputDecoration(
                    hintText: isAr
                        ? 'اكتب، أو الصق صورة بالماوس/الكيبورد 📋، أو تحدث بالصوت 🎙️...'
                        : 'Type, paste image (Ctrl+V) 📋, or speak 🎙️ to describe rule...',
                    hintStyle: GoogleFonts.cairo(fontSize: 12.5, color: colorScheme.onSurfaceVariant),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  onSubmitted: (_) => _handleSendMessage(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              icon: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send_rounded, size: 20),
              onPressed: (_isLoading || _isTranscribingVoice) ? null : () => _handleSendMessage(),
              style: IconButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
