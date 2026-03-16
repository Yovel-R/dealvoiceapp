import 'package:flutter/material.dart';
import 'theme.dart';
import 'screens/splash_screen.dart';
import 'screens/company_code_screen.dart';
import 'screens/sim_selection_screen.dart';
import 'screens/dashboard_screen.dart';
import 'services/background_sync_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BackgroundSyncService.initialize();
  await BackgroundSyncService.registerPeriodicTask();
  runApp(const TraceCallApp());
}

class TraceCallApp extends StatelessWidget {
  const TraceCallApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DealVoice',
      theme: appTheme,
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/company-code': (context) => const CompanyCodeScreen(),
        '/sim-selection': (context) => const SimSelectionScreen(),
        '/dashboard': (context) => const DashboardScreen(),
      },
    );
  }
}
