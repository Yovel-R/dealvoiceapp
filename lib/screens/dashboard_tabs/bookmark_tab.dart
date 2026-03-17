import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../utils/ui_utils.dart';
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
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

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
    final confirm = await UIUtils.showSmoothDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 30,
                offset: const Offset(0, 15),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header Section
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 30),
                decoration: BoxDecoration(
                  color: Colors.red.shade50.withOpacity(0.5),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                ),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.delete_sweep_rounded, color: Colors.red.shade700, size: 36),
                  ),
                ),
              ),
              
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
                child: Column(
                  children: [
                    const Text(
                      'Remove Bookmark?',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF111827),
                        fontFamily: 'Inter',
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Are you sure you want to remove this bookmark? This action cannot be undone.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade500,
                        fontFamily: 'Inter',
                        height: 1.5,
                      ),
                    ),
                    
                    const SizedBox(height: 32),
                    
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            child: Text(
                              'Keep it',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Inter',
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade600,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            child: const Text(
                              'Remove',
                              style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Inter'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirm == true) {
      await ApiService.deleteBookmark(id);
      if (mounted) {
        UIUtils.showPremiumSnackBar(context, '🗑️ Bookmark removed', isError: true);
        _fetchBookmarks();
      }
    }
  }

  String _formatTime(int? ms) {
    if (ms == null || ms == 0) return '';
    return DateFormat('hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(ms));
  }

  List<Map<String, dynamic>> get _filteredBookmarks {
    if (_searchQuery.isEmpty) return _bookmarks;
    final q = _searchQuery.toLowerCase();
    return _bookmarks.where((b) {
      final name = (b['contactName'] ?? '').toString().toLowerCase();
      final num  = (b['contactNumber'] ?? '').toString().toLowerCase();
      return name.contains(q) || num.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    const primaryBlue = Color(0xFF3D7DFE);
    return Column(
      children: [
        // Sticky Header: Search Bar
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          child: _buildSearchBar(),
        ),

        // Scrollable Content
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: primaryBlue))
              : _error.isNotEmpty
                  ? _buildErrorView()
                  : _filteredBookmarks.isEmpty
                      ? _buildEmptyView()
                      : RefreshIndicator(
                          onRefresh: _fetchBookmarks,
                          color: primaryBlue,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
                            itemCount: _filteredBookmarks.length,
                            itemBuilder: (ctx, i) => _bookmarkCard(_filteredBookmarks[i]),
                          ),
                        ),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _searchQuery = v),
        style: const TextStyle(fontSize: 14, fontFamily: 'Inter'),
        decoration: InputDecoration(
          hintText: 'Search bookmarks…',
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13, fontFamily: 'Inter'),
          prefixIcon: Icon(Icons.search, color: Colors.grey.shade400, size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  color: Colors.grey.shade400,
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
            const SizedBox(height: 12),
            Text(_error, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600, fontFamily: 'Inter')),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _fetchBookmarks, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bookmark_outline_rounded, size: 64, color: Colors.grey.shade200),
          const SizedBox(height: 16),
          Text(_searchQuery.isEmpty ? 'No bookmarks saved' : 'No matches found',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF111827), fontFamily: 'Inter')),
          const SizedBox(height: 6),
          Text(_searchQuery.isEmpty ? 'Tap 🔖 on any call to save it here.' : 'Try a different search term.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500, fontFamily: 'Inter')),
        ],
      ),
    );
  }

  Widget _bookmarkCard(Map<String, dynamic> b) {
    const primaryBlue = Color(0xFF3D7DFE);
    final name = (b['contactName'] ?? '').toString().isNotEmpty ? b['contactName'] as String : 'Unknown';
    final number = b['contactNumber'] as String? ?? '';
    final desc = b['description'] as String? ?? '';
    final ts = (b['callTimestamp'] as num?)?.toInt() ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: primaryBlue,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.bookmark_rounded, color: primaryBlue, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontFamily: 'Inter',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (ts != 0)
                      Text(
                        _formatTime(ts),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withOpacity(0.8),
                          fontFamily: 'Inter',
                        ),
                      ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => _deleteBookmark(b['_id'] as String),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close, size: 14, color: Colors.white),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      number,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.9),
                        fontWeight: FontWeight.w500,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ],
                ),
                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      desc,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.white,
                        height: 1.4,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Black bottom bar for actions (Floating Look)
          Container(
            margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _actionBtn(
                  icon: Icons.call_rounded,
                  color: Colors.white,
                  onTap: () async {
                    final uri = Uri(scheme: 'tel', path: number);
                    if (await canLaunchUrl(uri)) launchUrl(uri);
                  },
                ),
                _actionBtn(
                  icon: FontAwesomeIcons.whatsapp,
                  color: const Color(0xFF25D366),
                  onTap: () async {
                    final cleaned = number.replaceAll(RegExp(r'[^\d]'), '');
                    final message = _whatsappTemplate.replaceAll('{name}', name);
                    final uri = Uri.parse('https://wa.me/$cleaned?text=${Uri.encodeComponent(message)}');
                    if (await canLaunchUrl(uri)) launchUrl(uri, mode: LaunchMode.externalApplication);
                  },
                ),
                _actionBtn(
                  icon: Icons.copy_rounded,
                  color: Colors.grey.shade400,
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: number));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Number copied!'), duration: Duration(seconds: 1)),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn({required IconData icon, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Icon(icon, size: 22, color: color),
    );
  }
}
