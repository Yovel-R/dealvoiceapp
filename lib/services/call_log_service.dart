import 'dart:io';
import 'package:call_log/call_log.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class CallLogService {
  static const _lastSyncKey = 'lastCallLogSyncTimestamp';

  static Future<void> resetSyncTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    
    // Reset to start of today so that the next sync captures all of today's calls
    await prefs.setInt(_lastSyncKey, startOfToday);
    debugPrint('CallLog: Reset sync timestamp to start of today');
  }

  static Future<Map<String, dynamic>> syncNewEntries({
    required String companyCode,
    required String phone,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final selectedCarrier = prefs.getString('selectedSimCarrier') ?? '';
    final selectedDisplayName = prefs.getString('selectedSimDisplayName') ?? '';
    final selectedSlot = prefs.getInt('selectedSimSlot') ?? 0;
    final selectedSubId = prefs.getString('selectedSimSubscriptionId') ?? '';
    final isManualEntry = prefs.getBool('isManualEntry') ?? false;
    
    debugPrint('CallLog: Syncing for SIM: $selectedDisplayName ($selectedCarrier)');

    final now = DateTime.now();
    final queryTo = now.millisecondsSinceEpoch;
    final lastSync = prefs.getInt(_lastSyncKey) ?? DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;

    final Iterable<CallLogEntry> entries = await CallLog.query(dateFrom: lastSync, dateTo: queryTo);
    final all = entries.toList();

    final relevant = all.where((e) => _isCallFromSelectedSim(e, selectedCarrier, selectedDisplayName, selectedSlot, selectedSubId, isManualEntry)).toList();
    
    if (relevant.isEmpty) return {'success': true, 'hasNew': false};

    final groupedCalls = <String, List<CallLogEntry>>{};
    
    for (final e in relevant) {
      final timestamp = e.timestamp ?? 0;
      final dateStr = timestamp == 0 
          ? DateFormat('yyyy-MM-dd').format(now) 
          : DateFormat('yyyy-MM-dd').format(DateTime.fromMillisecondsSinceEpoch(timestamp));
          
      if (!groupedCalls.containsKey(dateStr)) {
        groupedCalls[dateStr] = [];
      }
      groupedCalls[dateStr]!.add(e);
    }

    bool allSuccess = true;
    String? lastErrorMsg;

    for (final dateStr in groupedCalls.keys) {
      final entriesForDate = groupedCalls[dateStr]!;
      
      int incoming = 0, outgoing = 0, missed = 0, rejected = 0;
      int incomingDur = 0, outgoingDur = 0, totalDur = 0;
      final callsList = <Map<String, dynamic>>[];

      for (final e in entriesForDate) {
        final dur = e.duration ?? 0;
        String typeStr = 'unknown';

        final effective = (e.callType == CallType.incoming && dur == 0) ? CallType.rejected : e.callType;
        switch (effective) {
          case CallType.incoming: 
            incoming++; incomingDur += dur; totalDur += dur; typeStr = 'incoming'; break;
          case CallType.outgoing: 
            outgoing++; outgoingDur += dur; totalDur += dur; typeStr = 'outgoing'; break;
          case CallType.missed: missed++; typeStr = 'missed'; break;
          case CallType.rejected: rejected++; typeStr = 'rejected'; break;
          default: break;
        }

        callsList.add({
          'number': e.number ?? '',
          'name': e.name ?? '',
          'callType': typeStr,
          'duration': dur,
          'timestamp': e.timestamp ?? 0,
        });
      }

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
        deviceModel: 'Android Device', // Fallback for brevity
        appVersion: '1.0.0',
      );

      if (res['success'] != true) {
        allSuccess = false;
        lastErrorMsg = res['message'];
      }
    }

    if (allSuccess) {
      await prefs.setInt(_lastSyncKey, queryTo);
      return {'success': true, 'hasNew': true};
    }
    return {'success': false, 'message': lastErrorMsg, 'hasNew': true};
  }

  static Future<List<CallLogEntry>> fetchLogsForPeriod(int from, int to) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final selectedCarrier = prefs.getString('selectedSimCarrier') ?? '';
    final selectedDisplayName = prefs.getString('selectedSimDisplayName') ?? '';
    final selectedSlot = prefs.getInt('selectedSimSlot') ?? 0;
    final selectedSubId = prefs.getString('selectedSimSubscriptionId') ?? '';
    final isManualEntry = prefs.getBool('isManualEntry') ?? false;

    final entries = await CallLog.query(dateFrom: from, dateTo: to);
    
    final all = entries.toList();
    debugPrint('CallLog UI: Verifying SIM for ${all.length} entries in period...');

    final filtered = all.where((e) {
      return _isCallFromSelectedSim(e, selectedCarrier, selectedDisplayName, selectedSlot, selectedSubId, isManualEntry);
    }).toList();

    return filtered;
  }

  static Future<List<CallLogEntry>> fetchTodayLogs() async {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    return fetchLogsForPeriod(startOfToday.millisecondsSinceEpoch, now.millisecondsSinceEpoch);
  }

  // --- Unified Filtering Logic ---
  static bool _isCallFromSelectedSim(
    CallLogEntry e,
    String selectedCarrier,
    String selectedDisplayName,
    int selectedSlot,
    String selectedSubId,
    bool isManualEntry,
  ) {
    // If no SIM selection info is saved at all — allow everything
    if (selectedCarrier.isEmpty && selectedSubId.isEmpty && !isManualEntry) return true;

    // If user manually entered their number (old device / carrier unknown), 
    // we can't do any reliable SIM filtering — allow all logs through.
    if (isManualEntry) return true;

    final accountId = (e.phoneAccountId ?? '').trim();
    final simName = (e.simDisplayName ?? '').trim();

    debugPrint('SIMFilter → accountId="$accountId" simName="$simName" | selected: carrier="$selectedCarrier" subId="$selectedSubId" slot=$selectedSlot displayName="$selectedDisplayName"');

    // 1. Strict Technical ID Matching
    if (accountId.isNotEmpty) {
      if (selectedSubId.isNotEmpty && accountId == selectedSubId) return true;
      // Avoid overlaps where SIM 1's subscription ID ("1") matches SIM 2's slot index (1).
      // Only fallback to slot string comparison if we don't have a valid subscription ID saved.
      if (selectedSubId.isEmpty && accountId == selectedSlot.toString()) return true;
    }

    // 2. Strict Display Name Matching (Fallback)
    if (simName.isNotEmpty && selectedDisplayName.isNotEmpty) {
      if (simName == selectedDisplayName) return true;
      
      // If simName contains slot indicator like "1" or "2"
      final slotStr = (selectedSlot + 1).toString();
      if (simName.contains(slotStr) && !simName.contains(selectedSlot == 0 ? "2" : "1")) {
         // Check if it also matches carrier
         if (selectedCarrier.isNotEmpty && simName.toLowerCase().contains(selectedCarrier.toLowerCase())) return true;
      }
    }

    // 3. Last Resort: Carrier match only if it's the only info we have
    if (simName.isNotEmpty && selectedCarrier.isNotEmpty) {
      if (simName.toLowerCase() == selectedCarrier.toLowerCase()) return true;
    }

    // 4. Ultimate Fallback for Very Old Devices
    // On older Android OS (like Vivo 1807 / Android 8), the CallLog provider 
    // often provides absolutely NO SIM information (no accountId, no simName)
    // We let these logs pass so they actually appear on screen instead of being blocked.
    if (accountId.isEmpty && simName.isEmpty) {
      return true;
    }

    return false;
  }
}
