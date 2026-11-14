import 'dart:collection';
import 'package:flutter/foundation.dart';

/// Quản lý nhật ký ứng dụng trong bộ nhớ (vòng tròn tối đa 400 dòng)
class AppLog {
  static const int maxLines = 400;
  static final ListQueue<String> _logs = ListQueue<String>(maxLines);
  static final ValueNotifier<int> logNotifier = ValueNotifier<int>(0);

  /// Thêm dòng nhật ký với định dạng HH:mm:ss.SSS
  static void add(String message) {
    final now = DateTime.now();
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    final s = now.second.toString().padLeft(2, '0');
    final ms = now.millisecond.toString().padLeft(3, '0');
    final line = '$h:$m:$s.$ms $message';

    if (_logs.length >= maxLines) {
      _logs.removeFirst();
    }
    _logs.addLast(line);

    debugPrint(line);
    logNotifier.value++;
  }

  /// Lấy danh sách dòng nhật ký (không thể sửa trực tiếp)
  static List<String> get logs => List<String>.unmodifiable(_logs);

  /// Lấy toàn bộ nhật ký dưới dạng văn bản
  static String getAllText() => _logs.join('\n');

  /// Xóa toàn bộ nhật ký
  static void clear() {
    _logs.clear();
    logNotifier.value++;
  }
}
