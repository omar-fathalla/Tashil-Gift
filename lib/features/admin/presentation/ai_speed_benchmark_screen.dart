import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/ai_receipt_service.dart';
import '../../../core/constants/country_currency_config.dart';
import '../../../core/localization/locale_provider.dart';
import '../../../core/widgets/m3_button_groups.dart';
import '../../../core/widgets/m3_progress_indicators.dart';
import '../../../core/animations/m3_motion.dart';

enum BenchmarkMode {
  instantSample,
  cameraPhoto,
  galleryFile,
  stressTest,
  deepAuditTest,
}

class BenchmarkRecord {
  final int runNumber;
  final double durationSeconds;
  final int durationMs;
  final int aiDurationMs;
  final int dartDurationMs;
  final String pipelineTier;
  final int imageBytesSize;
  final String kpiRating;
  final String modelName;
  final bool isValid;
  final String receiptNumber;
  final double targetTotal;
  final String storeChain;
  final String branch;
  final DateTime timestamp;

  BenchmarkRecord({
    required this.runNumber,
    required this.durationSeconds,
    required this.durationMs,
    this.aiDurationMs = 0,
    this.dartDurationMs = 0,
    this.pipelineTier = 'fast_tier',
    required this.imageBytesSize,
    required this.kpiRating,
    required this.modelName,
    required this.isValid,
    required this.receiptNumber,
    required this.targetTotal,
    required this.storeChain,
    required this.branch,
    required this.timestamp,
  });
}

class AiSpeedBenchmarkScreen extends ConsumerStatefulWidget {
  const AiSpeedBenchmarkScreen({super.key});

  @override
  ConsumerState<AiSpeedBenchmarkScreen> createState() => _AiSpeedBenchmarkScreenState();
}

class _AiSpeedBenchmarkScreenState extends ConsumerState<AiSpeedBenchmarkScreen>
    with SingleTickerProviderStateMixin {
  final ImagePicker _picker = ImagePicker();
  BenchmarkMode _selectedMode = BenchmarkMode.instantSample;
  Uint8List? _imageBytes;
  int _lastImageSize = 0;
  bool _isRunningTest = false;
  Timer? _liveTimer;
  double _elapsedSeconds = 0.0;
  String _currentPhaseText = '';
  AiReceiptAnalysisResult? _lastResult;
  bool _showRawJson = false;

  final List<BenchmarkRecord> _history = [];
  int _testCounter = 0;

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _startLiveTimer() {
    _elapsedSeconds = 0.0;
    _liveTimer?.cancel();
    final startTime = DateTime.now();
    _liveTimer = Timer.periodic(const Duration(milliseconds: 40), (timer) {
      if (mounted && _isRunningTest) {
        setState(() {
          _elapsedSeconds = DateTime.now().difference(startTime).inMilliseconds / 1000.0;
        });
      }
    });
  }

  void _stopLiveTimer() {
    _liveTimer?.cancel();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 80,
      );
      if (picked != null) {
        final bytes = await picked.readAsBytes();
        setState(() {
          _imageBytes = bytes;
          _lastImageSize = bytes.length;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ أثناء اختيار الصورة: $e')),
        );
      }
    }
  }

  Future<Uint8List> _generateSampleReceiptImage() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 600, 800));
    final bgPaint = Paint()..color = Colors.white;
    canvas.drawRect(const Rect.fromLTWH(0, 0, 600, 800), bgPaint);

    final borderPaint = Paint()
      ..color = Colors.grey.shade400
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(const Rect.fromLTWH(20, 20, 560, 760), borderPaint);

    void drawText(String text, double x, double y, {double fontSize = 16, bool isBold = false, Color color = Colors.black}) {
      final textSpan = TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.rtl,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x - textPainter.width, y));
    }

    drawText('أسواق فتح الله للجملة - Fathalla Market', 550, 50, fontSize: 20, isBold: true);
    drawText('فرع سموحة - الإسكندرية', 550, 85, fontSize: 16);
    drawText('رقم الفاتورة: 295/8/211/220726', 550, 120, fontSize: 15, isBold: true);
    drawText('التاريخ: 22/07/2026 14:30', 550, 150, fontSize: 14);

    final linePaint = Paint()..color = Colors.black45..strokeWidth = 1;
    canvas.drawLine(const Offset(40, 190), const Offset(560, 190), linePaint);

    drawText('الصنف', 550, 210, fontSize: 16, isBold: true);
    drawText('الكمية', 300, 210, fontSize: 16, isBold: true);
    drawText('السعر', 120, 210, fontSize: 16, isBold: true);

    canvas.drawLine(const Offset(40, 240), const Offset(560, 240), linePaint);

    drawText('حليب المراعي كامل الدسم 1 لتر', 550, 260, fontSize: 15);
    drawText('3', 290, 260, fontSize: 15);
    drawText('135.00 ج.م', 120, 260, fontSize: 15);

    drawText('زبادي المراعي طبيعي 105 جم', 550, 300, fontSize: 15);
    drawText('6', 290, 300, fontSize: 15);
    drawText('60.00 ج.م', 120, 300, fontSize: 15);

    drawText('عصير المراعي برتقال 1 لتر', 550, 340, fontSize: 15);
    drawText('2', 290, 340, fontSize: 15);
    drawText('70.00 ج.م', 120, 340, fontSize: 15);

    drawText('شاي العروسة 250 جم', 550, 380, fontSize: 15);
    drawText('1', 290, 380, fontSize: 15);
    drawText('45.00 ج.م', 120, 380, fontSize: 15);

    canvas.drawLine(const Offset(40, 430), const Offset(560, 430), linePaint);

    drawText('إجمالي منتجات المراعي: 265.00 ج.م', 550, 460, fontSize: 18, isBold: true, color: Colors.blue.shade900);
    drawText('الإجمالي الكلي: 310.00 ج.م', 550, 500, fontSize: 18, isBold: true);

    drawText('شكراً لزيارتكم أسواق فتح الله', 400, 680, fontSize: 16, isBold: true);

    final picture = recorder.endRecording();
    final img = await picture.toImage(600, 800);
    final pngBytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return pngBytes!.buffer.asUint8List();
  }

  Future<void> _executeBenchmark() async {
    if (_selectedMode == BenchmarkMode.instantSample ||
        _selectedMode == BenchmarkMode.stressTest ||
        _selectedMode == BenchmarkMode.deepAuditTest) {
      final sampleBytes = await _generateSampleReceiptImage();
      setState(() {
        _imageBytes = sampleBytes;
        _lastImageSize = sampleBytes.length;
      });
    }

    if (_imageBytes == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى التقاط صورة أو اختيار فاتورة أولاً.')),
      );
      return;
    }

    setState(() {
      _isRunningTest = true;
      _lastResult = null;
      _currentPhaseText = '1/3 ضغط الصورة وتحسين أبعادها...';
    });

    _startLiveTimer();

    try {
      final aiService = ref.read(aiReceiptServiceProvider);

      if (_selectedMode == BenchmarkMode.stressTest) {
        // Run 3 sequential iterations for robust statistical benchmarking
        for (int i = 1; i <= 3; i++) {
          if (!mounted) return;
          setState(() {
            _currentPhaseText = 'جاري تنفيذ الاختبار التكراري $i من 3...';
          });
          final result = await aiService.analyzeReceiptImage(
            _imageBytes!,
            'image/jpeg',
            targetCompany: 'المراعي',
            minimumSpend: 50.0,
            retailChainName: 'أسواق فتح الله',
          );
          _testCounter++;
          _history.insert(
            0,
            BenchmarkRecord(
              runNumber: _testCounter,
              durationSeconds: result.durationSeconds,
              durationMs: result.durationMs,
              aiDurationMs: result.aiDurationMs,
              dartDurationMs: result.dartDurationMs,
              pipelineTier: result.pipelineTierUsed,
              imageBytesSize: _lastImageSize,
              kpiRating: result.kpiRating,
              modelName: aiService.fastTierModelName,
              isValid: result.isValid,
              receiptNumber: result.receiptNumber,
              targetTotal: result.targetCompanyTotal,
              storeChain: result.storeChainDetected,
              branch: result.branchDetected,
              timestamp: DateTime.now(),
            ),
          );
          if (i == 3) {
            _lastResult = result;
          }
        }
      } else {
        final bool isDeepAudit = _selectedMode == BenchmarkMode.deepAuditTest;
        setState(() {
          _currentPhaseText = isDeepAudit
              ? '2/3 استدعاء مسار الاستدلال والتدقيق العميق (Deep Tier)...'
              : '2/3 استدعاء مسار Gemini 3.7 Flash الفائق السرعة (Fast Tier)...';
        });

        final result = await aiService.analyzeReceiptImage(
          _imageBytes!,
          'image/jpeg',
          targetCompany: 'المراعي',
          minimumSpend: 50.0,
          retailChainName: 'أسواق فتح الله',
          forceDeepAudit: isDeepAudit,
        );

        setState(() {
          _currentPhaseText = '3/3 تدقيق وتنسيق البيانات المستخرجة محلياً...';
        });

        _testCounter++;
        final record = BenchmarkRecord(
          runNumber: _testCounter,
          durationSeconds: result.durationSeconds,
          durationMs: result.durationMs,
          aiDurationMs: result.aiDurationMs,
          dartDurationMs: result.dartDurationMs,
          pipelineTier: result.pipelineTierUsed,
          imageBytesSize: _lastImageSize,
          kpiRating: result.kpiRating,
          modelName: isDeepAudit ? aiService.deepAuditModelName : aiService.fastTierModelName,
          isValid: result.isValid,
          receiptNumber: result.receiptNumber,
          targetTotal: result.targetCompanyTotal,
          storeChain: result.storeChainDetected,
          branch: result.branchDetected,
          timestamp: DateTime.now(),
        );

        _lastResult = result;
        _history.insert(0, record);
      }

      _stopLiveTimer();

      if (mounted) {
        setState(() {
          _isRunningTest = false;
          _elapsedSeconds = _lastResult?.durationSeconds ?? _elapsedSeconds;
          _currentPhaseText = '';
        });

        await M3Feedback.showSuccess(
          context,
          title: 'اكتمل اختبار السرعة بنجاح',
          message: 'تم فحص الفاتورة واستخراج البيانات في ${_lastResult?.durationSeconds.toStringAsFixed(2)} ثانية (${_lastResult?.kpiRating}).',
          buttonText: 'عرض النتائج',
        );
      }
    } catch (e) {
      _stopLiveTimer();
      if (mounted) {
        setState(() {
          _isRunningTest = false;
          _currentPhaseText = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ أثناء اختبار الذكاء الاصطناعي: $e')),
        );
      }
    }
  }

  void _exportHistoryCsv() {
    if (_history.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد سجلات لتصديرها حالياً.')),
      );
      return;
    }

    final StringBuffer buffer = StringBuffer();
    buffer.writeln('Run,Duration_Seconds,Duration_MS,KPI_Rating,Size_KB,Receipt_Number,Total,Store,Branch,Timestamp');
    for (final h in _history) {
      buffer.writeln(
        '${h.runNumber},${h.durationSeconds},${h.durationMs},"${h.kpiRating}",${(h.imageBytesSize / 1024).toStringAsFixed(1)},"${h.receiptNumber}",${h.targetTotal},"${h.storeChain}","${h.branch}","${h.timestamp.toIso8601String()}"',
      );
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم نسخ بيانات التقرير بتنسيق CSV إلى الحافظة بنجاح.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isAr = ref.isArabic;
    final activeCountry = ref.watch(activeCountryProvider);

    final double avgSeconds = _history.isEmpty
        ? 0.0
        : (_history.map((e) => e.durationSeconds).reduce((a, b) => a + b) / _history.length);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.speed_rounded, color: colorScheme.onPrimaryContainer, size: 22),
            ),
            const SizedBox(width: 12),
            Text(
              isAr ? 'أداة قياس واختبار سرعة الذكاء الاصطناعي (KPI Benchmark)' : 'AI Latency & Speed Benchmark',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        actions: [
          if (_history.isNotEmpty)
            Tooltip(
              message: isAr ? 'تصدير سجل التجارب بصيغة CSV' : 'Export CSV',
              waitDuration: const Duration(milliseconds: 400),
              child: IconButton(
                icon: const Icon(Icons.download_rounded),
                onPressed: _exportHistoryCsv,
              ),
            ),
          Tooltip(
            message: isAr ? 'إعادة ضبط وحذف سجل الجلسة' : 'Reset History',
            waitDuration: const Duration(milliseconds: 400),
            child: IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () {
                setState(() {
                  _history.clear();
                  _lastResult = null;
                  _testCounter = 0;
                  _elapsedSeconds = 0.0;
                });
              },
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Header Explanation Card (M3 Elevated)
            Card(
              elevation: 0,
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.bolt_rounded, size: 28, color: colorScheme.onPrimaryContainer),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isAr ? 'نظام قياس زمن الاستجابة الفعلي وتحليل الفواتير' : 'Real-time AI Latency & Inference Tracker',
                            style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 15, color: colorScheme.onSurface),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isAr
                                ? 'يقيس هذا النظام بالمللي ثانية زمن المعالجة وضغط الصورة واستجابة محرك Gemini لضمان عدم انتظار العميل أمام الكاشير.'
                                : 'Measures end-to-end image compression and Gemini inference time down to the millisecond.',
                            style: GoogleFonts.cairo(fontSize: 12, color: colorScheme.onSurfaceVariant, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // 2. Hero Latency & Speedometer Card (Material Design 3)
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              color: colorScheme.surfaceContainerLow,
              child: Padding(
                padding: const EdgeInsets.all(28.0),
                child: Column(
                  children: [
                    Text(
                      isAr ? 'زمن الاستجابة للعملية (Response Duration)' : 'Response Duration',
                      style: GoogleFonts.cairo(fontSize: 14, color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 16),

                    // Animated Speed Gauge Pill
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        final pulseScale = _isRunningTest ? (1.0 + _pulseController.value * 0.03) : 1.0;
                        final bool isUltraFast = _elapsedSeconds <= 2.0 && _elapsedSeconds > 0;
                        final Color pillBgColor = _isRunningTest
                            ? colorScheme.primary
                            : (isUltraFast ? colorScheme.primaryContainer : colorScheme.surfaceContainerHighest);
                        final Color pillTextColor = _isRunningTest
                            ? colorScheme.onPrimary
                            : (isUltraFast ? colorScheme.onPrimaryContainer : colorScheme.onSurface);

                        return Transform.scale(
                          scale: pulseScale,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                            decoration: BoxDecoration(
                              color: pillBgColor,
                              borderRadius: BorderRadius.circular(36),
                              boxShadow: [
                                BoxShadow(
                                  color: colorScheme.primary.withValues(alpha: _isRunningTest ? 0.25 : 0.08),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_isRunningTest) ...[
                                  SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      color: colorScheme.onPrimary,
                                      strokeWidth: 2.8,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                ] else ...[
                                  Icon(Icons.bolt_rounded, color: pillTextColor, size: 28),
                                  const SizedBox(width: 8),
                                ],
                                Text(
                                  '${_elapsedSeconds.toStringAsFixed(2)} ${isAr ? "ثانية" : "s"}',
                                  style: GoogleFonts.spaceMono(
                                    fontSize: 34,
                                    fontWeight: FontWeight.bold,
                                    color: pillTextColor,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),

                    if (_isRunningTest && _currentPhaseText.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        _currentPhaseText,
                        style: GoogleFonts.cairo(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const SizedBox(
                        width: 320,
                        child: M3LinearProgress(height: 6.0),
                      ),
                    ],

                    const SizedBox(height: 18),

                    // Active KPI Rating Badge
                    if (_lastResult != null && !_isRunningTest) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: colorScheme.outlineVariant),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_outline_rounded, size: 16, color: colorScheme.onSecondaryContainer),
                            const SizedBox(width: 6),
                            Text(
                              _lastResult!.kpiRating,
                              style: GoogleFonts.cairo(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSecondaryContainer,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 6,
                        alignment: WrapAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: _lastResult!.pipelineTierUsed == 'fast_tier'
                                  ? Colors.amber.withValues(alpha: 0.15)
                                  : Colors.purple.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _lastResult!.pipelineTierUsed == 'fast_tier'
                                    ? Colors.amber.shade700
                                    : Colors.purple.shade400,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _lastResult!.pipelineTierUsed == 'fast_tier'
                                      ? Icons.electric_bolt_rounded
                                      : Icons.psychology_rounded,
                                  size: 16,
                                  color: _lastResult!.pipelineTierUsed == 'fast_tier'
                                      ? Colors.amber.shade800
                                      : Colors.purple.shade700,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _lastResult!.pipelineTierUsed == 'fast_tier'
                                      ? (isAr ? 'المسار السريع الفوري (Fast Tier)' : 'Fast Flash Tier')
                                      : (isAr ? 'مسار الاستدلال والتدقيق العميق (Deep Tier)' : 'Deep Audit Tier'),
                                  style: GoogleFonts.cairo(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: _lastResult!.pipelineTierUsed == 'fast_tier'
                                        ? Colors.amber.shade900
                                        : Colors.purple.shade900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_lastResult!.aiDurationMs > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: colorScheme.outlineVariant),
                              ),
                              child: Text(
                                '🤖 AI: ${_lastResult!.aiDurationMs}ms | 🎯 Dart: ${_lastResult!.dartDurationMs}ms',
                                style: GoogleFonts.spaceMono(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 22),

                    // M3 KPI Speed Tier Chips
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        _buildM3KpiChip(
                          context,
                          label: '< 2.0s',
                          desc: isAr ? 'فائق السرعة (مثالي لنقاط البيع)' : 'Ultra Fast',
                          icon: Icons.flash_on_rounded,
                          tooltip: 'الزمن المستهدف الموصى به لتفادي أي انتظار أمام الكاشير',
                        ),
                        _buildM3KpiChip(
                          context,
                          label: '2.0s - 3.5s',
                          desc: isAr ? 'ممتاز' : 'Excellent',
                          icon: Icons.check_circle_rounded,
                          tooltip: 'زمن استجابة سريع جداً وتجربة سلسة',
                        ),
                        _buildM3KpiChip(
                          context,
                          label: '3.5s - 5.0s',
                          desc: isAr ? 'مقبول' : 'Acceptable',
                          icon: Icons.info_rounded,
                          tooltip: 'زمن استجابة متوسط ومقبول',
                        ),
                        _buildM3KpiChip(
                          context,
                          label: '> 5.0s',
                          desc: isAr ? 'يحتاج تحسين' : 'Slow',
                          icon: Icons.warning_amber_rounded,
                          tooltip: 'زمن طويل قد يسبب بطء في تدفق العملاء',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // 3. Test Mode Selector & Actions Card (M3 Button Groups)
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isAr ? 'نمط وبيئة اختبار السرعة' : 'Benchmark Mode & Controls',
                      style: GoogleFonts.cairo(fontSize: 15, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                    ),
                    const SizedBox(height: 14),

                    // Mode Selection via M3ConnectedButtonGroup
                    M3ConnectedButtonGroup<BenchmarkMode>(
                      selectedValue: _selectedMode,
                      onSelected: (mode) async {
                        setState(() => _selectedMode = mode);
                        if (mode == BenchmarkMode.cameraPhoto) {
                          await _pickImage(ImageSource.camera);
                        } else if (mode == BenchmarkMode.galleryFile) {
                          await _pickImage(ImageSource.gallery);
                        }
                      },
                      segments: [
                        M3ButtonSegment(
                          value: BenchmarkMode.instantSample,
                          label: isAr ? 'عينة فورية' : 'Sample',
                          icon: Icons.science_rounded,
                          tooltip: 'إجراء فحص تجريبي سريع باستخدام نموذج فاتورة حقيقي مدمج بالذاكرة',
                        ),
                        M3ButtonSegment(
                          value: BenchmarkMode.cameraPhoto,
                          label: isAr ? 'كاميرا' : 'Camera',
                          icon: Icons.camera_alt_rounded,
                          tooltip: 'التقاط صورة فاتورة مباشرة عبر كاميرا الجهاز وفحصها',
                        ),
                        M3ButtonSegment(
                          value: BenchmarkMode.galleryFile,
                          label: isAr ? 'استوديو / ملف' : 'File',
                          icon: Icons.photo_library_rounded,
                          tooltip: 'اختيار ملف صورة فاتورة من جهازك وإجراء فحص السرعة عليها',
                        ),
                        M3ButtonSegment(
                          value: BenchmarkMode.stressTest,
                          label: isAr ? 'اختبار تكراري x3' : 'Stress Test',
                          icon: Icons.repeat_rounded,
                          tooltip: 'تشغيل 3 اختبارات متتالية لاحتساب متوسط زمن الاستجابة الإحصائي',
                        ),
                        M3ButtonSegment(
                          value: BenchmarkMode.deepAuditTest,
                          label: isAr ? 'تدقيق عميق' : 'Deep Audit',
                          icon: Icons.psychology_rounded,
                          tooltip: 'فحص استثنائي باستخدام مسار الاستدلال والتدقيق الجنائي العميق',
                        ),
                      ],
                    ),

                    const SizedBox(height: 18),

                    // Trigger Button with M3 Motion
                    Row(
                      children: [
                        Expanded(
                          child: M3ActionButton(
                            label: _isRunningTest
                                ? (isAr ? 'جاري الفحص وقياس السرعة...' : 'Benchmarking...')
                                : (isAr ? 'بدء اختبار السرعة الآن' : 'Run Speed Benchmark'),
                            icon: Icons.play_arrow_rounded,
                            isLoading: _isRunningTest,
                            variant: M3ButtonVariant.filled,
                            onPressed: _isRunningTest ? null : () => _executeBenchmark(),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // 4. Latest Result Scorecard & Data Inspector
            if (_lastResult != null) ...[
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.analytics_outlined, color: colorScheme.primary, size: 22),
                              const SizedBox(width: 8),
                              Text(
                                isAr ? 'تقرير نتيجة الفحص الأخير' : 'Latest Benchmark Result',
                                style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _lastResult!.isValid ? colorScheme.primaryContainer : colorScheme.errorContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _lastResult!.isValid
                                  ? (isAr ? 'فاتورة مقبولة ومطابقة' : 'Valid Receipt')
                                  : (isAr ? 'فاتورة غير مطابقة' : 'Invalid Receipt'),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: _lastResult!.isValid ? colorScheme.onPrimaryContainer : colorScheme.onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      Row(
                        children: [
                          _buildM3MetricTile(
                            context: context,
                            icon: Icons.timer_outlined,
                            label: isAr ? 'زمن الاستجابة الكلي' : 'Latency',
                            value: '${_lastResult!.durationSeconds.toStringAsFixed(2)}s (${_lastResult!.durationMs}ms)',
                          ),
                          _buildM3MetricTile(
                            context: context,
                            icon: Icons.compress_rounded,
                            label: isAr ? 'حجم الصورة بعد الضغط' : 'Payload Size',
                            value: '${(_lastImageSize / 1024).toStringAsFixed(1)} KB',
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _buildM3MetricTile(
                            context: context,
                            icon: Icons.receipt_long_rounded,
                            label: isAr ? 'رقم الفاتورة المستخرج' : 'Receipt #',
                            value: _lastResult!.receiptNumber.isNotEmpty ? _lastResult!.receiptNumber : 'N/A',
                          ),
                          _buildM3MetricTile(
                            context: context,
                            icon: Icons.account_balance_wallet_rounded,
                            label: isAr ? 'إجمالي منتجات العرض' : 'Target Total',
                            value: '${_lastResult!.targetCompanyTotal} ${activeCountry.currencySymbol}',
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _buildM3MetricTile(
                            context: context,
                            icon: Icons.storefront_rounded,
                            label: isAr ? 'السلسلة والفرع' : 'Store & Branch',
                            value: '${_lastResult!.storeChainDetected} - ${_lastResult!.branchDetected}',
                          ),
                          _buildM3MetricTile(
                            context: context,
                            icon: Icons.calendar_today_rounded,
                            label: isAr ? 'تاريخ الشراء' : 'Date',
                            value: _lastResult!.receiptDate.isNotEmpty ? _lastResult!.receiptDate : 'N/A',
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          _lastResult!.message,
                          style: GoogleFonts.cairo(fontSize: 13, height: 1.4, color: colorScheme.onSurface),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Raw JSON Expander Toggle
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: () => setState(() => _showRawJson = !_showRawJson),
                            icon: Icon(_showRawJson ? Icons.code_off_rounded : Icons.code_rounded, size: 18),
                            label: Text(
                              _showRawJson ? (isAr ? 'إخفاء كود JSON' : 'Hide JSON') : (isAr ? 'عرض بيانات JSON الخام' : 'View Raw JSON'),
                              style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                          if (_showRawJson) ...[
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.copy_rounded, size: 18),
                              tooltip: isAr ? 'نسخ JSON' : 'Copy JSON',
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: jsonEncode(_lastResult!.toJson())));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('تم نسخ بيانات JSON بنجاح')),
                                );
                              },
                            ),
                          ],
                        ],
                      ),

                      if (_showRawJson) ...[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: colorScheme.outlineVariant),
                          ),
                          child: SelectableText(
                            const JsonEncoder.withIndent('  ').convert(_lastResult!.toJson()),
                            style: GoogleFonts.firaCode(fontSize: 11, color: colorScheme.onSurface),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],

            // 5. Benchmark Session History Table
            if (_history.isNotEmpty) ...[
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.history_rounded, color: colorScheme.primary, size: 22),
                              const SizedBox(width: 8),
                              Text(
                                isAr ? 'سجل اختبارات الجلسة الحالية' : 'Benchmark Session History',
                                style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${isAr ? "متوسط السرعة: " : "Avg Latency: "}${avgSeconds.toStringAsFixed(2)}s',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columnSpacing: 22,
                          columns: [
                            DataColumn(label: Text(isAr ? 'رقم التجربة' : 'Run #', style: const TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text(isAr ? 'المسار' : 'Tier', style: const TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text(isAr ? 'زمن الاستجابة' : 'Latency', style: const TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text(isAr ? 'تفصيل الزمن' : 'Breakdown', style: const TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text(isAr ? 'تقييم KPI' : 'KPI Rating', style: const TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text(isAr ? 'حجم الصورة' : 'Size', style: const TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text(isAr ? 'رقم الفاتورة' : 'Receipt #', style: const TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text(isAr ? 'الإجمالي' : 'Total', style: const TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text(isAr ? 'الوقت' : 'Time', style: const TextStyle(fontWeight: FontWeight.bold))),
                          ],
                          rows: _history.map((h) {
                            return DataRow(
                              cells: [
                                DataCell(Text('#${h.runNumber}')),
                                DataCell(
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: h.pipelineTier == 'Deep Tier'
                                          ? colorScheme.tertiaryContainer
                                          : colorScheme.secondaryContainer,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      h.pipelineTier,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: h.pipelineTier == 'Deep Tier'
                                            ? colorScheme.onTertiaryContainer
                                            : colorScheme.onSecondaryContainer,
                                      ),
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    '${h.durationSeconds.toStringAsFixed(2)}s',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: h.durationSeconds <= 2.0
                                          ? colorScheme.primary
                                          : colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    'AI: ${h.aiDurationMs}ms | Dart: ${h.dartDurationMs}ms',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                                DataCell(Text(h.kpiRating, style: const TextStyle(fontSize: 12))),
                                DataCell(Text('${(h.imageBytesSize / 1024).toStringAsFixed(1)} KB')),
                                DataCell(Text(h.receiptNumber.isNotEmpty ? h.receiptNumber : 'N/A')),
                                DataCell(Text('${h.targetTotal} ${activeCountry.currencySymbol}')),
                                DataCell(
                                   Builder(
                                     builder: (context) {
                                       final hour = h.timestamp.hour == 0 ? 12 : (h.timestamp.hour > 12 ? h.timestamp.hour - 12 : h.timestamp.hour);
                                       final period = h.timestamp.hour >= 12 ? 'PM' : 'AM';
                                       return Text(
                                         '${hour.toString().padLeft(2, '0')}:${h.timestamp.minute.toString().padLeft(2, '0')}:${h.timestamp.second.toString().padLeft(2, '0')} $period',
                                         style: const TextStyle(fontSize: 11),
                                       );
                                     },
                                   ),
                                 ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildM3KpiChip(
    BuildContext context, {
    required String label,
    required String desc,
    required IconData icon,
    required String tooltip,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: colorScheme.primary),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: colorScheme.onSurface),
            ),
            const SizedBox(width: 4),
            Text(
              '($desc)',
              style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildM3MetricTile({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: GoogleFonts.cairo(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                  Text(
                    value,
                    style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
