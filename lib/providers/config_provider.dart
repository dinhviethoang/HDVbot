import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_assistant/models/xiaozhi_config.dart';
import 'package:ai_assistant/utils/device_util.dart';

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

    final defaultMac = await DeviceUtil.getDeviceMac();
    bool needSave = false;

    // Tự tạo cấu hình mặc định nếu danh sách trống (lần đầu mở app)
    if (_xiaozhiConfigs.isEmpty) {
      _xiaozhiConfigs.add(
        XiaozhiConfig(
          id: 'default_hdvbot',
          name: 'HDVbot',
          otaUrl: XiaozhiConfig.defaultOtaUrl,
          websocketUrl: '',
          macAddress: defaultMac,
          token: 'test-token',
        ),
      );
      needSave = true;
    } else {
      // Mọi cấu hình có macAddress không đúng định dạng MAC thì tự thay bằng MAC chuẩn
      for (int i = 0; i < _xiaozhiConfigs.length; i++) {
        final config = _xiaozhiConfigs[i];
        if (!DeviceUtil.isValidMac(config.macAddress)) {
          _xiaozhiConfigs[i] = config.copyWith(macAddress: defaultMac);
          needSave = true;
        }
      }
    }

    if (needSave) {
      await _saveConfigs();
    }

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
    String? otaUrl,
    String? token,
  }) async {
    final defaultMac = await DeviceUtil.getDeviceMac();
    final macAddress =
        (customMacAddress != null && DeviceUtil.isValidMac(customMacAddress))
            ? customMacAddress.toLowerCase()
            : defaultMac;

    final newConfig = XiaozhiConfig(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      otaUrl: (otaUrl != null && otaUrl.isNotEmpty)
          ? otaUrl
          : XiaozhiConfig.defaultOtaUrl,
      websocketUrl: websocketUrl,
      macAddress: macAddress,
      token: (token != null && token.isNotEmpty) ? token : 'test-token',
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

  Future<String> _getDeviceMacAddress() async {
    return await DeviceUtil.getDeviceMac();
  }
}
