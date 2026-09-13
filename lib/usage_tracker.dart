import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

enum UsageType { search, ai }

class UsageTracker {
  static const String _keyDeviceId = 'device_uuid';
  static String? _cachedDeviceId;

  static Future<String> getDeviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;
    try {
      final prefs = await SharedPreferences.getInstance();
      String? deviceId = prefs.getString(_keyDeviceId);
      if (deviceId == null) {
        deviceId = const Uuid().v4();
        await prefs.setString(_keyDeviceId, deviceId);
      }
      _cachedDeviceId = deviceId;
      return deviceId;
    } catch (e) {
      return 'unknown_device';
    }
  }

  static Future<void> logUsage(UsageType type) async {
    final typeStr = type == UsageType.search ? 'search' : 'ai';
    print('\n--- [UsageTracker] START ($typeStr) ---');
    
    try {
      final deviceId = await getDeviceId();
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final platform = defaultTargetPlatform.name;

      // (default) 데이터베이스를 사용하므로 표준 인스턴스 사용
      final firestore = FirebaseFirestore.instance;

      // 윈도우 연결 안정성 (캐시 비활성화)
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
        firestore.settings = const Settings(persistenceEnabled: false);
      }

      final countField = type == UsageType.search ? 'searchCount' : 'aiCount';
      final dailyField = type == UsageType.search ? 'dailySearch' : 'dailyAi';
      final totalField = type == UsageType.search ? 'totalSearch' : 'totalAi';

      final batch = firestore.batch();

      batch.set(firestore.collection('usage_logs').doc('${deviceId}_$today'), {
        'deviceId': deviceId,
        'date': today,
        'platform': platform,
        countField: FieldValue.increment(1),
        'lastActive': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      batch.set(firestore.collection('global_stats').doc(today), {
        'date': today,
        dailyField: FieldValue.increment(1),
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      batch.set(firestore.collection('global_stats').doc('all_time'), {
        totalField: FieldValue.increment(1),
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      print('STEP: Committing batch to Firestore...');
      await batch.commit().timeout(const Duration(seconds: 15));
      
      print('✅ [UsageTracker] SUCCESS: Logged to Firestore');
    } catch (e) {
      print('❌ [UsageTracker] FAILED: $e');
    }
    print('--- [UsageTracker] END ---\n');
  }
}
