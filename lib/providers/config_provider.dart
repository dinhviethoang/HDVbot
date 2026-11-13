import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:ai_assistant/models/xiaozhi_config.dart';

class ConfigProvider extends ChangeNotifier {
  List<XiaozhiConfig> _xiaozhiConfigs = [];
  bool _isLoaded = false;

  List<XiaozhiConfig> get xiaozhiConfigs => _xiaozhiConfigs;
  bool get isLoaded => _isLoaded;

  ConfigProvider() {
    loadConfigs();
  }

  Future<void> loadConfigs() async {
    final prefs = await SharedPreferences.getInstance();

    // Load Xiaozhi configs
    final xiaozhiConfigsJson = prefs.getStringList('xiaozhiConfigs') ?? [];
    _xiaozhiConfigs =
        xiaozhiConfigsJson
            .map((json) => XiaozhiConfig.fromJson(jsonDecode(json)))
            .toList();

    _isLoaded = true;
    notifyListeners();
  }

  Future<void> _saveConfigs() async {
    final prefs = await SharedPreferences.getInstance();

    // Save Xiaozhi configs
    final xiaozhiConfigsJson =
        _xiaozhiConfigs.map((config) => jsonEncode(config.toJson())).toList();
    await prefs.setStringList('xiaozhiConfigs', xiaozhiConfigsJson);
  }

  Future<void> addXiaozhiConfig(
    String name,
    String websocketUrl, {
    String? customMacAddress,
  }) async {
    final macAddress = customMacAddress ?? await _getDeviceMacAddress();

    final newConfig = XiaozhiConfig(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      websocketUrl: websocketUrl,
      macAddress: macAddress,
      token: 'test-token',
    );

    _xiaozhiConfigs.add(newConfig);
    await _saveConfigs();
    notifyListeners();
  }

  Future<void> updateXiaozhiConfig(XiaozhiConfig updatedConfig) async {
    final index = _xiaozhiConfigs.indexWhere(
      (config) => config.id == updatedConfig.id,
    );
    if (index != -1) {
      _xiaozhiConfigs[index] = updatedConfig;
      await _saveConfigs();
      notifyListeners();
    }
  }

  Future<void> deleteXiaozhiConfig(String id) async {
    _xiaozhiConfigs.removeWhere((config) => config.id == id);
    await _saveConfigs();
    notifyListeners();
  }

  Future<String> _getSimpleDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();
    String deviceId = '';

    try {
      try {
        final androidInfo = await deviceInfo.androidInfo;
        deviceId = androidInfo.id;
      } catch (_) {
        try {
          final iosInfo = await deviceInfo.iosInfo;
          deviceId = iosInfo.identifierForVendor ?? '';
        } catch (_) {
          final webInfo = await deviceInfo.webBrowserInfo;
          deviceId = webInfo.userAgent ?? '';
        }
      }
    } catch (e) {
      deviceId = DateTime.now().millisecondsSinceEpoch.toString();
    }

    if (deviceId.isEmpty) {
      deviceId = DateTime.now().millisecondsSinceEpoch.toString();
    }

    return deviceId;
  }

  String _generateMacFromDeviceId(String deviceId) {
    final bytes = utf8.encode(deviceId);
    final digest = md5.convert(bytes);
    final hash = digest.toString();

    final List<String> macParts = [];
    for (int i = 0; i < 6; i++) {
      macParts.add(hash.substring(i * 2, i * 2 + 2));
    }

    return macParts.join(':');
  }

  Future<String> _getDeviceMacAddress() async {
    final deviceId = await _getSimpleDeviceId();

    if (_isMacAddress(deviceId)) {
      return deviceId;
    }

    return _generateMacFromDeviceId(deviceId);
  }

  bool _isMacAddress(String str) {
    final macRegex = RegExp(r'^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$');
    return macRegex.hasMatch(str);
  }
}
