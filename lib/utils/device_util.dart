import 'dart:io';
import 'dart:math' as math;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Thiết bị & định danh máy (MAC & Client-Id)
class DeviceUtil {
  static const String TAG = "DeviceUtil";
  static const String DEVICE_ID_KEY = "device_id";
  static const String MAC_KEY = "hdvbot_mac";
  static const String CLIENT_ID_KEY = "hdvbot_client_id";

  /// Kiểm tra chuỗi có đúng định dạng địa chỉ MAC 6 byte (aa:bb:cc:dd:ee:ff)
  static bool isValidMac(String? str) {
    if (str == null || str.trim().isEmpty) return false;
    final macRegex = RegExp(r'^([0-9a-fA-F]{2}[:-]){5}([0-9a-fA-F]{2})$');
    return macRegex.hasMatch(str.trim());
  }

  /// Tạo 1 MAC ngẫu nhiên dạng "02:xx:xx:xx:xx:xx" (byte đầu 02 = locally administered)
  static String generateRandomMac() {
    final rand = math.Random();
    final bytes = [
      0x02,
      rand.nextInt(256),
      rand.nextInt(256),
      rand.nextInt(256),
      rand.nextInt(256),
      rand.nextInt(256),
    ];
    return bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(':')
        .toLowerCase();
  }

  /// Lấy địa chỉ MAC thiết bị, lưu vĩnh viễn trong SharedPreferences (key "hdvbot_mac")
  static Future<String> getDeviceMac() async {
    final prefs = await SharedPreferences.getInstance();
    String? mac = prefs.getString(MAC_KEY);
    if (mac != null && isValidMac(mac)) {
      return mac.toLowerCase();
    }
    mac = generateRandomMac();
    await prefs.setString(MAC_KEY, mac);
    print('$TAG: Đã khởi tạo và lưu địa chỉ MAC vĩnh viễn: $mac');
    return mac;
  }

  /// Lấy Client-Id UUID v4, lưu vĩnh viễn trong SharedPreferences (key "hdvbot_client_id")
  static Future<String> getClientId() async {
    final prefs = await SharedPreferences.getInstance();
    String? clientId = prefs.getString(CLIENT_ID_KEY);
    if (clientId != null && clientId.isNotEmpty) {
      return clientId;
    }
    clientId = const Uuid().v4();
    await prefs.setString(CLIENT_ID_KEY, clientId);
    print('$TAG: Đã khởi tạo và lưu Client-Id UUID v4: $clientId');
    return clientId;
  }

  /// Lấy ID thiết bị (trả về MAC chuẩn cho server Xiaozhi)
  static Future<String> getDeviceId() async {
    return await getDeviceMac();
  }

  /// 格式化设备名称，移除特殊字符并规范化格式
  static String _formatDeviceName(String name) {
    if (name.isEmpty) return 'unknown_device';

    // 1. 转换为小写
    String formatted = name.toLowerCase();

    // 2. 替换空格和特殊字符为下划线
    formatted = formatted.replaceAll(RegExp(r'[^a-z0-9]'), '_');

    // 3. 替换连续的下划线为单个下划线
    formatted = formatted.replaceAll(RegExp(r'_+'), '_');

    // 4. 移除开头和结尾的下划线
    formatted = formatted.replaceAll(RegExp(r'^_+|_+$'), '');

    // 5. 如果处理后为空，返回默认值
    if (formatted.isEmpty) return 'unknown_device';

    // 6. 限制长度（可选）
    if (formatted.length > 32) {
      formatted = formatted.substring(0, 32);
      // 确保不以下划线结尾
      formatted = formatted.replaceAll(RegExp(r'_+$'), '');
    }

    return formatted;
  }

  /// 获取设备型号
  static Future<String> getDeviceModel() async {
    final deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      return '${androidInfo.manufacturer} ${androidInfo.model}';
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      return iosInfo.model;
    } else {
      return 'Unknown';
    }
  }

  /// 获取操作系统版本
  static Future<String> getOsVersion() async {
    final deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      return 'Android ${androidInfo.version.release}';
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      return 'iOS ${iosInfo.systemVersion}';
    } else {
      return 'Unknown OS';
    }
  }

  // 生成唯一的会话ID
  static String generateConversationId() {
    return const Uuid().v4();
  }
}
