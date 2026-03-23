import 'dart:io';
import 'package:flutter/material.dart';
import 'package:call_log/call_log.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:intl/intl.dart';

import 'package:fl_chart/fl_chart.dart';
import '../../services/call_log_service.dart';

class AnalyticsTab extends StatefulWidget {
  const AnalyticsTab({super.key});

  @override
  State<AnalyticsTab> createState() => _AnalyticsTabState();
}

class _AnalyticsTabState extends State<AnalyticsTab> {
  // Profile
  String _deviceModel  = 'Loading...';

  // Period
  int         _selectedFilter = 0; // 0=Today, 1=Yesterday, 2=Last Week, 3=Custom
  DateTime?   _customFrom;
  DateTime?   _customTo;

  // Drilldown sub-tab: 0 = Summary, 1 = Call History
  int _drilldownTab = 0;

  // Chart type: 0 = Pie, 1 = Bar, 2 = Line
  int _chartType = 0;

  // Data
  List<CallLogEntry> _allCallLogs = [];
  bool _isLoading = true;

  // ── Touch state for PieChart
  int _pieTouchedIndex = -1;

  @override
  void initState() {
    super.initState();
    _loadProfileAndDevice();
    _fetchCallLogs();
  }

  // ── Loaders ──────────────────────────────────────────────

  Future<void> _loadProfileAndDevice() async {
    // Basic profile handled by shared header in DashboardScreen
    try {
      final di = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await di.androidInfo;
        if (mounted) setState(() => _deviceModel = '${info.manufacturer} ${info.model}');
      } else if (Platform.isIOS) {
        final info = await di.iosInfo;
        if (mounted) setState(() => _deviceModel = info.utsname.machine);
      }
    } catch (_) {
      if (mounted) setState(() => _deviceModel = 'Unknown Device');
    }
  }

  Future<void> _fetchCallLogs() async {
    setState(() => _isLoading = true);
    try {
      final now  = DateTime.now();
      final from = now.subtract(const Duration(days: 30)).millisecondsSinceEpoch;
      final entries = await CallLogService.fetchLogsForPeriod(from, now.millisecondsSinceEpoch);
      if (mounted) setState(() { _allCallLogs = entries; _isLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Helpers ──────────────────────────────────────────────

  CallType? _effectiveType(CallLogEntry e) =>
      (e.callType == CallType.incoming && (e.duration ?? 0) == 0) ? CallType.rejected : e.callType;

  String _fmtDur(int? s) {
    final v = s ?? 0;
    if (v == 0) return '—';
    final h = v ~/ 3600, m = (v % 3600) ~/ 60, sec = v % 60;
    if (h > 0) return '${h}h ${m}m ${sec}s';
    if (m > 0) return '${m}m ${sec}s';
    return '${sec}s';
  }

  String _fmtTime(int? ts) => ts == null ? '' : DateFormat('hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(ts));
  String _fmtDate(int? ts) => ts == null ? '—' : DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(ts));

  // ── Period filtering ──────────────────────────────────────

  List<CallLogEntry> get _filteredLogs {
    final now = DateTime.now();
    DateTime start, end = now;
    switch (_selectedFilter) {
      case 0: start = DateTime(now.year, now.month, now.day); break;
      case 1:
        start = DateTime(now.year, now.month, now.day - 1);
        end   = DateTime(now.year, now.month, now.day - 1, 23, 59, 59);
        break;
      case 2: start = now.subtract(const Duration(days: 7)); break;
      case 3:
        if (_customFrom == null) return [];
        start = DateTime(_customFrom!.year, _customFrom!.month, _customFrom!.day);
        if (_customTo != null) end = DateTime(_customTo!.year, _customTo!.month, _customTo!.day, 23, 59, 59);
        break;
      default: start = DateTime(now.year, now.month, now.day);
    }
    final s = start.millisecondsSinceEpoch, e2 = end.millisecondsSinceEpoch;
    return _allCallLogs.where((e) { final ts = e.timestamp ?? 0; return ts >= s && ts <= e2; }).toList();
  }

  Map<String, int> get _stats {
    int total = 0, totalDur = 0, incoming = 0, inDur = 0, outgoing = 0, outDur = 0, missed = 0, rejected = 0, connected = 0;
    for (final e in _filteredLogs) {
      total++;
      final d = e.duration ?? 0;
      totalDur += d;
      if (d > 0) connected++;
      switch (_effectiveType(e)) {
        case CallType.incoming:  incoming++;  inDur  += d; break;
        case CallType.outgoing:  outgoing++;  outDur += d; break;
        case CallType.missed:    missed++;    break;
        case CallType.rejected:  rejected++;  break;
        default: break;
      }
    }
    return {
      'total': total, 'totalDur': totalDur, 'incoming': incoming, 'inDur': inDur,
      'outgoing': outgoing, 'outDur': outDur, 'missed': missed, 'rejected': rejected, 'connected': connected,
    };
  }

  // ── Date range picker ─────────────────────────────────────

  Future<void> _pickCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: ThemeData.light().copyWith(
          colorScheme: const ColorScheme.light(primary: Color(0xFF3D7DFE), onPrimary: Colors.white),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() { _selectedFilter = 3; _customFrom = picked.start; _customTo = picked.end; });
    } else if (_customFrom == null) {
      setState(() => _selectedFilter = 0);
    }
  }

  // ═══════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    const primaryBlue = Color(0xFF3D7DFE);
    return Column(
      children: [
        // Fixed Top Section: Period Filters
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPeriodRow(),
              if (_selectedFilter == 3 && _customFrom != null) ...[
                const SizedBox(height: 12),
                _buildCustomBadge()
              ],
            ],
          ),
        ),

        // Scrollable Content
        Expanded(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: primaryBlue),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
                  children: [
                    _buildDrilldownTabBar(),
                    const SizedBox(height: 16),
                    if (_drilldownTab == 0)
                      _buildSummaryView()
                    else
                      _buildCallsView(),
                    const SizedBox(height: 32),
                    if (_filteredLogs.isNotEmpty) _buildAnalyticsSection(),
                  ],
                ),
        ),
      ],
    );
  }

  // ── Period row ───────────────────────────────────────────

  Widget _buildPeriodRow() {
    final List<Map<String, dynamic>> items = [
      {'label': 'Today', 'icon': Icons.today_rounded},
      {'label': 'Yesterday', 'icon': Icons.history_rounded},
      {'label': 'Week', 'icon': Icons.date_range_rounded},
      {'label': 'Custom', 'icon': Icons.tune_rounded},
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(items.length, (i) {
          final isSelected = _selectedFilter == i;
          final item = items[i];
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: GestureDetector(
              onTap: () => i == 3 
                ? _pickCustomRange() 
                : setState(() { _selectedFilter = i; _customFrom = null; _customTo = null; }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                padding: EdgeInsets.symmetric(
                  horizontal: isSelected ? 16 : 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.black : const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          )
                        ]
                      : [],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      item['icon'],
                      size: 19,
                      color: isSelected ? Colors.white : Colors.black54,
                    ),
                    ClipRect(
                      child: AnimatedSize(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        child: !isSelected
                            ? const SizedBox.shrink()
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(width: 8),
                                  AnimatedOpacity(
                                    duration: const Duration(milliseconds: 200),
                                    opacity: isSelected ? 1.0 : 0.0,
                                    child: Text(
                                      item['label'],
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        fontFamily: 'Inter',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildCustomBadge() {
    final from = DateFormat('MMM d').format(_customFrom!);
    final to   = _customTo != null ? DateFormat('MMM d').format(_customTo!) : 'now';
    const primaryBlue = Color(0xFF3D7DFE);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: primaryBlue.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: primaryBlue.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          const Icon(Icons.date_range_rounded, size: 16, color: primaryBlue),
          const SizedBox(width: 8),
          Text('$from — $to', style: const TextStyle(fontSize: 13, color: primaryBlue, fontWeight: FontWeight.bold)),
          const Spacer(),
          GestureDetector(onTap: _pickCustomRange, child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: primaryBlue, borderRadius: BorderRadius.circular(8)),
            child: const Text('Change', style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
          )),
        ],
      ),
    );
  }

  // ── Drilldown tab bar ─────────────────────────────────────

  Widget _buildDrilldownTabBar() {
    final count = _filteredLogs.length;
    return Container(
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB)))),
      child: Row(
        children: [
          _tabBtn('Summary', 0),
          const SizedBox(width: 24),
          _tabBtn('Call History', 1, badge: count),
        ],
      ),
    );
  }

  Widget _tabBtn(String label, int idx, {int? badge}) {
    final active = _drilldownTab == idx;
    const primaryBlue = Color(0xFF3D7DFE);
    return GestureDetector(
      onTap: () => setState(() => _drilldownTab = idx),
      child: Container(
        padding: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(
            color: active ? primaryBlue : Colors.transparent, 
            width: 3,
          )),
        ),
        child: Row(children: [
          Text(label, style: TextStyle(
            fontSize: 15, 
            fontWeight: active ? FontWeight.bold : FontWeight.w500,
            color: active ? Colors.black : Colors.grey.shade500,
            fontFamily: 'Inter',
          )),
          if (badge != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: active ? primaryBlue : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('$badge', style: TextStyle(
                fontSize: 11, 
                fontWeight: FontWeight.bold, 
                color: active ? Colors.white : Colors.grey.shade600,
              )),
            ),
          ],
        ]),
      ),
    );
  }

  // ── Summary view ──────────────────────────────────────────

  Widget _buildSummaryView() {
    final s = _stats;
    if (s['total'] == 0) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Text('No data for this period.', style: TextStyle(color: Colors.grey.shade500)),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 600 ? 3 : 2;
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          padding: const EdgeInsets.symmetric(vertical: 4),
          childAspectRatio: 1.5,
          children: [
            _buildMetricCard(
              icon: Icons.phone_rounded,
              iconColor: const Color(0xFF818CF8), // Indigo/Purple
              label: 'Total Calls',
              value: '${s['total']}',
              unit: 'Calls',
            ),
            _buildMetricCard(
              icon: Icons.access_time_rounded,
              iconColor: const Color(0xFFC084FC), // Purple
              label: 'Call Duration',
              value: _fmtDur(s['totalDur']),
              unit: 'Total',
            ),
            _buildMetricCard(
              icon: Icons.call_received_rounded,
              iconColor: const Color(0xFF60A5FA), // Blue
              label: 'Incoming',
              value: '${s['incoming']}',
              unit: 'Calls',
            ),
            _buildMetricCard(
              icon: Icons.access_time_rounded,
              iconColor: const Color(0xFF93C5FD), // Light Blue
              label: 'In Duration',
              value: _fmtDur(s['inDur']),
              unit: 'Talk',
            ),
            _buildMetricCard(
              icon: Icons.call_made_rounded,
              iconColor: const Color(0xFFFB923C), // Orange
              label: 'Outgoing',
              value: '${s['outgoing']}',
              unit: 'Calls',
            ),
            _buildMetricCard(
              icon: Icons.access_time_rounded,
              iconColor: const Color(0xFFFDBA74), // Light Orange
              label: 'Out Duration',
              value: _fmtDur(s['outDur']),
              unit: 'Talk',
            ),
            _buildMetricCard(
              icon: Icons.call_missed_rounded,
              iconColor: const Color(0xFFF87171), // Red
              label: 'Missed',
              value: '${s['missed']}',
              unit: 'Calls',
            ),
            _buildMetricCard(
              icon: Icons.block_rounded,
              iconColor: const Color(0xFFF472B6), // Pink
              label: 'Rejected',
              value: '${s['rejected']}',
              unit: 'Calls',
            ),
          ],
        );
      },
    );
  }

  Widget _buildMetricCard({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required String unit,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB).withOpacity(0.8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.black, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                    fontFamily: 'Inter',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.bottomLeft,
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF111827),
                      fontFamily: 'Inter',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                unit,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade500,
                  fontFamily: 'Inter',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }



  Widget _metaCard() {
    final lastCall = _allCallLogs.firstOrNull?.timestamp;
    const primaryBlue = Color(0xFF3D7DFE);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(children: [
        _mRow('Last Call', _fmtDate(lastCall)),
        const SizedBox(height: 10),
        _mRow('Device', _deviceModel, valColor: primaryBlue),
      ]),
    );
  }

  Widget _mRow(String label, String val, {Color? valColor}) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
      Flexible(child: Text(val, textAlign: TextAlign.end, style: TextStyle(fontSize: 13, color: valColor ?? Colors.grey.shade800, fontWeight: FontWeight.w500))),
    ],
  );

  // ── Call history view ─────────────────────────────────────

  Widget _buildCallsView() {
    final logs = _filteredLogs;
    if (logs.isEmpty) {
      return Center(child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Text('No call data for this period.', style: TextStyle(color: Colors.grey.shade500)),
      ));
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: logs.length,
        separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFE5E7EB)),
        itemBuilder: (_, i) => _callItem(logs[i]),
      ),
    );
  }

  Widget _callItem(CallLogEntry e) {
    final t = _effectiveType(e);
    Color color;
    String typeStr;
    
    switch (t) {
      case CallType.incoming:
        color = const Color(0xFF3B82F6);
        typeStr = 'incoming';
        break;
      case CallType.outgoing:
        color = const Color(0xFF22C55E);
        typeStr = 'outgoing';
        break;
      case CallType.missed:
        color = const Color(0xFFEF4444);
        typeStr = 'missed';
        break;
      case CallType.rejected:
        color = const Color(0xFFF59E0B);
        typeStr = 'rejected';
        break;
      default:
        color = Colors.grey;
        typeStr = 'unknown';
    }
    
    final name = (e.name?.isNotEmpty == true) ? e.name! : (e.number ?? 'Unknown');
    final hasSub = e.name?.isNotEmpty == true;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          // Icon with background
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              (t == CallType.incoming) ? Icons.call_received :
              (t == CallType.outgoing) ? Icons.call_made :
              (t == CallType.missed) ? Icons.call_missed : Icons.call_end,
              size: 20,
              color: color,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Color(0xFF111827),
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasSub ? e.number ?? '' : typeStr.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _fmtTime(e.timestamp),
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.black87,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Inter',
                ),
              ),
              if ((e.duration ?? 0) > 0)
                Text(
                  _fmtDur(e.duration),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade400,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Analytics section (real charts) ──────────────────────

  Widget _buildAnalyticsSection() {
    final s = _stats;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Section header with chart type toggle
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('Analytics', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF111827))),
        Container(
          decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.all(3),
          child: Row(children: [
            _chartTogBtn('Pie',  0, Icons.pie_chart),
            _chartTogBtn('Bar',  1, Icons.bar_chart),
            _chartTogBtn('Line', 2, Icons.show_chart),
          ]),
        ),
      ]),
      const SizedBox(height: 16),

      // Chart card
      Container(
        height: 280,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: _chartType == 0 ? _buildPieChart(s) : _chartType == 1 ? _buildBarChart(s) : _buildLineChart(),
      ),

      const SizedBox(height: 16),

      // Legend (always visible below chart)
      _buildLegend(s),
      const SizedBox(height: 20),
      _metaCard(),
    ]);
  }

  Widget _chartTogBtn(String label, int idx, IconData icon) {
    final active = _chartType == idx;
    const primaryBlue = Color(0xFF3D7DFE);
    return GestureDetector(
      onTap: () => setState(() => _chartType = idx),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  )
                ]
              : null,
        ),
        child: Row(children: [
          Icon(icon, size: 13, color: active ? primaryBlue : Colors.grey.shade500),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: active ? FontWeight.bold : FontWeight.w500,
                  color: active ? primaryBlue : Colors.grey.shade600)),
        ]),
      ),
    );
  }

  // ── Pie chart ─────────────────────────────────────────────

  Widget _buildPieChart(Map<String, int> s) {
    final data = [
      (s['incoming']!, const Color(0xFF3B82F6)),  // blue
      (s['outgoing']!, const Color(0xFF22C55E)),  // green
      (s['missed']!,   const Color(0xFFEF4444)),  // red
      (s['rejected']!, const Color(0xFFF59E0B)),  // amber
    ];
    final total = s['total']!;

    return PieChart(
      PieChartData(
        pieTouchData: PieTouchData(
          touchCallback: (event, resp) {
            setState(() {
              _pieTouchedIndex = (resp?.touchedSection != null && event.isInterestedForInteractions)
                  ? resp!.touchedSection!.touchedSectionIndex : -1;
            });
          },
        ),
        sectionsSpace: 3,
        centerSpaceRadius: 52,
        sections: List.generate(data.length, (i) {
          final touched = i == _pieTouchedIndex;
          final val = data[i].$1;
          return PieChartSectionData(
            color: data[i].$2,
            value: val.toDouble(),
            radius: touched ? 72 : 60,
            title: val > 0 ? '${(val / total * 100).toStringAsFixed(0)}%' : '',
            titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
            borderSide: touched ? const BorderSide(color: Colors.white, width: 2) : BorderSide.none,
          );
        }),
      ),
      duration: const Duration(milliseconds: 250),
    );
  }

  // ── Bar chart ─────────────────────────────────────────────

  Widget _buildBarChart(Map<String, int> s) {
    final vals = [s['incoming']!, s['outgoing']!, s['missed']!, s['rejected']!];
    final colors = [const Color(0xFF3B82F6), const Color(0xFF22C55E), const Color(0xFFEF4444), const Color(0xFFF59E0B)];
    final labels = ['In', 'Out', 'Missed', 'Rej'];
    final maxY    = vals.fold(0, (a, b) => a > b ? a : b).toDouble();

    return BarChart(
      BarChartData(
        maxY: maxY == 0 ? 1 : maxY * 1.3,
        barTouchData: BarTouchData(enabled: true),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28,
            getTitlesWidget: (v, _) => Text('${v.toInt()}', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)))),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true,
            getTitlesWidget: (v, _) {
              final idx = v.toInt();
              return idx < labels.length ? Padding(padding: const EdgeInsets.only(top: 6), child: Text(labels[idx], style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600))) : const SizedBox();
            })),
          topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barGroups: List.generate(vals.length, (i) => BarChartGroupData(x: i, barRods: [
          BarChartRodData(toY: vals[i].toDouble(), color: colors[i], width: 32, borderRadius: BorderRadius.circular(6),
            backDrawRodData: BackgroundBarChartRodData(show: true, toY: maxY == 0 ? 1 : maxY * 1.3, color: colors[i].withOpacity(0.08))),
        ])),
      ),
      duration: const Duration(milliseconds: 300),
    );
  }

  // ── Line chart ────────────────────────────────────────────

  Widget _buildLineChart() {
    final logs = _filteredLogs.reversed.toList();
    if (logs.isEmpty) return const Center(child: Text('No data', style: TextStyle(color: Colors.grey)));

    // Group by hour (today/yesterday) or day (week/custom)
    final byPeriod = <String, int>{};
    for (final e in logs) {
      final dt = DateTime.fromMillisecondsSinceEpoch(e.timestamp ?? 0);
      final key = _selectedFilter <= 1
          ? DateFormat('ha').format(dt)          // e.g. "3PM"
          : DateFormat('EEE d').format(dt);      // e.g. "Mon 10"
      byPeriod[key] = (byPeriod[key] ?? 0) + 1;
    }

    final keys = byPeriod.keys.toList();
    final spots = List.generate(keys.length, (i) => FlSpot(i.toDouble(), byPeriod[keys[i]]!.toDouble()));
    final maxY  = spots.fold(0.0, (a, b) => a > b.y ? a : b.y);

    const primaryBlue = Color(0xFF3D7DFE);
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY == 0 ? 1 : maxY * 1.3,
        lineTouchData: LineTouchData(
            enabled: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (pts) => pts
                  .map((p) => LineTooltipItem(
                      '${p.y.toInt()} calls',
                      const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12)))
                  .toList(),
            )),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                  showTitles: true,
                  interval: (keys.length / 4).ceilToDouble(),
                  getTitlesWidget: (v, _) {
                    final i = v.toInt();
                    return i < keys.length
                        ? Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(keys[i],
                                style: TextStyle(
                                    fontSize: 9, color: Colors.grey.shade500)))
                        : const SizedBox();
                  })),
          leftTitles: AxisTitles(
              sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 26,
                  getTitlesWidget: (v, _) => Text('${v.toInt()}',
                      style:
                          TextStyle(fontSize: 10, color: Colors.grey.shade500)))),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: primaryBlue,
            barWidth: 3,
            dotData: FlDotData(show: spots.length <= 8),
            belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [
                    primaryBlue.withOpacity(0.3),
                    primaryBlue.withOpacity(0.0)
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                )),
          ),
        ],
      ),
      duration: const Duration(milliseconds: 300),
    );
  }

  // ── Legend ────────────────────────────────────────────────

  Widget _buildLegend(Map<String, int> s) {
    final items = [
      ('Incoming', const Color(0xFF3B82F6), s['incoming']!),
      ('Outgoing', const Color(0xFF22C55E), s['outgoing']!),
      ('Missed',   const Color(0xFFEF4444), s['missed']!),
      ('Rejected', const Color(0xFFF59E0B), s['rejected']!),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: items.map((item) => Column(
        children: [
          Row(children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: item.$2, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 5),
            Text(item.$1, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          ]),
          const SizedBox(height: 4),
          Text('${item.$3}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: item.$2)),
        ],
      )).toList()),
    );
  }
}

