import 'dart:io';
import 'package:call_log/call_log.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class CallLogService {
  static const _lastSyncKey = 'lastCallLogSyncTimestamp';

  /// Returns a map with 'success' and 'hasNew' flags.
  static Future<Map<String, dynamic>> syncNewEntries({
    required String companyCode,
    required String phone,
  }) async {
    // Ensure permission
    final status = await Permission.phone.request();
    if (!status.isGranted) return {'success': false, 'message': 'Phone permission denied', 'hasNew': false};

    final prefs = await SharedPreferences.getInstance();
    final selectedCarrier = prefs.getString('selectedSimCarrier') ?? '';
    final selectedSlot = prefs.getInt('selectedSimSlot') ?? 0;
    final selectedSubId = prefs.getString('selectedSimSubscriptionId') ?? '';
    final isManualEntry = prefs.getBool('isManualEntry') ?? false;
    final now = DateTime.now();
    // Capture the exact cutoff timestamp BEFORE the query so we store it
    // as lastSync on success — not a later DateTime.now() that could miss
    // calls arriving between the query and the API response finishing.
    final queryTo = now.millisecondsSinceEpoch;

    // Start of today (so we never miss any call from today)
    final startOfToday =
        DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;

    // The last timestamp we synced — default to start of today on first run
    final lastSync = prefs.getInt(_lastSyncKey) ?? startOfToday;

    // Query new entries to see if we need to sync
    final Iterable<CallLogEntry> newEntries = await CallLog.query(
      dateFrom: lastSync,
      dateTo: queryTo,
    );

    // Filter new entries for relevance (selected SIM)
    final relevantNewEntries = newEntries.where((e) => _isCallFromSelectedSim(e, selectedCarrier, selectedSlot, selectedSubId, isManualEntry)).toList();

    // Nothing new to sync
    if (relevantNewEntries.isEmpty) return {'success': true, 'hasNew': false};

    // Calculate stats for the DELTA (the new calls)
    int incoming = 0, outgoing = 0, missed = 0, rejected = 0;
    int incomingDur = 0, outgoingDur = 0, totalDur = 0;
    final callsList = <Map<String, dynamic>>[];

    for (final e in relevantNewEntries) {
      final dur = e.duration ?? 0;
      totalDur += dur;
      String typeStr;

      // Classify: incoming with 0 duration = rejected
      final effective = (e.callType == CallType.incoming && dur == 0)
          ? CallType.rejected
          : e.callType;

      switch (effective) {
        case CallType.incoming:
          incoming++;
          incomingDur += dur;
          typeStr = 'incoming';
          break;
        case CallType.outgoing:
          outgoing++;
          outgoingDur += dur;
          typeStr = 'outgoing';
          break;
        case CallType.missed:
          missed++;
          typeStr = 'missed';
          break;
        case CallType.rejected:
          rejected++;
          typeStr = 'rejected';
          break;
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

    // Get device info
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

    final dateStr = DateFormat('yyyy-MM-dd').format(now);

    // Sync to backend
    final res = await ApiService.syncCallLogs(
      companyCode: companyCode,
      phone: phone,
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

    if (res['success'] == true) {
      // ONLY update last sync timestamp if the API call succeeded.
      // Use queryTo (the cutoff used for the query), NOT DateTime.now(),
      // so calls that arrive between the query and the API response are
      // still picked up on the next sync.
      await prefs.setInt(_lastSyncKey, queryTo);
      return {'success': true, 'hasNew': true};
    } else if (res['code'] == 'SUBSCRIPTION_EXPIRED') {
      // Subscription expired — do not update lastSync, show renewal prompt
      return {
        'success': false,
        'subscriptionExpired': true,
        'message': 'Your subscription has expired. Please renew your plan to continue syncing call records.',
        'hasNew': false,
      };
    } else {
      return {
        'success': false,
        'message': res['message'] ?? 'Sync API failed',
        'hasNew': true
      };
    }
  }

  /// Fetch logs for a specific period and filter by selected SIM.
  static Future<List<CallLogEntry>> fetchLogsForPeriod(int fromMillis, int toMillis) async {
    final status = await Permission.phone.request();
    if (!status.isGranted) return [];

    final prefs = await SharedPreferences.getInstance();
    final selectedCarrier = prefs.getString('selectedSimCarrier') ?? '';
    final selectedSlot = prefs.getInt('selectedSimSlot') ?? 0;
    final selectedSubId = prefs.getString('selectedSimSubscriptionId') ?? '';
    final isManualEntry = prefs.getBool('isManualEntry') ?? false;

    final entries = await CallLog.query(
      dateFrom: fromMillis,
      dateTo: toMillis,
    );

    final all = entries.toList();
    final filtered = all.where((e) => _isCallFromSelectedSim(e, selectedCarrier, selectedSlot, selectedSubId, isManualEntry)).toList();
    return filtered;
  }

  /// Full sync — all of today's calls from the selected SIM. Used on initial load.
  static Future<List<CallLogEntry>> fetchTodayLogs() async {
    final status = await Permission.phone.request();
    if (!status.isGranted) return [];

    final prefs = await SharedPreferences.getInstance();
    final selectedCarrier = prefs.getString('selectedSimCarrier') ?? '';
    final selectedSlot = prefs.getInt('selectedSimSlot') ?? 0;
    final selectedSubId = prefs.getString('selectedSimSubscriptionId') ?? '';
    final isManualEntry = prefs.getBool('isManualEntry') ?? false;

    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final entries = await CallLog.query(
      dateFrom: startOfToday.millisecondsSinceEpoch,
      dateTo: now.millisecondsSinceEpoch,
    );

    final all = entries.toList();
    final filtered = all.where((e) => _isCallFromSelectedSim(e, selectedCarrier, selectedSlot, selectedSubId, isManualEntry)).toList();
    return filtered;
  }

  /// Reset the sync timestamp (e.g., when the day changes)
  static Future<void> resetSyncTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    await prefs.setInt(_lastSyncKey, startOfToday.millisecondsSinceEpoch);
  }


  /// Helper to accurately check if a call entry matches the user's selected SIM
  static bool _isCallFromSelectedSim(
    CallLogEntry e,
    String selectedCarrier,
    int selectedSlot,
    String selectedSubId,
    bool isManualEntry,
  ) {
    if (selectedCarrier.isEmpty && selectedSubId.isEmpty && !isManualEntry) return true;

    final accountId = (e.phoneAccountId ?? '').trim();
    final simName = (e.simDisplayName ?? '').toLowerCase().trim();
    final carrier = selectedCarrier.toLowerCase().trim();
    final slotPattern = 'sim ${selectedSlot + 1}';

    // 1. Subscription ID match (most reliable)
    if (selectedSubId.isNotEmpty && accountId == selectedSubId) return true;

    // 2. Slot index match via accountId
    if (accountId == selectedSlot.toString() ||
        accountId == (selectedSlot + 1).toString()) return true;

    // 3. Carrier name match via simDisplayName
    if (simName.isNotEmpty && carrier.isNotEmpty) {
      if (simName.contains(carrier) || carrier.contains(simName)) return true;
      if (simName.contains(slotPattern)) return true;
    }

    // 4. Carrier name match via accountId
    if (carrier.isNotEmpty && accountId.toLowerCase().contains(carrier)) return true;

    // 5. Manual entry fallback for older devices with no SIM metadata
    if (isManualEntry) {
      // accountId is often just "0" or "1" for slot index on older devices
      if (accountId == selectedSlot.toString() ||
          accountId == (selectedSlot + 1).toString()) return true;
      // If accountId is completely absent, show only slot-0 calls when slot 0 selected
      if (accountId.isEmpty && selectedSlot == 0) return true;
    }

    return false;
  }
}
