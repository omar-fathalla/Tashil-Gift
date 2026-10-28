import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

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
  final FirebaseFunctions _functions;

  CloudGenerativeModel({
    required this.model,
    this.systemInstruction,
    this.generationConfig,
    this.safetySettings = const [],
    FirebaseFunctions? functions,
  }) : _functions = functions ?? FirebaseFunctions.instance;

  Future<CloudGenerateContentResponse> generateContent(
    Iterable<Content> contents, {
    GenerationConfig? generationConfig,
    List<SafetySetting>? safetySettings,
  }) async {
    final effectiveConfig = generationConfig ?? this.generationConfig;
    final effectiveSafety = safetySettings ?? this.safetySettings;

    final payload = <String, dynamic>{
      'model': model,
      'contents': contents.map((c) => c.toJson()).toList(),
      if (systemInstruction != null)
        'systemInstruction': systemInstruction!.toJson(),
      if (effectiveConfig != null) 'generationConfig': effectiveConfig.toJson(),
      if (effectiveSafety.isNotEmpty)
        'safetySettings': effectiveSafety.map((s) => s.toJson()).toList(),
    };

    try {
      final callable = _functions.httpsCallable(
        'geminiGenerate',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 120)),
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
