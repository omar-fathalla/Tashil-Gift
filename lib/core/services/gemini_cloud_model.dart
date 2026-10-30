import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'firebase_scope.dart';

/// Result of a server-proxied Gemini generateContent call.
///
/// Mirrors the subset of [GenerateContentResponse] that Tashil Gift uses
/// (primarily [.text]).
class CloudGenerateContentResponse {
  final String? text;
  final Map<String, dynamic> raw;

  const CloudGenerateContentResponse({this.text, this.raw = const {}});

  factory CloudGenerateContentResponse.fromGeminiJson(Map<String, dynamic> json) {
    String? text;
    final candidates = json['candidates'];
    if (candidates is List && candidates.isNotEmpty) {
      final first = candidates.first;
      if (first is Map) {
        final content = first['content'];
        if (content is Map) {
          final parts = content['parts'];
          if (parts is List) {
            final buf = StringBuffer();
            for (final part in parts) {
              if (part is Map && part['text'] is String) {
                buf.write(part['text'] as String);
              }
            }
            final joined = buf.toString();
            if (joined.isNotEmpty) text = joined;
          }
        }
      }
    }
    return CloudGenerateContentResponse(text: text, raw: json);
  }
}

/// Drop-in stand-in for [GenerativeModel] that never holds a Gemini API key.
///
/// All generateContent traffic goes through the `geminiGenerate` Cloud Function,
/// which reads `GEMINI_API_KEY` from Firebase Secrets.
class CloudGenerativeModel {
  final String model;
  final Content? systemInstruction;
  final GenerationConfig? generationConfig;
  final List<SafetySetting> safetySettings;

  /// 2.0.148+208: optional Gemini `thinkingConfig` (e.g. `{'thinkingLevel': 'low'}`)
  /// merged into `generationConfig`. google_generative_ai's GenerationConfig has
  /// no thinking field, so it is injected into the JSON sent to geminiGenerate
  /// (which passes generationConfig through unchanged). If Gemini rejects the
  /// field (400 on an older model), the call is retried once without it.
  final Map<String, dynamic>? thinkingConfig;
  final FirebaseFunctions _functions;

  /// 2.0.150+211: callable cap (server aborts upstream at 38s, function 60s).
  static const Duration callableTimeout = Duration(seconds: 45);

  CloudGenerativeModel({
    required this.model,
    this.systemInstruction,
    this.generationConfig,
    this.safetySettings = const [],
    this.thinkingConfig,
    FirebaseFunctions? functions,
  }) : _functions = functions ?? scopedFunctions();

  Future<CloudGenerateContentResponse> generateContent(
    Iterable<Content> contents, {
    GenerationConfig? generationConfig,
    List<SafetySetting>? safetySettings,
  }) async {
    final effectiveConfig = generationConfig ?? this.generationConfig;
    final effectiveSafety = safetySettings ?? this.safetySettings;
    final contentsJson = contents.map((c) => c.toJson()).toList();
    if (thinkingConfig != null && thinkingConfig!.isNotEmpty) {
      try {
        return await _call(contentsJson, effectiveConfig, effectiveSafety,
            withThinking: true);
      } on FirebaseFunctionsException catch (e) {
        final msg = '${e.code} ${e.message ?? ''}'.toLowerCase();
        final rejectedThinking = msg.contains('thinking') &&
            (msg.contains('invalid') || msg.contains('400') ||
                msg.contains('unknown') || msg.contains('not supported'));
        if (!rejectedThinking) rethrow;
        debugPrint('geminiGenerate: thinkingConfig rejected for $model; retrying without it');
      }
    }
    return _call(contentsJson, effectiveConfig, effectiveSafety,
        withThinking: false);
  }

  Future<CloudGenerateContentResponse> _call(
    List<Object?> contentsJson,
    GenerationConfig? effectiveConfig,
    List<SafetySetting> effectiveSafety, {
    required bool withThinking,
  }) async {
    Map<String, dynamic>? configJson;
    if (effectiveConfig != null) {
      configJson = Map<String, dynamic>.from(
          jsonDecode(jsonEncode(effectiveConfig.toJson())) as Map);
    }
    if (withThinking && thinkingConfig != null) {
      configJson = {...?configJson, 'thinkingConfig': thinkingConfig};
    }

    final payload = <String, dynamic>{
      'model': model,
      'contents': contentsJson,
      if (systemInstruction != null)
        'systemInstruction': systemInstruction!.toJson(),
      'generationConfig': ?configJson,
      if (effectiveSafety.isNotEmpty)
        'safetySettings': effectiveSafety.map((s) => s.toJson()).toList(),
    };

    try {
      final callable = _functions.httpsCallable(
        'geminiGenerate',
        options: HttpsCallableOptions(timeout: callableTimeout),
      );
      // Normalize to plain JSON (Maps/Lists/primitives). google_generative_ai's
      // toJson() leaves nested objects (e.g. Schema under responseSchema) that
      // the web callable cannot serialize ("e.hasOwnProperty is not a function").
      final safePayload = jsonDecode(jsonEncode(payload));
      final result = await callable.call(safePayload);
      final data = result.data;
      if (data is Map) {
        final map = Map<String, dynamic>.from(
          data.map((key, value) => MapEntry(key.toString(), value)),
        );
        if (map['error'] != null) {
          throw FirebaseFunctionsException(
            code: 'internal',
            message: map['error'].toString(),
          );
        }
        // Server returns the raw Gemini generateContent JSON under `response`,
        // or the raw object itself for forward-compat.
        final responseNode = map['response'] is Map
            ? Map<String, dynamic>.from(
                (map['response'] as Map).map(
                  (k, v) => MapEntry(k.toString(), v),
                ),
              )
            : map;
        return CloudGenerateContentResponse.fromGeminiJson(responseNode);
      }
      throw FirebaseFunctionsException(
        code: 'internal',
        message: 'Unexpected geminiGenerate response type: ${data.runtimeType}',
      );
    } on FirebaseFunctionsException {
      rethrow;
    } catch (e, st) {
      debugPrint('geminiGenerate proxy failed: $e\n$st');
      throw FirebaseFunctionsException(
        code: 'internal',
        message: 'AI_SERVICE_ERROR: $e',
      );
    }
  }
}
