import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/api_service.dart';
import '../utils/ui_utils.dart';

class SimSelectionScreen extends StatefulWidget {
  const SimSelectionScreen({Key? key}) : super(key: key);

  @override
  State<SimSelectionScreen> createState() => _SimSelectionScreenState();
}

class _SimSelectionScreenState extends State<SimSelectionScreen> {
  static const platform = MethodChannel('com.example.mobile/sim');

  bool _isLoading = true;
  String _statusMessage = 'Checking device SIMs...';
  List<Map<String, dynamic>> _simCards = [];

  @override
  void initState() {
    super.initState();
    _checkSetupAndFetch();
  }

  Future<void> _checkSetupAndFetch() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString('companyCode') ?? '';
    if (code.isEmpty) {
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/company-code');
      }
      return;
    }
    await _fetchSimData();
  }

  Future<void> _fetchSimData() async {
    // Both are often required on newer Android versions to get the full SIM data and numbers
    final phoneStatus = await Permission.phone.request();
    
    if (phoneStatus.isGranted) {
      try {
        final List<dynamic> result = await platform.invokeMethod('getSimCards');
        
        setState(() {
          _simCards = result.map((e) => Map<String, dynamic>.from(e)).toList();
          _isLoading = false;
        });

        if (_simCards.isEmpty) {
          setState(() {
            _statusMessage = 'No SIM cards detected or permission denied natively.';
          });
        } else if (_simCards.length == 1) {
          // Auto select if only 1 SIM
          _loginWithSim(_simCards.first);
        } else {
          setState(() {
            _statusMessage = 'Multiple SIMs detected. Please select one:';
          });
        }
      } on PlatformException catch (e) {
        setState(() {
           _isLoading = false;
           _statusMessage = 'Failed to fetch SIM data from native. ${e.message}';
        });
      }
    } else {
      setState(() {
        _isLoading = false;
        _statusMessage = 'Phone permission is required to detect mobile number.';
      });
    }
  }

  Future<void> _loginWithSim(Map<String, dynamic> sim) async {
    final carrier = sim['carrierName'] ?? 'Unknown Carrier';
    final slotIndex = sim['slotIndex'] ?? 0;
    setState(() {
      _isLoading = true;
      _statusMessage = 'Logging in with $carrier...';
    });

    final prefs = await SharedPreferences.getInstance();
    final companyCode = prefs.getString('companyCode') ?? '';

    String rawNumber = sim['number']?.toString() ?? '';

    // Strip common country code prefixes (e.g. +91, 0091) to get bare local number
    if (rawNumber.startsWith('+')) rawNumber = rawNumber.substring(1);
    if (rawNumber.length > 10 && rawNumber.startsWith('91')) {
      rawNumber = rawNumber.substring(2);
    }
    rawNumber = rawNumber.replaceAll(RegExp(r'[\s\-]'), '');

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _statusMessage = rawNumber.isEmpty
          ? 'Number not found on SIM.'
          : 'Please confirm your number.';
    });

    final slot = slotIndex is int ? slotIndex : int.tryParse(slotIndex.toString()) ?? 0;
    final confirmedNumber = await _showManualNumberDialog(carrier, slot, prefill: rawNumber);
    if (confirmedNumber == null || confirmedNumber.isEmpty) {
      setState(() => _statusMessage = 'Login cancelled.');
      return;
    }
    rawNumber = confirmedNumber;
    setState(() {
      _isLoading = true;
      _statusMessage = 'Logging in with $carrier...';
    });

    // Save the selected SIM info for call log filtering later.
    // If carrier is unknown, save empty string so the filter shows all calls.
    final effectiveCarrier = (carrier == 'Unknown Carrier') ? '' : carrier;
    final subscriptionId = sim['subscriptionId']?.toString() ?? '';

    // Detect if the user had to manually enter their number (SIM didn't provide it)
    final isManualEntry = (sim['number']?.toString() ?? '').isEmpty || (carrier == 'Unknown Carrier' && subscriptionId.isEmpty);

    final displayName = sim['displayName']?.toString() ?? '';

    await prefs.setBool('isManualEntry', isManualEntry);
    await prefs.setString('selectedSimCarrier', effectiveCarrier);
    await prefs.setString('selectedSimDisplayName', displayName);
    await prefs.setString('selectedSimSubscriptionId', subscriptionId);
    await prefs.setInt('selectedSimSlot', slot);

    final response = await ApiService.loginEmployee(companyCode, rawNumber);

    if (!mounted) return;

    if (response['success'] == true) {
      final employee = response['employee'];
      await prefs.setBool('isLoggedIn', true);
      await prefs.setString('employeeName', employee['name'] ?? '');
      await prefs.setString('mobileNumber', rawNumber);
      // Save employee code if it exists
      final existingCode = employee['employeeCode'] ?? '';
      if (existingCode.isNotEmpty) {
        await prefs.setString('employeeCode', existingCode);
      }

      // If the employee has no code yet, show the optional prompt
      if (existingCode.isEmpty && mounted) {
        await _showEmployeeCodeDialog(employee['_id'] ?? '');
      }

      if (mounted) {
        Navigator.pushReplacementNamed(context, '/dashboard');
      }
    } else {
      setState(() {
        _isLoading = false;
      });
      UIUtils.showPremiumSnackBar(context, response['message'] ?? 'Login failed', isError: true);
    }
  }

  /// Shows an optional dialog where the employee can set their employee code.
  /// They can skip and go straight to the dashboard.
  Future<void> _showEmployeeCodeDialog(String employeeId) async {
    final codeController = TextEditingController();
    String errorText = '';

    await UIUtils.showSmoothDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => PremiumDialog(
          icon: Icons.badge_outlined,
          iconColor: Colors.indigo,
          title: 'Employee Code',
          subtitle: 'Your manager may assign you a code. Enter it below, or skip for now.',
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: codeController,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(fontSize: 14, fontFamily: 'Inter'),
                decoration: InputDecoration(
                  labelText: 'Company Code',
                  hintText: 'e.g. EMP-001',
                  prefixIcon: const Icon(Icons.pin_outlined, size: 20),
                  errorText: errorText.isNotEmpty ? errorText : null,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: Text('Skip for now', style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold, fontFamily: 'Inter')),
            ),
            ElevatedButton(
              onPressed: () async {
                final code = codeController.text.trim();
                if (code.isEmpty) {
                  setDialogState(() => errorText = 'Enter code or tap Skip.');
                  return;
                }
                final res = await ApiService.updateEmployeeCode(
                  employeeId: employeeId,
                  employeeCode: code,
                );
                if (res['success'] == true) {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('employeeCode', code);
                  if (ctx.mounted) Navigator.pop(ctx);
                } else {
                  setDialogState(() => errorText = res['message'] ?? 'Failed to save.');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text('Save Code', style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Inter')),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _showManualNumberDialog(String carrier, int slotIndex, {String prefill = ''}) async {
    final numberController = TextEditingController(text: prefill);
    String errorText = '';
    final hasDetected = prefill.isNotEmpty;

    return await UIUtils.showSmoothDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => PremiumDialog(
          icon: hasDetected ? Icons.verified_user_rounded : Icons.phone_android_rounded,
          iconColor: Colors.indigo,
          title: hasDetected ? 'Verify Number' : 'Enter Number',
          subtitle: hasDetected
              ? 'SIM ${slotIndex + 1} ($carrier) number detected. Please confirm.'
              : 'Could not detect number for SIM ${slotIndex + 1}. Please enter manually.',
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: numberController,
                keyboardType: TextInputType.phone,
                style: const TextStyle(fontSize: 14, fontFamily: 'Inter'),
                decoration: InputDecoration(
                  labelText: 'Mobile Number',
                  hintText: 'e.g. 9876543210',
                  prefixIcon: const Icon(Icons.phone, size: 20),
                  errorText: errorText.isNotEmpty ? errorText : null,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: Text('Cancel', style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold, fontFamily: 'Inter')),
            ),
            ElevatedButton(
              onPressed: () {
                final num = numberController.text.trim();
                if (num.isEmpty || num.length < 8) {
                  setDialogState(() => errorText = 'Enter a valid number.');
                  return;
                }
                Navigator.pop(ctx, num);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text('Continue', style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Inter')),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detect Mobile Number')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.sim_card, size: 64, color: Colors.indigo),
            const SizedBox(height: 24),
            Text(
              _statusMessage,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            if (_isLoading)
              const Center(child: CircularProgressIndicator()),
            if (!_isLoading && _simCards.length > 1)
              ..._simCards.map((sim) => Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: ElevatedButton.icon(
                  onPressed: () => _loginWithSim(sim),
                  icon: const Icon(Icons.sim_card),
                  label: Text('Use SIM ${sim['slotIndex']} (${sim['carrierName']})'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.indigo,
                    side: const BorderSide(color: Colors.indigo),
                  ),
                ),
              )).toList(),
          ],
        ),
      ),
    );
  }
}
