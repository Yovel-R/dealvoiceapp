import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../utils/ui_utils.dart';
import '../../services/background_sync_service.dart';

class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  String _employeeName = '';
  String _appVersion = '1.0.0';
  // Removed redundant header fields

  final TextEditingController _templateCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final packageInfo = await PackageInfo.fromPlatform();
    setState(() {
      _employeeName = prefs.getString('employeeName') ?? 'Employee';
      _templateCtrl.text = prefs.getString('whatsappTemplate') ?? 'Hi {name}!';
      _appVersion = '${packageInfo.version} (${packageInfo.buildNumber})';
    });
  }

  Future<void> _saveTemplate() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('whatsappTemplate', _templateCtrl.text.trim());
  }

  @override
  void dispose() {
    _templateCtrl.dispose();
    super.dispose();
  }

  void _showPrivacyPolicy() {
    UIUtils.showSmoothDialog(
      context: context,
      builder: (context) => PremiumDialog(
        icon: Icons.privacy_tip_rounded,
        title: 'Privacy Policy',
        subtitle: 'Last updated: March 2024',
        content: const Text(
          'DealVoice respects your privacy and ensures that your call logs are securely synced to your organization\'s dashboard. We do not share your personal data with third parties.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Color(0xFF4B5563), height: 1.5, fontFamily: 'Inter'),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3D7DFE),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
            child: const Text('Understand', style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Inter')),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    final confirm = await UIUtils.showSmoothDialog<bool>(
      context: context,
      builder: (context) => PremiumDialog(
        icon: Icons.logout_rounded,
        title: 'Log Out',
        subtitle: 'Are you sure you want to log out of DealVoice? All local data will be cleared.',
        isDestructive: true,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: Text('Cancel', style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold, fontFamily: 'Inter')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
            child: const Text('Log Out', style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Inter')),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // Stop background service before clearing data
      await BackgroundSyncService.stopAll();
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
      }
    }
  }

  void _showWhatsAppTemplateDialog() {
    UIUtils.showSmoothDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return PremiumDialog(
            icon: FontAwesomeIcons.whatsapp,
            iconColor: const Color(0xFF25D366),
            title: 'WhatsApp Format',
            subtitle: 'Customize your auto-fill message. Use {name} for dynamic placeholders.',
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Quick-insert chip
                GestureDetector(
                  onTap: () {
                    final pos = _templateCtrl.selection.baseOffset;
                    final text = _templateCtrl.text;
                    const insert = '{name}';
                    final validPos = pos < 0 ? text.length : pos;
                    final newText = text.substring(0, validPos) + insert + text.substring(validPos);
                    _templateCtrl.value = TextEditingValue(
                      text: newText,
                      selection: TextSelection.collapsed(offset: validPos + insert.length),
                    );
                    setDialogState(() {});
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF25D366).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF25D366).withOpacity(0.2)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                         Icon(Icons.add_circle_outline_rounded, color: Color(0xFF166534), size: 14),
                         SizedBox(width: 6),
                         Text(
                          'Insert {name}',
                          style: TextStyle(fontSize: 12, color: Color(0xFF166534), fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Template text field
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: TextField(
                    controller: _templateCtrl,
                    maxLines: 4,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'e.g. Hi {name}, looking forward to our call!',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.all(16),
                    ),
                    style: const TextStyle(fontSize: 14, fontFamily: 'Inter'),
                  ),
                ),

                const SizedBox(height: 16),

                // Live preview
                if (_templateCtrl.text.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF86EFAC).withOpacity(0.5)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('LIVE PREVIEW', style: TextStyle(fontSize: 9, color: Color(0xFF166534), fontWeight: FontWeight.w900, letterSpacing: 1.0)),
                        const SizedBox(height: 8),
                        Text(
                          _templateCtrl.text.replaceAll('{name}', _employeeName.isNotEmpty ? _employeeName : 'John'),
                          style: const TextStyle(fontSize: 13, color: Color(0xFF065F46), fontWeight: FontWeight.w500, fontFamily: 'Inter'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: Text('Cancel', style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold, fontFamily: 'Inter')),
              ),
              ElevatedButton(
                onPressed: () async {
                  await _saveTemplate();
                  if (context.mounted) Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3D7DFE),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: const Text('Save Format', style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Inter')),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const primaryBlue = Color(0xFF3D7DFE);
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),

          // --- ACCOUNT SECTION ---
          _buildSectionHeader('Account Settings'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Column(
              children: [
                _buildMenuTile(
                  icon: FontAwesomeIcons.whatsapp,
                  title: 'WhatsApp Format',
                  iconColor: const Color(0xFF25D366),
                  subtitle: 'Customize your auto-fill message',
                  onTap: _showWhatsAppTemplateDialog,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // --- SUPPORT SECTION ---
          _buildSectionHeader('Support & Legal'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Column(
              children: [
                _buildMenuTile(
                  icon: Icons.privacy_tip_rounded,
                  title: 'Privacy Policy',
                  iconColor: primaryBlue,
                  subtitle: 'How we handle your data',
                  onTap: _showPrivacyPolicy,
                ),
                _buildMenuTile(
                  icon: Icons.info_outline_rounded,
                  title: 'About DealVoice',
                  iconColor: Colors.amber.shade700,
                  subtitle: 'Version $_appVersion',
                  onTap: () {
                    UIUtils.showPremiumSnackBar(context, 'DealVoice v$_appVersion - Premium');
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // --- LOGOUT SECTION ---
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: _buildMenuTile(
              icon: Icons.logout_rounded,
              title: 'Log Out',
              textColor: Colors.red,
              iconColor: Colors.red,
              subtitle: 'Securely exit your account',
              onTap: _logout,
            ),
          ),

          const SizedBox(height: 20),

          // Version Info
          Center(
            child: Column(
              children: [
                Text(
                  'DealVoice for Business',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.black.withOpacity(0.3),
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 100), // Bottom nav padding
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E), // Premium black
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
            color: Colors.white,
            fontFamily: 'Inter',
          ),
        ),
      ),
    );
  }

  Widget _buildMenuTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    String? subtitle,
    Color textColor = const Color(0xFF1A1E2E),
    Color iconColor = const Color(0xFF3D7DFE),
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB).withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: iconColor, size: 22),
        ),
        title: Text(
          title,
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.bold,
            fontSize: 16,
            fontFamily: 'Inter',
          ),
        ),
        subtitle: subtitle != null
            ? Text(
                subtitle,
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 12,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w500,
                ),
              )
            : null,
        trailing: Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400, size: 20),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
    );
  }
}
