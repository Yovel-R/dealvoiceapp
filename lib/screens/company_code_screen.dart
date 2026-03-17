import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/ui_utils.dart';
import '../services/api_service.dart';

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
      UIUtils.showPremiumSnackBar(context, 'Please enter a company code', isError: true, showAtTop: true);
      return;
    }

    setState(() => _isLoading = true);
    
    final res = await ApiService.verifyCompanyCode(code);
    
    if (!mounted) return;

    if (res['success'] == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('companyCode', code);
      Navigator.pushReplacementNamed(context, '/sim-selection');
    } else {
      setState(() => _isLoading = false);
      UIUtils.showPremiumSnackBar(
        context, 
        res['message'] ?? 'Invalid company code. Please check and try again.', 
        isError: true,
        showAtTop: true
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryBlue = Color(0xFF3D7DFE);
    
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 80),
              
              // Animated Icon/Logo Area
              Center(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: primaryBlue.withOpacity(0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.business_rounded, 
                    size: 64, 
                    color: primaryBlue
                  ),
                ),
              ),
              
              const SizedBox(height: 48),
              
              const Text(
                'Welcome to DealVoice',
                style: TextStyle(
                  fontSize: 28, 
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF111827),
                  fontFamily: 'Inter',
                  letterSpacing: -1,
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 12),
              
              Text(
                'Enter your unique company code to continue with the setup.',
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey.shade500,
                  fontFamily: 'Inter',
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 48),
              
              // Input Field with Premium Styling
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: TextField(
                  controller: _codeController,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(
                    fontSize: 16, 
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Inter',
                    letterSpacing: 2,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Company Code',
                    labelStyle: TextStyle(
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0,
                    ),
                    hintText: 'e.g. ABC-0101-2024',
                    hintStyle: TextStyle(
                      color: Colors.grey.shade300,
                      letterSpacing: 0,
                    ),
                    prefixIcon: const Icon(Icons.vpn_key_outlined, size: 22, color: primaryBlue),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(20),
                  ),
                ),
              ),
              
              const SizedBox(height: 12),
              
              Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 14, color: Colors.grey.shade400),
                  const SizedBox(width: 6),
                  Text(
                    'Ask your admin if you don\'t have a code.',
                    style: TextStyle(
                      fontSize: 12, 
                      color: Colors.grey.shade400,
                      fontFamily: 'Inter',
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 48),
              
              // Premium Action Button
              ElevatedButton(
                onPressed: _isLoading ? null : _verifyCode,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryBlue,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: primaryBlue.withOpacity(0.6),
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  elevation: 8,
                  shadowColor: primaryBlue.withOpacity(0.4),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 3, 
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Continue to Login',
                        style: TextStyle(
                          fontSize: 16, 
                          fontWeight: FontWeight.w900,
                          fontFamily: 'Inter',
                        ),
                      ),
              ),
              
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
