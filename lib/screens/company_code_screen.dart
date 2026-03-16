import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/ui_utils.dart';

class CompanyCodeScreen extends StatefulWidget {
  const CompanyCodeScreen({Key? key}) : super(key: key);

  @override
  State<CompanyCodeScreen> createState() => _CompanyCodeScreenState();
}

class _CompanyCodeScreenState extends State<CompanyCodeScreen> {
  final _codeController = TextEditingController();
  bool _isLoading = false;

  void _verifyCode() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      UIUtils.showPremiumSnackBar(context, 'Please enter a company code', isError: true);
      return;
    }

    setState(() => _isLoading = true);
    
    // In a real flow, you might verify the company code exists first via API.
    // Here we'll just save it and proceed to SIM selection since login happens there.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('companyCode', code);

    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/sim-selection');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('DealVoice Setup')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.business_rounded, size: 64, color: Colors.indigo),
            const SizedBox(height: 24),
            const Text(
              'Enter Company Code',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Ask your administrator for the trace tracking code.',
              style: TextStyle(color: Colors.black54),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _codeController,
              decoration: const InputDecoration(
                labelText: 'Company Code',
                hintText: 'e.g. SOG-2903-2026',
                prefixIcon: Icon(Icons.vpn_key),
              ),
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _isLoading ? null : _verifyCode,
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}
