import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class ApiService {
  static String get baseUrl {
    if (Platform.isAndroid) {
      // return 'http://10.139.243.125:4000/api';
      return 'https://softrate-call.onrender.com/api';
    }
    return 'https://softrate-call.onrender.com/api';
    // return 'http://10.139.243.125:4000/api';
  }

  // ── Employee Login ────────────────────────────────────────
  static Future<Map<String, dynamic>> loginEmployee(
      String companyCode, String mobile) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/employees/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'companyCode': companyCode, 'mobile': mobile}),
      );
      
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body);
      } else {
        final body = jsonDecode(response.body);
        return {'success': false, 'message': body['message'] ?? 'Server error: ${response.statusCode}'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Failed to connect to server: $e'};
    }
  }

  // ── Update employee code (optional, set by employee after login) ──
  static Future<Map<String, dynamic>> updateEmployeeCode({
    required String employeeId,
    required String employeeCode,
  }) async {
    try {
      final response = await http.patch(
        Uri.parse('$baseUrl/employees/$employeeId/code'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'employeeCode': employeeCode}),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body);
      } else {
        final body = jsonDecode(response.body);
        return {'success': false, 'message': body['message'] ?? 'Update failed: ${response.statusCode}'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Failed to update code: $e'};
    }
  }

  // ── Sync today's call log to backend ─────────────────────
  static Future<Map<String, dynamic>> syncCallLogs({
    required String companyCode,
    required String phone,
    required String date,
    required int incoming,
    required int outgoing,
    required int missed,
    required int rejected,
    required int incomingDuration,
    required int outgoingDuration,
    required int totalDuration,
    required List<Map<String, dynamic>> calls,
    String deviceModel = '',
    String appVersion = '1.0.0',
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/calllogs/sync'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'companyCode': companyCode,
          'phone': phone,
          'date': date,
          'incoming': incoming,
          'outgoing': outgoing,
          'missed': missed,
          'rejected': rejected,
          'incomingDuration': incomingDuration,
          'outgoingDuration': outgoingDuration,
          'totalDuration': totalDuration,
          'calls': calls,
          'deviceModel': deviceModel,
          'appVersion': appVersion,
        }),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body);
      } else {
        final body = jsonDecode(response.body);
        return {'success': false, 'message': body['message'] ?? 'Sync failed: ${response.statusCode}'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Sync failed: $e'};
    }
  }

  // ── Bookmarks ─────────────────────────────────────────────
  static Future<Map<String, dynamic>> addBookmark({
    required String companyCode,
    required String employeePhone,
    required String contactNumber,
    String contactName = '',
    String description = '',
    int callTimestamp = 0,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/bookmarks'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'companyCode': companyCode,
          'employeePhone': employeePhone,
          'contactNumber': contactNumber,
          'contactName': contactName,
          'description': description,
          'callTimestamp': callTimestamp,
        }),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body);
      } else {
        final body = jsonDecode(response.body);
        return {'success': false, 'message': body['message'] ?? 'Failed: ${response.statusCode}'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Failed to add bookmark: $e'};
    }
  }

  static Future<Map<String, dynamic>> getBookmarks({
    required String companyCode,
    required String phone,
  }) async {
    try {
      // Use the production URL correctly
      final uri = Uri.https(
        'softrate-call.onrender.com',
        '/api/bookmarks',
        {'companyCode': companyCode, 'phone': phone},
      );
      final response = await http.get(uri, headers: {'Content-Type': 'application/json'});
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body);
      } else {
        final body = jsonDecode(response.body);
        return {'success': false, 'message': body['message'] ?? 'Fetch failed: ${response.statusCode}'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Failed to fetch bookmarks: $e'};
    }
  }

  static Future<Map<String, dynamic>> deleteBookmark(String id) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/bookmarks/$id'),
        headers: {'Content-Type': 'application/json'},
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body);
      } else {
        final body = jsonDecode(response.body);
        return {'success': false, 'message': body['message'] ?? 'Delete failed: ${response.statusCode}'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Failed to delete bookmark: $e'};
    }
  }
}
