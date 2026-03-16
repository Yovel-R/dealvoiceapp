import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../utils/ui_utils.dart';
import 'package:call_log/call_log.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../../services/api_service.dart';
import '../../services/call_log_service.dart';

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  // Unused fields from header removed
  String _companyCode = '';
  String _mobileNumber = '';
  String _whatsappTemplate = 'Hi {name}!';

  List<CallLogEntry> _allCallLogs = [];
  bool _isLoadingLogs = true;
  bool _isSyncing = false;
  String _searchQuery = '';
  int _selectedTab = 0; // 0=All, 1=Incoming, 2=Outgoing, 3=Missed, 4=Rejected
  DateTime? _lastSyncTime;

  Timer? _syncTimer;
  final TextEditingController _searchController = TextEditingController();

  final _tabs = [
    _TabItem(label: 'All Calls', icon: Icons.phone),
    _TabItem(label: 'Incoming', icon: Icons.call_received),
    _TabItem(label: 'Outgoing', icon: Icons.call_made),
    _TabItem(label: 'Missed', icon: Icons.call_missed),
    _TabItem(label: 'Rejected', icon: Icons.call_end),
  ];

  @override
  void initState() {
    super.initState();
    _loadProfile().then((_) {
      // Reset sync timestamp at the start of each day
      CallLogService.resetSyncTimestamp();
      // First full load
      _fetchAllAndSync();
      // Then start live 30-second interval
      _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        _syncNewCalls();
      });
    });
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _companyCode = prefs.getString('companyCode') ?? 'XXXX';
      _mobileNumber = prefs.getString('mobileNumber') ?? 'N/A';
      _whatsappTemplate = prefs.getString('whatsappTemplate') ?? 'Hi {name}!';
    });
  }

  /// Full load on app open — fetches all of today's logs, displays and syncs them.
  Future<void> _fetchAllAndSync() async {
    setState(() => _isLoadingLogs = true);
    try {
      final logs = await CallLogService.fetchTodayLogs();
      if (mounted) {
        setState(() {
          _allCallLogs = logs;
          _isLoadingLogs = false;
        });
      }
      // Sync full today's log on initial load
      if (_companyCode.isNotEmpty && _mobileNumber.isNotEmpty) {
        await _pushLogsToBackend(logs);
        if (mounted) setState(() => _lastSyncTime = DateTime.now());
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingLogs = false);
    }
  }

  /// Called every 30s — only syncs NEW entries since the last sync.
  Future<void> _syncNewCalls() async {
    if (_companyCode.isEmpty || _mobileNumber.isEmpty) return;
    if (mounted) setState(() => _isSyncing = true);
    try {
      final res = await CallLogService.syncNewEntries(
        companyCode: _companyCode,
        phone: _mobileNumber,
      );
      
      if (res['success'] == false) {
        if (mounted) {
          UIUtils.showPremiumSnackBar(context, 'Sync failed: ${res['message']}', isError: true);
        }
      } else if (res['hasNew'] == true) {
        // Refresh the displayed list if new calls were found and synced
        final logs = await CallLogService.fetchTodayLogs();
        if (mounted) {
          setState(() {
            _allCallLogs = logs;
            _lastSyncTime = DateTime.now();
          });
        }
      } else {
        if (mounted) setState(() => _lastSyncTime = DateTime.now());
      }
    } catch (e) {
      if (mounted) {
        UIUtils.showPremiumSnackBar(context, 'Sync error: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  /// Low-level: pushes a list of entries to the backend (used by _fetchAllAndSync).
  Future<void> _pushLogsToBackend(List<CallLogEntry> list) async {
    int incoming = 0, outgoing = 0, missed = 0, rejected = 0;
    int incomingDur = 0, outgoingDur = 0, totalDur = 0;
    final callsList = <Map<String, dynamic>>[];

    for (final e in list) {
      final dur = e.duration ?? 0;
      totalDur += dur;
      String typeStr;
      final effective = (e.callType == CallType.incoming && dur == 0)
          ? CallType.rejected
          : e.callType;

      switch (effective) {
        case CallType.incoming:
          incoming++; incomingDur += dur; typeStr = 'incoming'; break;
        case CallType.outgoing:
          outgoing++; outgoingDur += dur; typeStr = 'outgoing'; break;
        case CallType.missed:
          missed++; typeStr = 'missed'; break;
        case CallType.rejected:
          rejected++; typeStr = 'rejected'; break;
        default:
          typeStr = 'unknown';
      }

      callsList.add({
        'number': e.number ?? '',
        'name': e.name ?? '',
        'callType': typeStr,
        'duration': dur,
        'timestamp': e.timestamp ?? 0,
      });
    }

    String deviceModel = '';
    try {
      final di = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await di.androidInfo;
        deviceModel = '${info.manufacturer} ${info.model}';
      } else if (Platform.isIOS) {
        final info = await di.iosInfo;
        deviceModel = info.utsname.machine;
      }
    } catch (_) {}

    final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    await ApiService.syncCallLogs(
      companyCode: _companyCode,
      phone: _mobileNumber,
      date: dateStr,
      incoming: incoming,
      outgoing: outgoing,
      missed: missed,
      rejected: rejected,
      incomingDuration: incomingDur,
      outgoingDuration: outgoingDur,
      totalDuration: totalDur,
      calls: callsList,
      deviceModel: deviceModel,
      appVersion: '1.0.0',
    );
  }

  List<CallLogEntry> get _filteredLogs {
    List<CallLogEntry> logs = _allCallLogs;

    // Tab filter
    if (_selectedTab == 1) {
      logs = logs.where((e) => _getEffectiveCallType(e) == CallType.incoming).toList();
    } else if (_selectedTab == 2) {
      logs = logs.where((e) => _getEffectiveCallType(e) == CallType.outgoing).toList();
    } else if (_selectedTab == 3) {
      logs = logs.where((e) => _getEffectiveCallType(e) == CallType.missed).toList();
    } else if (_selectedTab == 4) {
      logs = logs.where((e) => _getEffectiveCallType(e) == CallType.rejected).toList();
    }

    // Search filter
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      logs = logs.where((e) {
        final name = (e.name ?? '').toLowerCase();
        final number = (e.number ?? '').toLowerCase();
        return name.contains(q) || number.contains(q);
      }).toList();
    }

    return logs;
  }

  CallType? _getEffectiveCallType(CallLogEntry e) {
    if (e.callType == CallType.incoming && (e.duration ?? 0) == 0) {
      return CallType.rejected;
    }
    return e.callType;
  }

  String _formatDuration(int? seconds) {
    final s = seconds ?? 0;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    return '${h}h ${m}m ${sec}s';
  }

  String _formatTime(int? timestamp) {
    if (timestamp == null) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return DateFormat('hh:mm a').format(dt);
  }

  Color _callTypeColor(CallType? type) {
    switch (type) {
      case CallType.incoming:
        return const Color(0xFF4CAF50);
      case CallType.outgoing:
        return const Color(0xFFFFA726);
      case CallType.missed:
        return const Color(0xFFEF5350);
      case CallType.rejected:
        return const Color(0xFFEF5350);
      default:
        return Colors.indigo;
    }
  }

  IconData _callTypeIcon(CallType? type) {
    switch (type) {
      case CallType.incoming:
        return Icons.call_received;
      case CallType.outgoing:
        return Icons.call_made;
      case CallType.missed:
        return Icons.call_missed;
      case CallType.rejected:
        return Icons.call_end;
      default:
        return Icons.phone;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Your Activity Section (The header is now shared in DashboardScreen)

          // Your Activity Section 
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Section title
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Your Activity',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1E2E),
                      ),
                    ),
                    // Live sync indicator
                    GestureDetector(
                      onTap: _syncNewCalls,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_isSyncing)
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.indigo,
                              ),
                            )
                          else
                            Icon(Icons.sync, size: 14, color: Colors.indigo.shade400),
                          const SizedBox(width: 4),
                          Text(
                            _lastSyncTime != null
                                ? 'Synced ${DateFormat('hh:mm a').format(_lastSyncTime!)}'
                                : 'Syncing…',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.indigo.shade400,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Tab Filters
                _buildTabRow(),

                const SizedBox(height: 16),

                // Search Bar
                _buildSearchBar(),

                const SizedBox(height: 20),

                // Call Log List
                _isLoadingLogs
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(40),
                          child: CircularProgressIndicator(color: Colors.indigo),
                        ),
                      )
                    : _filteredLogs.isEmpty
                        ? _buildEmptyState()
                        : Column(
                            children: _filteredLogs.map((e) => _buildCallCard(e)).toList(),
                          ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(_tabs.length, (i) {
        final isSelected = _selectedTab == i;
        Color tabColor;
        switch (i) {
          case 1:
            tabColor = const Color(0xFF4CAF50);
            break;
          case 2:
            tabColor = const Color(0xFFFFA726);
            break;
          case 3:
            tabColor = const Color(0xFFEF5350);
            break;
          case 4:
            tabColor = const Color(0xFFEF5350);
            break;
          default:
            tabColor = Colors.indigo;
        }

        return GestureDetector(
          onTap: () => setState(() => _selectedTab = i),
          child: Column(
            children: [
              Icon(
                _tabs[i].icon,
                color: isSelected ? tabColor : Colors.grey.shade400,
                size: 22,
              ),
              const SizedBox(height: 6),
              Text(
                _tabs[i].label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? tabColor : Colors.grey.shade500,
                ),
              ),
              const SizedBox(height: 4),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 3,
                width: isSelected ? 28 : 0,
                decoration: BoxDecoration(
                  color: tabColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _searchQuery = v),
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Search by name or number…',
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
          prefixIcon: Icon(Icons.search, color: Colors.grey.shade400),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  color: Colors.grey.shade400,
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  Widget _buildCallCard(CallLogEntry entry) {
    final effectiveType = _getEffectiveCallType(entry);
    final typeColor = _callTypeColor(effectiveType);
    final typeIcon = _callTypeIcon(effectiveType);
    final name = (entry.name?.isNotEmpty == true) ? entry.name! : 'Unknown';
    final number = entry.number ?? '';
    final time = _formatTime(entry.timestamp);
    final duration = _formatDuration(entry.duration);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color.fromARGB(255, 244, 244, 244),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(typeIcon, color: typeColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Color(0xFF1A1E2E),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        number,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  time,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    duration,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.indigo.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  _actionIcon(
                    icon: Icons.call,
                    color: Colors.indigo.shade400,
                    onTap: () async {
                      final uri = Uri(scheme: 'tel', path: number);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri);
                      }
                    },
                  ),
                  const SizedBox(width: 16),
                  GestureDetector(
                    onTap: () async {
                      final cleaned = number.replaceAll(RegExp(r'[^\d]'), '');
                      // Substitute {name} placeholder with actual contact name
                      final contactName = entry.name?.isNotEmpty == true ? entry.name! : number;
                      final message = _whatsappTemplate.replaceAll('{name}', contactName);
                      final uri = Uri.parse(
                        'https://wa.me/$cleaned?text=${Uri.encodeComponent(message)}',
                      );
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    },
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: const Color(0xFF25D366),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Center(
                        child: FaIcon(FontAwesomeIcons.whatsapp, color: Colors.white, size: 16),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  _actionIcon(
                    icon: Icons.copy,
                    color: Colors.grey.shade600,
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: number));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Number copied!'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                   ),
                   const SizedBox(width: 16),
                   _actionIcon(
                     icon: Icons.bookmark_border,
                     color: Colors.amber.shade600,
                     onTap: () => _showBookmarkDialog(entry),
                   ),
                 ],
               ),
             ),
           ],
         ),
       ),
     );
   }

   Future<void> _showBookmarkDialog(dynamic entry) async {
     final name = (entry.name?.isNotEmpty == true) ? entry.name! : 'Unknown';
     final number = entry.number ?? '';
     final ts = entry.timestamp ?? 0;
     final descCtrl = TextEditingController();
     bool saving = false;
     String errorMsg = '';

     await showDialog(
       context: context,
       builder: (ctx) => StatefulBuilder(
         builder: (ctx, setDialogState) => AlertDialog(
           shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
           title: Row(
             children: [
               Icon(Icons.bookmark, color: Colors.amber.shade600, size: 22),
               const SizedBox(width: 8),
               Expanded(child: Text('Bookmark: $name', overflow: TextOverflow.ellipsis)),
             ],
           ),
           content: Column(
             mainAxisSize: MainAxisSize.min,
             children: [
               Text(number, style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
               const SizedBox(height: 14),
               TextField(
                 controller: descCtrl,
                 maxLines: 3,
                 decoration: InputDecoration(
                   hintText: 'Add a note or description…',
                   border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                   contentPadding: const EdgeInsets.all(12),
                 ),
               ),
               if (errorMsg.isNotEmpty) ...[
                 const SizedBox(height: 8),
                 Text(errorMsg, style: const TextStyle(color: Colors.red, fontSize: 12)),
               ],
             ],
           ),
           actions: [
             TextButton(
               onPressed: () => Navigator.pop(ctx),
               child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
             ),
             ElevatedButton.icon(
               style: ElevatedButton.styleFrom(
                 backgroundColor: Colors.amber.shade600,
                 foregroundColor: Colors.white,
                 shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
               ),
               icon: saving
                   ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                   : const Icon(Icons.bookmark_add, size: 16),
               label: const Text('Save'),
               onPressed: saving
                   ? null
                   : () async {
                       setDialogState(() { saving = true; errorMsg = ''; });
                       final res = await ApiService.addBookmark(
                         companyCode: _companyCode,
                         employeePhone: _mobileNumber,
                         contactNumber: number,
                         contactName: name,
                         description: descCtrl.text.trim(),
                         callTimestamp: ts is int ? ts : 0,
                       );
                       if (res['success'] == true) {
                         if (ctx.mounted) Navigator.pop(ctx);
                         if (mounted) {
                           ScaffoldMessenger.of(context).showSnackBar(
                             const SnackBar(content: Text('📌 Bookmarked!'), duration: Duration(seconds: 1)),
                           );
                         }
                       } else {
                         setDialogState(() { saving = false; errorMsg = res['message'] ?? 'Failed to save.'; });
                       }
                     },
             ),
           ],
         ),
       ),
     );
   }

  Widget _actionIcon({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Icon(icon, size: 22, color: color),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            Icon(Icons.phone_missed_outlined, size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              'No calls found',
              style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey.shade400,
                  fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabItem {
  final String label;
  final IconData icon;
  const _TabItem({required this.label, required this.icon});
}
