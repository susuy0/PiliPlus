import 'package:get/get.dart';

/// The same official checkout used by the UP charging leaderboard.
abstract final class ChargeUtils {
  static Future<void> open(int mid) async {
    if (mid <= 0) return;
    await Get.toNamed(
      '/webview',
      parameters: {
        'url': 'https://member.bilibili.com/mall/upower-pay?mid=$mid&oid=$mid',
      },
    );
  }
}
