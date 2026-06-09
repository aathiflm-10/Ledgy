import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../db/app_database.dart';
import '../../providers/db_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/analytics_service.dart';
import '../../core/formatters.dart';
import '../../main.dart';

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  late DateTime _selectedMonth;
  String _currencySymbol = '₹';

  // Analytics local states
  SummaryData? _summary;
  List<CategoryTotal> _catTotals = [];
  List<DailyTotal> _dailyTotals = [];
  List<String> _insights = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
    
    final uid = ref.read(currentUidProvider);
    final savedCode = globalPrefs.getString('currency_$uid') ?? 'INR';
    setState(() {
      if (savedCode == 'USD') _currencySymbol = '\$';
      else if (savedCode == 'EUR') _currencySymbol = '€';
      else if (savedCode == 'GBP') _currencySymbol = '£';
      else _currencySymbol = '₹';
    });

    _loadAnalyticsData();
  }

  // ── RE-LOAD ANALYTICAL QUERIES ─────────────────────────────────────
  void _loadAnalyticsData() async {
    setState(() => _isLoading = true);
    final db = ref.read(appDatabaseProvider);
    final uid = ref.read(currentUidProvider);
    final service = AnalyticsService(db);

    final start = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final end = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0, 23, 59, 59);

    try {
      final summary = await service.getSummary(uid, start, end);
      final catTotals = await service.getCategoryTotals(uid, start, end);
      final dailyTotals = await service.getDailyTotals(uid, start, end);
      final insights = await service.generateInsights(uid);

      if (mounted) {
        setState(() {
          _summary = summary;
          _catTotals = catTotals;
          _dailyTotals = dailyTotals;
          _insights = insights;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading analytics: $e');
    }
  }

  void _changeMonth(int offset) {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + offset, 1);
    });
    _loadAnalyticsData();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          // ── MONTH PICKER BAR ───────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios, size: 16),
                  onPressed: () => _changeMonth(-1),
                ),
                Text(
                  DateFormat('MMMM yyyy').format(_selectedMonth).toUpperCase(),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_forward_ios, size: 16),
                  onPressed: () => _changeMonth(1),
                ),
              ],
            ),
          ),

          _isLoading
              ? const Expanded(child: Center(child: CircularProgressIndicator()))
              : Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ── SUMMARY CARDS ──────────────────────────────────
                        _buildSummaryMetrics(theme),
                        const SizedBox(height: 24),

                        // ── DYNAMIC PIE CHART (SPEND BREAKDOWN) ───────────
                        Text('Category Breakdown', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 16),
                        _buildPieChart(theme),
                        const SizedBox(height: 24),

                        // ── DYNAMIC LINE CHART (DAILY TRENDS) ─────────────
                        Text('Daily Spending', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 16),
                        _buildLineChart(theme),
                        const SizedBox(height: 24),

                        // ── SMART AI INSIGHTS ──────────────────────────────
                        Text('Smart Insights', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 12),
                        _buildInsightsPanel(theme),
                        const SizedBox(height: 48),
                      ],
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  // ── METRIC BLOCK BUILDER ───────────────────────────────────────────
  Widget _buildSummaryMetrics(ThemeData theme) {
    final s = _summary!;
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.primaryColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('INFLOW', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 4),
                Text(
                  Formatters.formatCurrency(s.totalIncome, symbol: _currencySymbol),
                  style: theme.textTheme.titleSmall?.copyWith(color: theme.primaryColor),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.error.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('OUTFLOW', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 4),
                Text(
                  Formatters.formatCurrency(s.totalExpense, symbol: _currencySymbol),
                  style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.error),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ],
    ).animate().fadeIn(duration: 350.ms);
  }

  // ── PIE CHART RENDER ───────────────────────────────────────────────
  Widget _buildPieChart(ThemeData theme) {
    if (_catTotals.isEmpty) {
      return Container(
        height: 160,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.dividerColor),
        ),
        child: const Center(child: Text('No expenses recorded for this month.', style: TextStyle(color: Colors.grey))),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Row(
          children: [
            SizedBox(
              width: 120,
              height: 120,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 30,
                  sections: _catTotals.map((cat) {
                    final color = Color(int.parse(cat.colorHex.replaceAll('#', '0xFF')));
                    return PieChartSectionData(
                      color: color,
                      value: cat.total,
                      title: cat.percentage > 10 ? '${cat.percentage.toStringAsFixed(0)}%' : '',
                      radius: 30,
                      titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _catTotals.length.clamp(0, 4),
                itemBuilder: (context, idx) {
                  final cat = _catTotals[idx];
                  final color = Color(int.parse(cat.colorHex.replaceAll('#', '0xFF')));
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6.0),
                    child: Row(
                      children: [
                        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${cat.emoji} ${cat.name}',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          Formatters.formatCurrency(cat.total, symbol: _currencySymbol),
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── LINE CHART RENDER ──────────────────────────────────────────────
  Widget _buildLineChart(ThemeData theme) {
    if (_dailyTotals.length < 2) {
      return Container(
        height: 180,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.dividerColor),
        ),
        child: const Center(child: Text('Insufficient logs to chart trends.', style: TextStyle(color: Colors.grey))),
      );
    }

    final double maxVal = _dailyTotals.map((e) => e.total).reduce((a, b) => a > b ? a : b) * 1.15;

    return Container(
      height: 180,
      padding: const EdgeInsets.fromLTRB(10, 16, 20, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: LineChart(
        LineChartData(
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          minX: 0,
          maxX: _dailyTotals.length.toDouble() - 1,
          minY: 0,
          maxY: maxVal,
          lineBarsData: [
            LineChartBarData(
              spots: List.generate(_dailyTotals.length, (idx) {
                return FlSpot(idx.toDouble(), _dailyTotals[idx].total);
              }),
              isCurved: true,
              color: theme.primaryColor,
              barWidth: 3.5,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: theme.primaryColor.withOpacity(0.08),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── INSIGHTS RENDER ────────────────────────────────────────────────
  Widget _buildInsightsPanel(ThemeData theme) {
    return Column(
      children: _insights.map((insight) {
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.dividerColor),
          ),
          child: Row(
            children: [
              Icon(Icons.tips_and_updates_outlined, color: theme.primaryColor, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  insight,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    ).animate().fadeIn(delay: 200.ms, duration: 400.ms);
  }
}
