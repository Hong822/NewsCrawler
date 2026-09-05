import 'dart:io';
import 'package:flutter/foundation.dart';

class AdHelper {
  static String get bannerAdUnitId {
    if (kIsWeb) return "";
    if (Platform.isAndroid) {
      return 'ca-app-pub-8302020192046846/4181662432';
    } else if (Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/2934735716';
    } else {
      return "";
    }
  }

  static String get interstitialAdUnitId {
    if (kIsWeb) return "";
    if (Platform.isAndroid) {
      return 'ca-app-pub-8302020192046846/5089045227';
    } else if (Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/4411468910';
    } else {
      return "";
    }
  }

  static String get rewardedAdUnitId {
    if (kIsWeb) return "";
    if (Platform.isAndroid) {
      return 'ca-app-pub-8302020192046846/5369563470';
    } else if (Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/1712485313';
    } else {
      return "";
    }
  }
}
