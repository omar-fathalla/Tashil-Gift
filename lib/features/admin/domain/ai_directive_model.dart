import 'package:al_mraay/core/constants/ai_models.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

/// Categories of AI directives and heuristics taught to the agent
enum AiDirectiveCategory {
  promotionalRules, // خوارزميات احتساب وتفكيك العروض
  nlpMatching, // مطابقة المنتجات والتهجئة الذكية
  branchGovernance, // حوكمة واسترداد الفروع والسلاسل
  unitEconomics, // اقتصاديات وأسعار القطعة الواحدة
  fraudSecurity, // مكافحة التلاعب وسلامة البونات
}

extension AiDirectiveCategoryExt on AiDirectiveCategory {
  String get key {
    switch (this) {
      case AiDirectiveCategory.promotionalRules:
        return 'promotional_rules';
      case AiDirectiveCategory.nlpMatching:
        return 'nlp_matching';
      case AiDirectiveCategory.branchGovernance:
        return 'branch_governance';
      case AiDirectiveCategory.unitEconomics:
        return 'unit_economics';
      case AiDirectiveCategory.fraudSecurity:
        return 'fraud_security';
    }
  }

  String getLabel(bool isAr) {
    switch (this) {
      case AiDirectiveCategory.promotionalRules:
        return isAr ? 'خوارزميات احتساب العروض' : 'Promotional & Waterfall Rules';
      case AiDirectiveCategory.nlpMatching:
        return isAr ? 'مطابقة المنتجات والتهجئة' : 'NLP & Phonetic Matching';
      case AiDirectiveCategory.branchGovernance:
        return isAr ? 'حوكمة واسترداد الفروع' : 'Branch & Retail Chain Governance';
      case AiDirectiveCategory.unitEconomics:
        return isAr ? 'تسعير واقتصاديات الوحدة' : 'Retail Price & Unit Economics';
      case AiDirectiveCategory.fraudSecurity:
        return isAr ? 'كشف الاحتيال وسلامة البونات' : 'Fraud & Thermal POS Detection';
    }
  }

  IconData get icon {
    switch (this) {
      case AiDirectiveCategory.promotionalRules:
        return Icons.auto_awesome_rounded;
      case AiDirectiveCategory.nlpMatching:
        return Icons.spellcheck_rounded;
      case AiDirectiveCategory.branchGovernance:
        return Icons.store_mall_directory_rounded;
      case AiDirectiveCategory.unitEconomics:
        return Icons.calculate_rounded;
      case AiDirectiveCategory.fraudSecurity:
        return Icons.security_rounded;
    }
  }

  Color get color => resolveColor(AppTheme.lightTheme.colorScheme);

  Color resolveColor(ColorScheme colorScheme) {
    switch (this) {
      case AiDirectiveCategory.promotionalRules:
        return colorScheme.primary;
      case AiDirectiveCategory.nlpMatching:
        return colorScheme.secondary;
      case AiDirectiveCategory.branchGovernance:
        return colorScheme.tertiary;
      case AiDirectiveCategory.unitEconomics:
        return colorScheme.onPrimaryFixedVariant;
      case AiDirectiveCategory.fraudSecurity:
        return colorScheme.onSecondaryFixedVariant;
    }
  }

  static AiDirectiveCategory fromKey(String? key) {
    switch (key) {
      case 'promotional_rules':
        return AiDirectiveCategory.promotionalRules;
      case 'nlp_matching':
        return AiDirectiveCategory.nlpMatching;
      case 'branch_governance':
        return AiDirectiveCategory.branchGovernance;
      case 'unit_economics':
        return AiDirectiveCategory.unitEconomics;
      case 'fraud_security':
        return AiDirectiveCategory.fraudSecurity;
      default:
        return AiDirectiveCategory.promotionalRules;
    }
  }
}

/// Represents a single learned AI directive / rule heuristic in the Brain Knowledge Base
class AiDirectiveModel {
  final String id; // e.g. "AIR-01"
  final String code; // e.g. "GREEDY_WATERFALL_DECOMPOSITION"
  final String titleAr;
  final String titleEn;
  final AiDirectiveCategory category;
  final String descriptionAr;
  final String descriptionEn;
  final String logicAr; // تفاصيل عمل المنطق البرمجي
  final String logicEn;
  final String exampleInput; // مثال المدخلات من الفاتورة
  final String exampleOutput; // مثال المخرجات بعد الفحص
  final bool isGloballyActive; // هل مطبق عالمياً على كل الحملات
  final int orderIndex;
  final String primaryModel; // e.g. AiModels.defaultPrimaryLabel
  final List<String> tags;
  final String lastUpdated;

  const AiDirectiveModel({
    required this.id,
    required this.code,
    required this.titleAr,
    required this.titleEn,
    required this.category,
    required this.descriptionAr,
    required this.descriptionEn,
    required this.logicAr,
    required this.logicEn,
    required this.exampleInput,
    required this.exampleOutput,
    this.isGloballyActive = true,
    this.orderIndex = 1,
    this.primaryModel = AiModels.defaultPrimaryLabel,
    this.tags = const [],
    this.lastUpdated = '2026-08-27',
  });

  String getTitle(bool isAr) => isAr ? titleAr : titleEn;
  String getDescription(bool isAr) => isAr ? descriptionAr : descriptionEn;
  String getLogic(bool isAr) => isAr ? logicAr : logicEn;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'code': code,
      'title_ar': titleAr,
      'title_en': titleEn,
      'category': category.key,
      'description_ar': descriptionAr,
      'description_en': descriptionEn,
      'logic_ar': logicAr,
      'logic_en': logicEn,
      'example_input': exampleInput,
      'example_output': exampleOutput,
      'is_globally_active': isGloballyActive,
      'order_index': orderIndex,
      'primary_model': primaryModel,
      'tags': tags,
      'last_updated': lastUpdated,
    };
  }

  factory AiDirectiveModel.fromMap(Map<String, dynamic> map, String docId) {
    return AiDirectiveModel(
      id: map['id'] ?? docId,
      code: map['code'] ?? docId,
      titleAr: map['title_ar'] ?? map['titleAr'] ?? '',
      titleEn: map['title_en'] ?? map['titleEn'] ?? '',
      category: AiDirectiveCategoryExt.fromKey(map['category']),
      descriptionAr: map['description_ar'] ?? map['descriptionAr'] ?? '',
      descriptionEn: map['description_en'] ?? map['descriptionEn'] ?? '',
      logicAr: map['logic_ar'] ?? map['logicAr'] ?? '',
      logicEn: map['logic_en'] ?? map['logicEn'] ?? '',
      exampleInput: map['example_input'] ?? map['exampleInput'] ?? '',
      exampleOutput: map['example_output'] ?? map['exampleOutput'] ?? '',
      isGloballyActive: map['is_globally_active'] ?? map['isGloballyActive'] ?? true,
      orderIndex: (map['order_index'] ?? map['orderIndex'] ?? 0) as int,
      primaryModel: map['primary_model'] ?? map['primaryModel'] ?? AiModels.defaultPrimaryLabel,
      tags: List<String>.from(map['tags'] ?? []),
      lastUpdated: map['last_updated'] ?? map['lastUpdated'] ?? '2026-08-27',
    );
  }

  AiDirectiveModel copyWith({
    String? id,
    String? code,
    String? titleAr,
    String? titleEn,
    AiDirectiveCategory? category,
    String? descriptionAr,
    String? descriptionEn,
    String? logicAr,
    String? logicEn,
    String? exampleInput,
    String? exampleOutput,
    bool? isGloballyActive,
    int? orderIndex,
    String? primaryModel,
    List<String>? tags,
    String? lastUpdated,
  }) {
    return AiDirectiveModel(
      id: id ?? this.id,
      code: code ?? this.code,
      titleAr: titleAr ?? this.titleAr,
      titleEn: titleEn ?? this.titleEn,
      category: category ?? this.category,
      descriptionAr: descriptionAr ?? this.descriptionAr,
      descriptionEn: descriptionEn ?? this.descriptionEn,
      logicAr: logicAr ?? this.logicAr,
      logicEn: logicEn ?? this.logicEn,
      exampleInput: exampleInput ?? this.exampleInput,
      exampleOutput: exampleOutput ?? this.exampleOutput,
      isGloballyActive: isGloballyActive ?? this.isGloballyActive,
      orderIndex: orderIndex ?? this.orderIndex,
      primaryModel: primaryModel ?? this.primaryModel,
      tags: tags ?? this.tags,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}
