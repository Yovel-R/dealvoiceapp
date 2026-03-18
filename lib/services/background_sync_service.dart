import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:phone_state/phone_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'call_log_service.dart';

const backgroundSyncTaskName = 'tracecall_bg_sync';
const backgroundSyncTaskTag = 'tracecall_sync_tag';
const notificationChannelId = 'dealvoice_sync_channel';
const notificationId = 888;

/// This function runs in a separate isolate (background).
/// It must be a top-level function for Workmanager.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == backgroundSyncTaskName) {
      await BackgroundSyncService.performSync();
    }
    return Future.value(true);
  });
}

/// This function runs in the foreground service isolate.
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // Listen for phone state changes and sync immediately after a call ends
  PhoneState.stream.listen((state) async {
    debugPrint('Background Service: Phone Status Changed -> ${state.status}');
    if (state.status == PhoneStateStatus.NOTHING ||
        state.status == PhoneStateStatus.CALL_ENDED) {
      debugPrint('Call Ended detected. Waiting 8s for call log to populate...');
      // Wait a bit longer for system log to update (especially on slow devices)
      await Future.delayed(const Duration(seconds: 8));
      final hasNew = await BackgroundSyncService.performSync();
      // Notify the UI if it's open
      service.invoke('update', {'hasNew': hasNew});

      // Update the notification with the latest sync time
      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: "DealVoice Sync Active",
          content:
              "Last synced: ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}",
        );
      }
    }
  });

  // Periodic redundant heartbeat every 30 minutes as a safety net
  Timer.periodic(const Duration(minutes: 30), (timer) async {
    await BackgroundSyncService.performSync();
  });
}

class BackgroundSyncService {
  /// Global method to perform the actual sync logic. Returns true if new calls synced.
  static Future<bool> performSync() async {
    debugPrint('BackgroundSyncService: Starting performSync()...');
    final prefs = await SharedPreferences.getInstance();
    
    // Very important for multi-isolate sync
    try {
      await prefs.reload();
      debugPrint('SharedPreferences reloaded successfully in background.');
    } catch (e) {
      debugPrint('Warning: Could not reload SharedPreferences: $e');
    }

    final companyCode = prefs.getString('companyCode') ?? '';
    final phone = prefs.getString('mobileNumber') ?? '';

    debugPrint('Sync Credentials: Company=$companyCode, Phone=$phone');
    if (companyCode.isEmpty || phone.isEmpty) {
      debugPrint('Sync aborted: Missing credentials in SharedPreferences.');
      return false;
    }

    try {
      final res = await CallLogService.syncNewEntries(
        companyCode: companyCode,
        phone: phone,
      );
      return res['hasNew'] == true;
    } catch (e) {
      debugPrint('Sync failed: $e');
      return false;
    }
  }

  /// Initialize all background capabilities
  static Future<void> initialize() async {
    // 1. Initialize Workmanager (The Safety Net)
    if (Platform.isAndroid || Platform.isIOS) {
      await Workmanager().initialize(callbackDispatcher);
    }

    // 2. Initialize Foreground Service (The Instant Sync)
    final service = FlutterBackgroundService();

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      notificationChannelId,
      'DealVoice Sync',
      description: 'Maintains background connection for instant call sync.',
      importance: Importance.low,
    );

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

    if (Platform.isAndroid) {
      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: true,
        isForegroundMode: true,
        notificationChannelId: notificationChannelId,
        initialNotificationTitle: 'DealVoice Active',
        initialNotificationContent: 'Monitoring calls for automatic sync',
        foregroundServiceNotificationId: notificationId,
        foregroundServiceTypes: [AndroidForegroundType.dataSync], // Android 14 requirement
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: onStart,
        onBackground: (service) => true,
      ),
    );

    // service.startService() not needed when autoStart: true
  }

  /// Register periodic backup task (runs even if service is killed)
  static Future<void> registerPeriodicTask() async {
    if (Platform.isAndroid || Platform.isIOS) {
      await Workmanager().registerPeriodicTask(
        backgroundSyncTaskTag,
        backgroundSyncTaskName,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
    }
  }

  static Future<void> stopAll() async {
    final service = FlutterBackgroundService();
    service.invoke("stopService");
    await Workmanager().cancelByTag(backgroundSyncTaskTag);
  }
}
