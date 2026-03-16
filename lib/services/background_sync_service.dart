import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'call_log_service.dart';

const backgroundSyncTaskName = 'tracecall_bg_sync';
const backgroundSyncTaskTag = 'tracecall_sync_tag';

/// This function runs in a separate isolate (background).
/// It must be a top-level function.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == backgroundSyncTaskName) {
      final prefs = await SharedPreferences.getInstance();
      final companyCode = prefs.getString('companyCode') ?? '';
      final phone = prefs.getString('mobileNumber') ?? '';

      if (companyCode.isEmpty || phone.isEmpty) {
        // Not logged in yet — skip
        return Future.value(true);
      }

      try {
        await CallLogService.syncNewEntries(
          companyCode: companyCode,
          phone: phone,
        );
      } catch (e) {
        // Return true so workmanager doesn't retry aggressively
        return Future.value(true);
      }
    }
    return Future.value(true);
  });
}

class BackgroundSyncService {
  /// Call once from main() to register the periodic background task.
  static Future<void> initialize() async {
    if (Platform.isAndroid || Platform.isIOS) {
      await Workmanager().initialize(
        callbackDispatcher,
      );
    }
  }

  /// Register a periodic task (minimum 15 minutes on Android due to OS limits).
  static Future<void> registerPeriodicTask() async {
    if (Platform.isAndroid || Platform.isIOS) {
      await Workmanager().registerPeriodicTask(
        backgroundSyncTaskTag,
        backgroundSyncTaskName,
        frequency: const Duration(minutes: 15),
        // Run even if app is in the background
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
    }
  }

  /// Cancel the background task (e.g. on logout).
  static Future<void> cancelTask() async {
    if (Platform.isAndroid || Platform.isIOS) {
      await Workmanager().cancelByTag(backgroundSyncTaskTag);
    }
  }
}
