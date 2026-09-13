import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

class UsageTracker {
  static const String _keyDeviceId = 'device_uuid';
  static String? _cachedDeviceId;

  /// 기기 고유 ID 가져오기 (없으면 생성)
  static Future<String> getDeviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;

    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString(_keyDeviceId);

    if (deviceId == null) {
      deviceId = const Uuid().v4();
      await prefs.setString(_keyDeviceId, deviceId);
    }

    _cachedDeviceId = deviceId;
    return deviceId;
  }

  /// 쿼리 사용량 기록 (Firestore)
  static Future<void> logQuery() async {
    try {
      final deviceId = await getDeviceId();
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final platform = defaultTargetPlatform.name;

      // 지정된 데이터베이스 ID 사용
      final firestore = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'news-collector-history');
      final batch = firestore.batch();

      // 1. 기기별 일별 로그 (usage_logs/{deviceId}_{YYYY-MM-DD})
      final deviceLogRef = firestore.collection('usage_logs').doc('${deviceId}_$today');
      batch.set(deviceLogRef, {
        'deviceId': deviceId,
        'date': today,
        'platform': platform,
        'count': FieldValue.increment(1),
        'lastActive': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 2. 일별 전체 통계 (global_stats/{YYYY-MM-DD})
      final dailyGlobalRef = firestore.collection('global_stats').doc(today);
      batch.set(dailyGlobalRef, {
        'date': today,
        'dailyTotal': FieldValue.increment(1),
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 3. 전체 누적 통계 (global_stats/all_time)
      final allTimeRef = firestore.collection('global_stats').doc('all_time');
      batch.set(allTimeRef, {
        'totalQueries': FieldValue.increment(1),
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await batch.commit();
      debugPrint('Usage logged successfully for device: $deviceId');
    } catch (e) {
      debugPrint('Error logging usage: $e');
    }
  }
}
