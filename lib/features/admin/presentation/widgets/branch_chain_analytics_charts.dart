import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/constants/country_currency_config.dart';
import '../../../../core/widgets/m3_progress_indicators.dart';
import '../../../../core/widgets/m3_list_tile.dart';

/// Data Model for Branch / Chain Analytics Visualization Item
class BranchChartItem {
  final String name;
  final double totalRevenue;
  final int receiptCount;
  final double percentageOfTotal;
  final bool isChain;
  final Color color;

  const BranchChartItem({
    required this.name,
    required this.totalRevenue,
    required this.receiptCount,
    required this.percentageOfTotal,
    this.isChain = false,
    required this.color,
  });

  double get avgTicket => receiptCount > 0 ? (totalRevenue / receiptCount) : 0.0;
}

/// Palette generator for M3 harmonized chart sections
class M3ChartPalette {
  static List<Color> get colors =>
      AppTheme.getDynamicPalette(AppTheme.lightTheme.colorScheme);

  static Color getColor(int index, [ColorScheme? colorScheme]) {
    final cs = colorScheme ?? AppTheme.lightTheme.colorScheme;
    final dynamicPalette = [
      cs.primary,
      cs.tertiary,
      cs.secondary,
      cs.onPrimaryContainer,
      cs.onTertiaryContainer,
      cs.onSecondaryContainer,
      cs.inversePrimary,
      cs.outline,
    ];
    return dynamicPalette[index % dynamicPalette.length];
  }
}

// ---------------------------------------------------------------------------
// 1. Interactive Animated Donut Chart (مخطط دائري تفاعلي متحرك)
// ---------------------------------------------------------------------------
class BranchChainDonutChart extends StatefulWidget {
  final List<BranchChartItem> items;
  final double totalSales;
  final int totalReceipts;
  final String metricDimension; // 'REVENUE' or 'COUNT'
  final CountryCurrency activeCountry;
  final bool isAr;
  final bool isHi;
  final ValueChanged<int?>? onItemSelected;

  const BranchChainDonutChart({
    super.key,
    required this.items,
    required this.totalSales,
    required this.totalReceipts,
    this.metricDimension = 'REVENUE',
    required this.activeCountry,
    required this.isAr,
    required this.isHi,
    this.onItemSelected,
  });

  @override
  State<BranchChainDonutChart> createState() => _BranchChainDonutChartState();
}

class _BranchChainDonutChartState extends State<BranchChainDonutChart> {
  int _touchedIndex = -1;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (widget.items.isEmpty) {
      return Center(
        child: Text(
          widget.isAr ? 'لا توجد بيانات متاحة للرسم البياني' : 'No data available for chart',
          style: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant),
        ),
      );
    }

    final isRevenue = widget.metricDimension == 'REVENUE';
    final double metricTotal = isRevenue ? widget.totalSales : widget.totalReceipts.toDouble();

    // Top 8 items + Others if more than 8
    final List<BranchChartItem> displayItems = [];
    if (widget.items.length <= 8) {
      displayItems.addAll(widget.items);
    } else {
      displayItems.addAll(widget.items.take(7));
      double othersRevenue = 0.0;
      int othersCount = 0;
      for (int i = 7; i < widget.items.length; i++) {
        othersRevenue += widget.items[i].totalRevenue;
        othersCount += widget.items[i].receiptCount;
      }
      final double othersPct = metricTotal > 0
          ? ((isRevenue ? othersRevenue : othersCount.toDouble()) / metricTotal) * 100
          : 0.0;
      displayItems.add(
        BranchChartItem(
          name: widget.isAr ? 'فروع أخرى مجمعة' : (widget.isHi ? 'अन्य शाखाएं' : 'Other Branches'),
          totalRevenue: othersRevenue,
          receiptCount: othersCount,
          percentageOfTotal: othersPct,
          color: colorScheme.outline,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 680;

        return Column(
          children: [
            // Donut Chart Graphic with Center Summary
            SizedBox(
              height: isCompact ? 280 : 320,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      pieTouchData: PieTouchData(
                        touchCallback: (FlTouchEvent event, pieTouchResponse) {
                          setState(() {
                            if (!event.isInterestedForInteractions ||
                                pieTouchResponse == null ||
                                pieTouchResponse.touchedSection == null) {
                              _touchedIndex = -1;
                              return;
                            }
                            _touchedIndex = pieTouchResponse.touchedSection!.touchedSectionIndex;
                          });
                          if (widget.onItemSelected != null) {
                            widget.onItemSelected!(_touchedIndex >= 0 && _touchedIndex < displayItems.length ? _touchedIndex : null);
                          }
                        },
                      ),
                      borderData: FlBorderData(show: false),
                      sectionsSpace: 3,
                      centerSpaceRadius: isCompact ? 60 : 78,
                      sections: List.generate(displayItems.length, (i) {
                        final item = displayItems[i];
                        final isTouched = i == _touchedIndex;
                        final double radius = isTouched ? (isCompact ? 36 : 46) : (isCompact ? 28 : 36);
                        final double val = isRevenue ? item.totalRevenue : item.receiptCount.toDouble();

                        return PieChartSectionData(
                          color: item.color,
                          value: val > 0 ? val : 0.001,
                          title: isTouched ? '${item.percentageOfTotal.toStringAsFixed(1)}%' : '',
                          radius: radius,
                          titleStyle: GoogleFonts.cairo(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          badgeWidget: isTouched
                              ? Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: colorScheme.surface,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.2),
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                  child: Icon(Icons.touch_app_rounded, size: 12, color: item.color),
                                )
                              : null,
                          badgePositionPercentageOffset: .98,
                        );
                      }),
                    ),
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutCubic,
                  ),

                  // Center Information Card
                  _buildCenterBadge(
                    context: context,
                    colorScheme: colorScheme,
                    touchedItem: (_touchedIndex >= 0 && _touchedIndex < displayItems.length)
                        ? displayItems[_touchedIndex]
                        : null,
                    isRevenue: isRevenue,
                    metricTotal: metricTotal,
                    isCompact: isCompact,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Interactive Responsive Legend Flow
            _buildInteractiveLegend(
              displayItems: displayItems,
              colorScheme: colorScheme,
              isRevenue: isRevenue,
            ),
          ],
        );
      },
    );
  }

  Widget _buildCenterBadge({
    required BuildContext context,
    required ColorScheme colorScheme,
    required BranchChartItem? touchedItem,
    required bool isRevenue,
    required double metricTotal,
    required bool isCompact,
  }) {
    if (touchedItem != null) {
      return Container(
        width: isCompact ? 110 : 140,
        height: isCompact ? 110 : 140,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: touchedItem.color.withValues(alpha: 0.25),
              blurRadius: 12,
              spreadRadius: 2,
            ),
          ],
          border: Border.all(color: touchedItem.color, width: 2),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              touchedItem.name,
              style: GoogleFonts.cairo(
                fontSize: isCompact ? 10 : 11.5,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
                height: 1.1,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              isRevenue
                  ? '${touchedItem.totalRevenue.toStringAsFixed(0)} ${widget.activeCountry.currencySymbol}'
                  : '${touchedItem.receiptCount} ${widget.isAr ? "فاتورة" : "rcpts"}',
              style: GoogleFonts.cairo(
                fontSize: isCompact ? 11 : 13,
                fontWeight: FontWeight.w900,
                color: touchedItem.color,
                height: 1.1,
              ),
              textAlign: TextAlign.center,
            ),
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: touchedItem.color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${touchedItem.percentageOfTotal.toStringAsFixed(1)}%',
                style: GoogleFonts.cairo(
                  fontSize: isCompact ? 9 : 10.5,
                  fontWeight: FontWeight.bold,
                  color: touchedItem.color,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Default Total View
    return Container(
      width: isCompact ? 110 : 140,
      height: isCompact ? 110 : 140,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        shape: BoxShape.circle,
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isRevenue ? Icons.payments_rounded : Icons.receipt_long_rounded,
            size: isCompact ? 16 : 20,
            color: colorScheme.primary,
          ),
          const SizedBox(height: 2),
          Text(
            isRevenue ? (widget.isAr ? 'إجمالي المبيعات' : 'Total Sales') : (widget.isAr ? 'إجمالي الفواتير' : 'Total Receipts'),
            style: GoogleFonts.cairo(
              fontSize: isCompact ? 9.5 : 10.5,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          Text(
            isRevenue
                ? '${metricTotal.toStringAsFixed(0)} ${widget.activeCountry.currencySymbol}'
                : '${metricTotal.toInt()}',
            style: GoogleFonts.cairo(
              fontSize: isCompact ? 12 : 14,
              fontWeight: FontWeight.w900,
              color: colorScheme.primary,
              letterSpacing: -0.3,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildInteractiveLegend({
    required List<BranchChartItem> displayItems,
    required ColorScheme colorScheme,
    required bool isRevenue,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: List.generate(displayItems.length, (i) {
        final item = displayItems[i];
        final isSelected = i == _touchedIndex;

        return InkWell(
          onTap: () {
            setState(() {
              _touchedIndex = (_touchedIndex == i) ? -1 : i;
            });
          },
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected
                  ? item.color.withValues(alpha: 0.15)
                  : colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? item.color : colorScheme.outlineVariant.withValues(alpha: 0.5),
                width: isSelected ? 1.5 : 1.0,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: item.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Text(
                    item.name,
                    style: GoogleFonts.cairo(
                      fontSize: 11.5,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${item.percentageOfTotal.toStringAsFixed(1)}%',
                  style: GoogleFonts.cairo(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: item.color,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// 2. Interactive Animated Column / Bar Chart (مخطط بياني للمقارنة)
// ---------------------------------------------------------------------------
class BranchChainBarChart extends StatefulWidget {
  final List<BranchChartItem> items;
  final String metricDimension; // 'REVENUE' or 'COUNT'
  final CountryCurrency activeCountry;
  final bool isAr;
  final bool isHi;

  const BranchChainBarChart({
    super.key,
    required this.items,
    this.metricDimension = 'REVENUE',
    required this.activeCountry,
    required this.isAr,
    required this.isHi,
  });

  /// Cleans branch names for presentation:
  /// - Strips parenthetical governorates e.g. (الإسكندرية), (الغربية), (البحيرة), (القاهرة)
  /// - Strips chain prefixes e.g. "أسواق فتح الله - "
  /// - Ensures "فرع " prefix is present in Arabic for branches (e.g. "فرع المحلة الكبرى")
  static String cleanBranchDisplayName(
    String rawName, {
    bool isChain = false,
    bool isAr = true,
  }) {
    var name = rawName.trim();
    if (name.isEmpty) return isAr ? 'فرع غير محدد' : 'Unspecified Branch';

    if (isChain) {
      name = name.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim();
      return name;
    }

    // 1. Remove parenthetical governorates, cities, or metadata like (الإسكندرية), (الغربية), (البحيرة), (القاهرة), (الجيزة), (دمياط), etc.
    name = name.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim();

    // 2. Strip leading parent chain / supermarket brand prefixes like "أسواق فتح الله - ", "فتح الله - ", "كارفور - ", etc.
    name = name.replaceFirst(
      RegExp(
        r'^(?:أسواق\s+)?(?:فتح\s+الله|كارفور|جملة\s+ماركت|بيت\s+الجملة|خير\s+زمان|سبينس|أولاد\s+رجب|مترو|لولو|بيم|باندا|الراية|كازيون|المحمل)\s*[-–:]\s*',
        caseSensitive: false,
      ),
      '',
    ).trim();

    // 3. Clean any leading/trailing hyphens, colons, or noise
    name = name.replaceAll(RegExp(r'^[-–:\s]+|[-–:\s]+$'), '').trim();

    // 4. Ensure it reads "فرع ..." in Arabic if it's a branch and doesn't already have "فرع"
    // As requested by user: "يكتبلي فرع المحلة الكبرى ممكن"
    if (isAr) {
      if (!name.startsWith('فرع ') && !name.startsWith('الفرع ')) {
        name = 'فرع $name';
      }
    }

    return name;
  }

  @override
  State<BranchChainBarChart> createState() => _BranchChainBarChartState();
}

class _BranchChainBarChartState extends State<BranchChainBarChart> {
  int _touchedGroupIndex = -1;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (widget.items.isEmpty) {
      return Center(
        child: Text(
          widget.isAr ? 'لا توجد بيانات للمقارنة' : 'No data for comparison',
          style: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant),
        ),
      );
    }

    final isRevenue = widget.metricDimension == 'REVENUE';
    // Show top 10 items for clean readability
    final displayItems = widget.items.take(10).toList();

    double maxValue = 0.0;
    for (final it in displayItems) {
      final v = isRevenue ? it.totalRevenue : it.receiptCount.toDouble();
      if (v > maxValue) maxValue = v;
    }
    if (maxValue <= 0) maxValue = 100.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 650;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: isCompact ? 330 : 380,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxValue * 1.30,
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (group) => colorScheme.inverseSurface,
                      tooltipRoundedRadius: 12,
                      tooltipPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final item = displayItems[group.x.toInt()];
                        final displayName = BranchChainBarChart.cleanBranchDisplayName(
                          item.name,
                          isChain: item.isChain,
                          isAr: widget.isAr,
                        );
                        final valStr = isRevenue
                            ? '${NumberFormat('#,##0.#').format(item.totalRevenue)} ${widget.activeCountry.currencySymbol}'
                            : '${item.receiptCount} ${widget.isAr ? "فاتورة" : "receipts"}';

                        return BarTooltipItem(
                          '$displayName\n',
                          GoogleFonts.cairo(
                            color: colorScheme.onInverseSurface,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                          children: [
                            TextSpan(
                              text: '$valStr (${item.percentageOfTotal.toStringAsFixed(1)}%)',
                              style: GoogleFonts.cairo(
                                color: colorScheme.primaryContainer,
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    touchCallback: (FlTouchEvent event, barTouchResponse) {
                      setState(() {
                        if (!event.isInterestedForInteractions ||
                            barTouchResponse == null ||
                            barTouchResponse.spot == null) {
                          _touchedGroupIndex = -1;
                          return;
                        }
                        _touchedGroupIndex = barTouchResponse.spot!.touchedBarGroupIndex;
                      });
                    },
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    // 1. Direct at-a-glance values visible without hovering
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: isCompact ? 36 : 42,
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx < 0 || idx >= displayItems.length) return const SizedBox.shrink();
                          final item = displayItems[idx];
                          final isTouched = idx == _touchedGroupIndex;
                          final val = isRevenue ? item.totalRevenue : item.receiptCount.toDouble();

                          // Format primary value clearly
                          String primaryVal;
                          if (isRevenue) {
                            if (val >= 100000) {
                              primaryVal = '${(val / 1000).toStringAsFixed(1)}k';
                            } else if (val >= 1000) {
                              primaryVal = isCompact
                                  ? '${(val / 1000).toStringAsFixed(1)}k'
                                  : '${NumberFormat('#,##0').format(val.round())} ${widget.activeCountry.currencySymbol}';
                            } else {
                              primaryVal = '${val.toStringAsFixed(0)} ${isCompact ? "" : widget.activeCountry.currencySymbol}';
                            }
                          } else {
                            primaryVal = '${item.receiptCount}${isCompact ? "" : (widget.isAr ? " فاتورة" : " rec")}';
                          }

                          final pctText = '${item.percentageOfTotal.toStringAsFixed(1)}%';

                          return FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: isCompact ? 6 : 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: isTouched
                                      ? colorScheme.primaryContainer
                                      : item.color.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isTouched
                                        ? colorScheme.primary
                                        : item.color.withValues(alpha: 0.45),
                                    width: isTouched ? 1.5 : 1.0,
                                  ),
                                  boxShadow: isTouched
                                      ? [
                                          BoxShadow(
                                            color: colorScheme.primary.withValues(alpha: 0.25),
                                            blurRadius: 6,
                                            offset: const Offset(0, 2),
                                          ),
                                        ]
                                      : [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.03),
                                            blurRadius: 3,
                                            offset: const Offset(0, 1),
                                          ),
                                        ],
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      primaryVal,
                                      style: GoogleFonts.cairo(
                                        fontSize: isCompact ? 10 : 11,
                                        fontWeight: FontWeight.bold,
                                        color: isTouched ? colorScheme.onPrimaryContainer : item.color,
                                        height: 1.1,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    Text(
                                      pctText,
                                      style: GoogleFonts.cairo(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w600,
                                        color: isTouched
                                            ? colorScheme.primary
                                            : colorScheme.onSurfaceVariant.withValues(alpha: 0.85),
                                        height: 1.0,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: isCompact ? 36 : 46,
                        getTitlesWidget: (value, meta) {
                          if (value == 0) return const SizedBox.shrink();
                          String label;
                          if (value >= 1000) {
                            label = '${(value / 1000).toStringAsFixed(0)}k';
                          } else {
                            label = value.toInt().toString();
                          }
                          return Text(
                            label,
                            style: GoogleFonts.cairo(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 10,
                            ),
                          );
                        },
                      ),
                    ),
                    // 2. Clean Branch Names without governorates and without artificial truncation
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: isCompact ? 50 : 64,
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx < 0 || idx >= displayItems.length) return const SizedBox.shrink();
                          final item = displayItems[idx];
                          
                          final displayName = BranchChainBarChart.cleanBranchDisplayName(
                            item.name,
                            isChain: item.isChain,
                            isAr: widget.isAr,
                          );

                          final isTouched = idx == _touchedGroupIndex;

                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: SizedBox(
                              width: isCompact ? 60 : 96,
                              child: Text(
                                displayName,
                                style: GoogleFonts.cairo(
                                  fontSize: isCompact ? 9.5 : 11,
                                  fontWeight: isTouched ? FontWeight.bold : FontWeight.w600,
                                  color: isTouched ? colorScheme.primary : colorScheme.onSurface,
                                  height: 1.2,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                      strokeWidth: 1,
                      dashArray: [4, 4],
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: List.generate(displayItems.length, (i) {
                    final item = displayItems[i];
                    final isTouched = i == _touchedGroupIndex;
                    final val = isRevenue ? item.totalRevenue : item.receiptCount.toDouble();

                    return BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: val,
                          gradient: LinearGradient(
                             colors: isTouched
                                 ? [colorScheme.primary, colorScheme.tertiary]
                                 : [item.color, item.color.withValues(alpha: 0.75)],
                             begin: Alignment.bottomCenter,
                             end: Alignment.topCenter,
                          ),
                          width: isCompact ? 14 : 24,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                          backDrawRodData: BackgroundBarChartRodData(
                            show: true,
                            toY: maxValue * 1.15,
                            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                          ),
                        ),
                      ],
                    );
                  }),
                ),
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutCubic,
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// 3. M3 Leaderboard & Performance List (بطاقات وترتيب الأداء)
// ---------------------------------------------------------------------------
class BranchChainLeaderboardList extends StatelessWidget {
  final List<BranchChartItem> items;
  final double maxRevenue;
  final CountryCurrency activeCountry;
  final ColorScheme colorScheme;
  final bool isAr;
  final bool isHi;
  final bool isMobile;

  const BranchChainLeaderboardList({
    super.key,
    required this.items,
    required this.maxRevenue,
    required this.activeCountry,
    required this.colorScheme,
    required this.isAr,
    this.isHi = false,
    required this.isMobile,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Text(
          isAr ? 'لا توجد بيانات متاحة' : (isHi ? 'कोई डेटा उपलब्ध नहीं है' : 'No items recorded'),
          style: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (context, index) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: M3InsetDivider(indent: 52),
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        final rank = index + 1;
        final progress = maxRevenue > 0 ? (item.totalRevenue / maxRevenue).clamp(0.0, 1.0) : 0.0;

        return Container(
          padding: EdgeInsets.all(isMobile ? 12 : 16),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: rank <= 3
                  ? item.color.withValues(alpha: 0.4)
                  : colorScheme.outlineVariant.withValues(alpha: 0.4),
              width: rank <= 3 ? 1.5 : 1.0,
            ),
            boxShadow: rank <= 3
                ? [
                    BoxShadow(
                      color: item.color.withValues(alpha: 0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Rank Medal / Badge
                  _buildRankBadge(rank: rank, color: item.color, colorScheme: colorScheme),
                  const SizedBox(width: 10),

                  // Branch / Chain Name
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          style: GoogleFonts.cairo(
                            fontWeight: FontWeight.bold,
                            fontSize: isMobile ? 12.5 : 14,
                            color: colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Row(
                          children: [
                            Icon(
                              item.isChain ? Icons.corporate_fare_rounded : Icons.storefront_rounded,
                              size: 13,
                              color: item.color,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              item.isChain
                                  ? (isAr ? 'سلسلة تجارية' : (isHi ? 'रिटेल चेन' : 'Retail Chain'))
                                  : (isAr ? 'فرع / منفذ بيع' : (isHi ? 'शाखा आउटलेट' : 'Store Outlet')),
                              style: GoogleFonts.cairo(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '• ${isAr ? "متوسط الفاتورة: " : (isHi ? "• औसत रसीद: " : "• Avg: ")}${item.avgTicket.toStringAsFixed(1)} ${activeCountry.currencySymbol}',
                              style: GoogleFonts.cairo(
                                fontSize: 10.5,
                                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Total Revenue Amount
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${item.totalRevenue.toStringAsFixed(1)} ${activeCountry.currencySymbol}',
                        style: GoogleFonts.cairo(
                          fontWeight: FontWeight.w900,
                          fontSize: isMobile ? 13 : 15,
                          color: colorScheme.primary,
                        ),
                      ),
                      Text(
                        '${item.receiptCount} ${isAr ? "فاتورة" : (isHi ? "रसीदें" : "receipts")}',
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Share progress row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isAr ? 'الحصة من المبيعات' : (isHi ? 'बिक्री शेयर' : 'Sales Share'),
                    style: GoogleFonts.cairo(fontSize: 11, color: colorScheme.onSurfaceVariant),
                  ),
                  Text(
                    '${item.percentageOfTotal.toStringAsFixed(1)}%',
                    style: GoogleFonts.cairo(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: item.color,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              M3LinearProgress(
                value: progress,
                height: 7,
                color: item.color,
                backgroundColor: colorScheme.surfaceContainerHighest,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRankBadge({
    required int rank,
    required Color color,
    required ColorScheme colorScheme,
  }) {
    if (rank == 1) {
      return Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colorScheme.primaryFixedDim),
        ),
        child: const Center(
          child: Text('🥇', style: TextStyle(fontSize: 16)),
        ),
      );
    } else if (rank == 2) {
      return Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colorScheme.primaryFixedDim),
        ),
        child: const Center(
          child: Text('🥈', style: TextStyle(fontSize: 16)),
        ),
      );
    } else if (rank == 3) {
      return Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colorScheme.secondaryFixedDim),
        ),
        child: const Center(
          child: Text('🥉', style: TextStyle(fontSize: 16)),
        ),
      );
    }

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: Text(
          '#$rank',
          style: GoogleFonts.cairo(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            color: color,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 4. Branch & Chain Summary KPI Bar (شريط المؤشرات السريعة للفروع)
// ---------------------------------------------------------------------------
class BranchPerformanceKpiRow extends StatelessWidget {
  final int activeEntitiesCount;
  final String topEntityName;
  final double topEntityRevenue;
  final double avgRevenuePerEntity;
  final CountryCurrency activeCountry;
  final ColorScheme colorScheme;
  final bool isChainMode;
  final bool isAr;
  final bool isHi;
  final bool isMobile;

  const BranchPerformanceKpiRow({
    super.key,
    required this.activeEntitiesCount,
    required this.topEntityName,
    required this.topEntityRevenue,
    required this.avgRevenuePerEntity,
    required this.activeCountry,
    required this.colorScheme,
    required this.isChainMode,
    required this.isAr,
    this.isHi = false,
    required this.isMobile,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 650;

        if (isCompact) {
          return Column(
            children: [
              _buildMiniKpi(
                icon: isChainMode ? Icons.corporate_fare_rounded : Icons.store_rounded,
                title: isChainMode
                    ? (isAr ? 'إجمالي السلاسل' : (isHi ? 'कुल रिटेल चेन' : 'Total Chains'))
                    : (isAr ? 'المنافذ النشطة' : (isHi ? 'सक्रिय आउटलेट' : 'Active Outlets')),
                value: '$activeEntitiesCount',
                color: colorScheme.primary,
              ),
              const SizedBox(height: 8),
              _buildMiniKpi(
                icon: Icons.emoji_events_rounded,
                title: isChainMode
                    ? (isAr ? 'السلسلة الأعلى مبيعاً' : (isHi ? 'शीर्ष रिटेल चेन' : 'Top Chain'))
                    : (isAr ? 'الفرع الأعلى مبيعاً' : (isHi ? 'शीर्ष आउटलेट' : 'Top Outlet')),
                value: BranchChainBarChart.cleanBranchDisplayName(topEntityName, isChain: isChainMode, isAr: isAr),
                subtitle: '${NumberFormat('#,##0.#').format(topEntityRevenue)} ${activeCountry.currencySymbol}',
                color: colorScheme.onSecondaryFixedVariant,
              ),
              const SizedBox(height: 8),
              _buildMiniKpi(
                icon: Icons.query_stats_rounded,
                title: isAr ? 'متوسط مبيعات المنفذ' : (isHi ? 'औसत आउटलेट बिक्री' : 'Avg Outlet Sales'),
                value: '${NumberFormat('#,##0.#').format(avgRevenuePerEntity)} ${activeCountry.currencySymbol}',
                color: colorScheme.tertiary,
              ),
            ],
          );
        }

        return Row(
          children: [
            Expanded(
              child: _buildMiniKpi(
                icon: isChainMode ? Icons.corporate_fare_rounded : Icons.store_rounded,
                title: isChainMode
                    ? (isAr ? 'إجمالي السلاسل' : (isHi ? 'कुल रिटेल चेन' : 'Total Chains'))
                    : (isAr ? 'المنافذ النشطة' : (isHi ? 'सक्रिय आउटलेट' : 'Active Outlets')),
                value: '$activeEntitiesCount',
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: _buildMiniKpi(
                icon: Icons.emoji_events_rounded,
                title: isChainMode
                    ? (isAr ? 'السلسلة الأعلى مبيعاً' : (isHi ? 'शीर्ष रिटेल चेन' : 'Top Chain'))
                    : (isAr ? 'الفرع الأعلى مبيعاً' : (isHi ? 'शीर्ष आउटलेट' : 'Top Outlet')),
                value: BranchChainBarChart.cleanBranchDisplayName(topEntityName, isChain: isChainMode, isAr: isAr),
                subtitle: '${NumberFormat('#,##0.#').format(topEntityRevenue)} ${activeCountry.currencySymbol}',
                color: colorScheme.onSecondaryFixedVariant,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: _buildMiniKpi(
                icon: Icons.query_stats_rounded,
                title: isAr ? 'متوسط مبيعات المنفذ' : (isHi ? 'औसत आउटलेट बिक्री' : 'Avg Outlet Sales'),
                value: '${NumberFormat('#,##0.#').format(avgRevenuePerEntity)} ${activeCountry.currencySymbol}',
                color: colorScheme.tertiary,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMiniKpi({
    required IconData icon,
    required String title,
    required String value,
    String? subtitle,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: GoogleFonts.cairo(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  value,
                  style: GoogleFonts.cairo(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: GoogleFonts.cairo(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
