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
    _fetchSimData();
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

    await prefs.setBool('isManualEntry', isManualEntry);
    await prefs.setString('selectedSimCarrier', effectiveCarrier);
    await prefs.setString('selectedSimSubscriptionId', subscriptionId);
    await prefs.setInt('selectedSimSlot', slot);

    final response = await ApiService.loginEmployee(companyCode, rawNumber);

    if (!mounted) return;

    if (response['success'] == true) {
      final employee = response['employee'];
      await prefs.setBool('isLoggedIn', true);
      await prefs.setString('employeeName', employee['name'] ?? '');
      await prefs.setString('mobileNumber', rawNumber);
      await prefs.setString('employeeId', employee['_id'] ?? '');

      // If the employee has no code yet, show the optional prompt
      final existingCode = employee['employeeCode'] ?? '';
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
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'Set Employee Code',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Your manager may assign you an employee code. Enter it below, or tap Skip to do it later from your profile.',
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: codeController,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: 'Employee Code (optional)',
                  hintText: 'e.g. EMP-001',
                  prefixIcon: const Icon(Icons.badge_outlined),
                  errorText: errorText.isNotEmpty ? errorText : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Skip', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                final code = codeController.text.trim();
                if (code.isEmpty) {
                  setDialogState(() => errorText = 'Please enter a code or tap Skip.');
                  return;
                }
                final res = await ApiService.updateEmployeeCode(
                  employeeId: employeeId,
                  employeeCode: code,
                );
                if (res['success'] == true) {
                  if (ctx.mounted) Navigator.pop(ctx);
                } else {
                  setDialogState(() => errorText = res['message'] ?? 'Failed to save code.');
                }
              },
              child: const Text('Save', style: TextStyle(color: Colors.white)),
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
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            hasDetected ? 'Confirm Mobile Number' : 'Enter Mobile Number',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                hasDetected
                    ? 'We detected the number below for SIM ${slotIndex + 1} ($carrier). Please verify or correct it before continuing.'
                    : 'We could not detect the mobile number for SIM ${slotIndex + 1} ($carrier). Please enter your number below.',
                style: const TextStyle(fontSize: 13, color: Colors.black54),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: numberController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Mobile Number',
                  hintText: 'e.g. 9876543210',
                  prefixIcon: const Icon(Icons.phone),
                  errorText: errorText.isNotEmpty ? errorText : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                final num = numberController.text.trim();
                if (num.isEmpty || num.length < 8) {
                  setDialogState(() => errorText = 'Please enter a valid number.');
                  return;
                }
                Navigator.pop(ctx, num);
              },
              child: const Text('Continue', style: TextStyle(color: Colors.white)),
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
