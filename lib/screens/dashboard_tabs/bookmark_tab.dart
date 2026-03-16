import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../services/api_service.dart';

class BookmarkTab extends StatefulWidget {
  const BookmarkTab({super.key});
  @override
  State<BookmarkTab> createState() => _BookmarkTabState();
}

class _BookmarkTabState extends State<BookmarkTab> {
  String _companyCode = '';
  String _mobileNumber = '';
  String _whatsappTemplate = 'Hi {name}!';
  List<Map<String, dynamic>> _bookmarks = [];
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _loadAndFetch();
  }

  Future<void> _loadAndFetch() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _companyCode = prefs.getString('companyCode') ?? '';
      _mobileNumber = prefs.getString('mobileNumber') ?? '';
      _whatsappTemplate = prefs.getString('whatsappTemplate') ?? 'Hi {name}!';
    });
    await _fetchBookmarks();
  }

  Future<void> _fetchBookmarks() async {
    if (_companyCode.isEmpty || _mobileNumber.isEmpty) {
      setState(() { _loading = false; _error = 'Not logged in. (code: "$_companyCode", phone: "$_mobileNumber")'; });
      return;
    }
    setState(() { _loading = true; _error = ''; });
    final res = await ApiService.getBookmarks(companyCode: _companyCode, phone: _mobileNumber);
    if (!mounted) return;
    if (res['success'] == true) {
      setState(() {
        _bookmarks = List<Map<String, dynamic>>.from(res['bookmarks'] ?? []);
        _loading = false;
      });
    } else {
      setState(() { _loading = false; _error = res['message'] ?? 'Failed to load bookmarks.'; });
    }
  }

  Future<void> _deleteBookmark(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove Bookmark'),
        content: const Text('Remove this bookmark?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await ApiService.deleteBookmark(id);
      _fetchBookmarks();
    }
  }

  String _formatTime(int? ms) {
    if (ms == null || ms == 0) return '';
    return DateFormat('dd MMM, hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(ms));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Content (Header is now shared in DashboardScreen)
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: Colors.indigo))
              : _error.isNotEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
                            const SizedBox(height: 12),
                            Text(_error, textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey.shade600)),
                            const SizedBox(height: 16),
                            ElevatedButton(onPressed: _fetchBookmarks, child: const Text('Retry')),
                          ],
                        ),
                      ),
                    )
                  : _bookmarks.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.bookmark_border, size: 64, color: Colors.grey.shade300),
                              const SizedBox(height: 12),
                              Text('No bookmarks yet.',
                                  style: TextStyle(fontSize: 16, color: Colors.grey.shade400)),
                              const SizedBox(height: 6),
                              Text('Tap 🔖 on a call card to save one.',
                                  style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _fetchBookmarks,
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                            itemCount: _bookmarks.length,
                            itemBuilder: (ctx, i) {
                              final b = _bookmarks[i];
                              final name = (b['contactName'] ?? '').toString().isNotEmpty
                                  ? b['contactName'] as String
                                  : 'Unknown';
                              final number = b['contactNumber'] as String? ?? '';
                              final desc = b['description'] as String? ?? '';
                              final ts = (b['callTimestamp'] as num?)?.toInt() ?? 0;

                              return Container(
                                margin: const EdgeInsets.only(bottom: 14),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(18),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.06),
                                      blurRadius: 10,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Top row: name + delete
                                      Row(
                                        children: [
                                          Container(
                                            width: 44, height: 44,
                                            decoration: BoxDecoration(
                                              color: Colors.indigo.shade50,
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Icon(Icons.bookmark, color: Colors.indigo.shade400, size: 20),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(name,
                                                    style: const TextStyle(fontWeight: FontWeight.bold,
                                                        fontSize: 15, color: Color(0xFF1A1E2E))),
                                                Text(number,
                                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                                              ],
                                            ),
                                          ),
                                          if (ts != 0)
                                            Text(_formatTime(ts),
                                                style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                                          const SizedBox(width: 8),
                                          GestureDetector(
                                            onTap: () => _deleteBookmark(b['_id'] as String),
                                            child: Icon(Icons.close, size: 18, color: Colors.grey.shade400),
                                          ),
                                        ],
                                      ),
                                      // Description
                                      if (desc.isNotEmpty) ...[
                                        const SizedBox(height: 10),
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          decoration: BoxDecoration(
                                            color: Colors.indigo.shade50,
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Text(desc,
                                              style: TextStyle(fontSize: 13, color: Colors.indigo.shade700)),
                                        ),
                                      ],
                                      const SizedBox(height: 12),
                                      // Action row: call, whatsapp, copy
                                      Row(
                                        children: [
                                          _actionBtn(
                                            icon: Icons.call,
                                            color: Colors.indigo.shade400,
                                            onTap: () async {
                                              final uri = Uri(scheme: 'tel', path: number);
                                              if (await canLaunchUrl(uri)) launchUrl(uri);
                                            },
                                          ),
                                          const SizedBox(width: 16),
                                          GestureDetector(
                                            onTap: () async {
                                              final cleaned = number.replaceAll(RegExp(r'[^\d]'), '');
                                              final message = _whatsappTemplate.replaceAll('{name}', name);
                                              final uri = Uri.parse(
                                                'https://wa.me/$cleaned?text=${Uri.encodeComponent(message)}',
                                              );
                                              if (await canLaunchUrl(uri)) {
                                                launchUrl(uri, mode: LaunchMode.externalApplication);
                                              }
                                            },
                                            child: Container(
                                              width: 26, height: 26,
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF25D366),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: const Center(
                                                child: FaIcon(FontAwesomeIcons.whatsapp, color: Colors.white, size: 15),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          _actionBtn(
                                            icon: Icons.copy,
                                            color: Colors.grey.shade600,
                                            onTap: () {
                                              Clipboard.setData(ClipboardData(text: number));
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text('Number copied!'),
                                                    duration: Duration(seconds: 1)),
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
        ),
      ],
    );
  }

  Widget _actionBtn({required IconData icon, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Icon(icon, size: 22, color: color),
    );
  }
}
