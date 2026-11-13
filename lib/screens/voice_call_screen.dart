import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:ai_assistant/models/conversation.dart';
import 'package:ai_assistant/models/message.dart';
import 'package:ai_assistant/models/xiaozhi_config.dart';
import 'package:ai_assistant/providers/conversation_provider.dart';
import 'package:ai_assistant/providers/config_provider.dart';
import 'package:ai_assistant/services/xiaozhi_service.dart';
import 'package:ai_assistant/services/xiaozhi_ota_service.dart';
import 'package:ai_assistant/utils/app_theme.dart';
import 'package:ai_assistant/utils/device_util.dart';
import 'package:ai_assistant/widgets/robot_eyes.dart';

/// Màn hình gọi thoại toàn màn hình phong cách mặt robot HDVbot
/// Tối ưu đặc biệt cho Samsung J2 Pro (540x960, RAM 1.5GB)
class VoiceCallScreen extends StatefulWidget {
  final Conversation conversation;
  final XiaozhiConfig xiaozhiConfig;

  const VoiceCallScreen({
    super.key,
    required this.conversation,
    required this.xiaozhiConfig,
  });

  @override
  State<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends State<VoiceCallScreen>
    with SingleTickerProviderStateMixin {
  XiaozhiService? _xiaozhiService;
  final XiaozhiOtaService _otaService = XiaozhiOtaService();
  OtaCancellationToken? _otaCancelToken;
  late XiaozhiConfig _currentConfig;

  // Trạng thái kích hoạt OTA
  bool _showActivationOverlay = false;
  bool _isOtaConnecting = false;
  String? _activationCode;
  String _otaStatus = 'Đang kết nối máy chủ...';
  String? _otaError;

  bool _isConnected = false;
  bool _isSpeaking = false; // Micro máy khách đang thu âm
  bool _isRobotSpeaking = false; // Robot đang phát giọng TTS
  bool _isThinking = false; // Robot đang xử lý/suy nghĩ
  bool _hasError = false; // Có lỗi kết nối / mic
  String _statusText = 'Đang kết nối...';
  String _latestSubtitle = ''; // Phụ đề câu nói gần nhất
  Timer? _callTimer;
  Duration _callDuration = Duration.zero;
  bool _serverReady = false;

  late AnimationController _animationController;
  final List<double> _audioLevels = List.filled(24, 0.05);
  Timer? _audioVisualizerTimer;

  @override
  void initState() {
    super.initState();
    _currentConfig = widget.xiaozhiConfig;

    // Thiết lập thanh trạng thái trong suốt nền tối
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: AppTheme.backgroundColor,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarColor: AppTheme.backgroundColor,
          systemNavigationBarIconBrightness: Brightness.light,
          systemNavigationBarDividerColor: Colors.transparent,
        ),
      );
    });

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    // Bắt đầu quy trình kích hoạt OTA và kết nối
    _startActivationFlow();
    _startAudioVisualizer();
  }

  /// Khởi chạy quy trình kích hoạt OTA
  Future<void> _startActivationFlow() async {
    _otaCancelToken?.cancel();
    final cancelToken = OtaCancellationToken();
    _otaCancelToken = cancelToken;

    setState(() {
      _showActivationOverlay = true;
      _isOtaConnecting = true;
      _activationCode = null;
      _otaError = null;
      _otaStatus = 'Đang kết nối máy chủ...';
    });

    try {
      final mac = DeviceUtil.isValidMac(_currentConfig.macAddress)
          ? _currentConfig.macAddress
          : await DeviceUtil.getDeviceMac();
      final clientId = await DeviceUtil.getClientId();

      if (_currentConfig.macAddress != mac) {
        _currentConfig = _currentConfig.copyWith(macAddress: mac);
      }

      final result = await _otaService.ensureActivated(
        otaUrl: _currentConfig.otaUrl,
        mac: mac,
        clientId: clientId,
        onActivationCode: (code) {
          if (!mounted || cancelToken.isCancelled) return;
          setState(() {
            _activationCode = code;
            _isOtaConnecting = false;
            _otaStatus = 'Đang chờ kích hoạt...';
          });
        },
        onStatusChange: (status) {
          if (!mounted || cancelToken.isCancelled) return;
          setState(() {
            _otaStatus = status;
          });
        },
        cancelToken: cancelToken,
      );

      if (!mounted || cancelToken.isCancelled) return;

      // Cập nhật cấu hình lưu trữ
      final updatedConfig = _currentConfig.copyWith(
        websocketUrl: result.websocketUrl,
        token: result.websocketToken,
        macAddress: mac,
      );
      _currentConfig = updatedConfig;

      await Provider.of<ConfigProvider>(
        context,
        listen: false,
      ).updateXiaozhiConfig(updatedConfig);

      if (!mounted || cancelToken.isCancelled) return;

      setState(() {
        _showActivationOverlay = false;
        _isOtaConnecting = false;
        _otaError = null;
      });

      // Tạo và kết nối XiaozhiService với websocket url & token từ OTA
      _xiaozhiService = XiaozhiService(
        websocketUrl: updatedConfig.websocketUrl,
        macAddress: updatedConfig.macAddress,
        clientId: clientId,
        token: updatedConfig.token,
        sessionId: widget.conversation.id,
      );

      _xiaozhiService!.setMessageListener(_handleServerMessage);
      _xiaozhiService!.addListener(_handleServiceEvent);

      _connectToVoiceService();
    } catch (e) {
      if (!mounted || cancelToken.isCancelled) return;
      print('Lỗi kích hoạt OTA VoiceCallScreen: $e');
      setState(() {
        _isOtaConnecting = false;
        _otaError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _handleServerMessage(dynamic message) {
    if (!mounted) return;
    if (message is Map<String, dynamic>) {
      final String type = message['type'] ?? '';

      if (type == 'hello') {
        setState(() {
          _serverReady = true;
          _isConnected = true;
          _hasError = false;
          _statusText = 'Đã kết nối máy chủ';
        });

        // Tự động bắt đầu thu âm sau khi máy chủ sẵn sàng
        if (_isConnected && !_isSpeaking) {
          Future.delayed(const Duration(milliseconds: 800), () {
            if (mounted && _isConnected && !_isSpeaking) {
              _startSpeaking();
            }
          });
        }
      } else if (type == 'tts') {
        final String state = message['state'] ?? '';
        final String text = message['text'] ?? '';
        if (state == 'sentence_start') {
          setState(() {
            _isRobotSpeaking = true;
            _isThinking = false;
            _statusText = 'HDVbot đang nói...';
            if (text.isNotEmpty) {
              _latestSubtitle = 'HDVbot: $text';
            }
          });
        } else if (state == 'sentence_end' || state == 'stop') {
          setState(() {
            _isRobotSpeaking = false;
            if (_isSpeaking) {
              _statusText = 'Đang lắng nghe...';
            } else {
              _statusText = 'Sẵn sàng';
            }
          });
        }
      } else if (type == 'stt') {
        final String text = message['text'] ?? '';
        if (text.isNotEmpty) {
          setState(() {
            _latestSubtitle = 'Bạn: $text';
            _isThinking = true;
            _statusText = 'Đang suy nghĩ...';
          });
        }
      } else if (type == 'llm') {
        setState(() {
          _isThinking = true;
          _statusText = 'Đang xử lý...';
        });
      }
    }
  }

  void _handleServiceEvent(XiaozhiServiceEvent event) {
    if (!mounted) return;
    switch (event.type) {
      case XiaozhiServiceEventType.userMessage:
        setState(() {
          if (event.data is String && (event.data as String).isNotEmpty) {
            _latestSubtitle = 'Bạn: ${event.data}';
          }
          _isThinking = true;
          _statusText = 'Đang suy nghĩ...';
        });
        break;

      case XiaozhiServiceEventType.textMessage:
        setState(() {
          if (event.data is String && (event.data as String).isNotEmpty) {
            _latestSubtitle = 'HDVbot: ${event.data}';
          }
          _isRobotSpeaking = true;
          _isThinking = false;
          _statusText = 'HDVbot đang nói...';
        });
        break;

      case XiaozhiServiceEventType.error:
        setState(() {
          _hasError = true;
          _statusText = 'Lỗi kết nối';
        });
        break;

      case XiaozhiServiceEventType.disconnected:
        setState(() {
          _isConnected = false;
          _statusText = 'Mất kết nối máy chủ';
        });
        break;

      default:
        break;
    }
  }

  @override
  void dispose() {
    _otaCancelToken?.cancel();
    _xiaozhiService?.removeListener(_handleServiceEvent);
    _xiaozhiService?.switchToChatMode();
    _callTimer?.cancel();
    _audioVisualizerTimer?.cancel();
    _animationController.dispose();
    _xiaozhiService?.stopPlayback();
    super.dispose();
  }

  void _connectToVoiceService() async {
    if (_xiaozhiService == null) return;

    setState(() {
      _statusText = 'Đang chuẩn bị...';
      _hasError = false;
    });

    try {
      await _xiaozhiService!.switchToVoiceCallMode();
      await _xiaozhiService!.connectVoiceCall();

      setState(() {
        _statusText = 'Đã kết nối';
        _isConnected = true;
        _hasError = false;
      });

      if (mounted) {
        _showCustomSnackbar(
          message: 'Đã vào chế độ gọi thoại HDVbot',
          icon: Icons.check_circle_outline,
          iconColor: AppTheme.accentColor,
        );
      }

      _startCallTimer();

      // Ghi nhận tin nhắn vào lịch sử trò chuyện
      Provider.of<ConversationProvider>(context, listen: false).addMessage(
        conversationId: widget.conversation.id,
        role: MessageRole.assistant,
        content: 'Cuộc gọi thoại đã bắt đầu',
      );

      _startSpeaking();
    } catch (e) {
      setState(() {
        _statusText = 'Kết nối thất bại';
        _isConnected = false;
        _hasError = true;
      });

      if (mounted) {
        _showCustomSnackbar(
          message: 'Lỗi vào chế độ thoại: $e',
          icon: Icons.error_outline,
          iconColor: AppTheme.errorColor,
        );
      }
    }
  }

  void _startCallTimer() {
    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _callDuration = Duration(seconds: timer.tick);
        });
      }
    });
  }

  void _startAudioVisualizer() {
    _audioVisualizerTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (timer) {
        if (_isConnected && mounted) {
          setState(() {
            for (int i = 0; i < _audioLevels.length - 1; i++) {
              _audioLevels[i] = _audioLevels[i + 1];
            }

            if (_isRobotSpeaking) {
              // Nhịp theo giọng robot đang nói
              _audioLevels[_audioLevels.length - 1] =
                  0.15 + (0.75 * (0.5 + 0.5 * _animationController.value));
            } else if (_isSpeaking) {
              // Nhịp theo micro người dùng
              _audioLevels[_audioLevels.length - 1] =
                  0.10 + (0.60 * (0.5 + 0.5 * _animationController.value));
            } else {
              _audioLevels[_audioLevels.length - 1] = 0.05;
            }
          });
        }
      },
    );
  }

  // Bắt đầu thu âm micro
  void _startSpeaking() {
    if (!_isSpeaking) {
      setState(() {
        _isSpeaking = true;
        if (!_isRobotSpeaking && !_isThinking) {
          _statusText = 'Đang lắng nghe...';
        }
      });

      try {
        _xiaozhiService
            ?.startListeningCall()
            .then((_) {
              if (mounted) {
                _showCustomSnackbar(
                  message: 'Micro đang lắng nghe...',
                  icon: Icons.mic,
                  iconColor: AppTheme.accentColor,
                );
              }
            })
            .catchError((e) {
              if (mounted) {
                setState(() {
                  _isSpeaking = false;
                  _hasError = true;
                });
                _showCustomSnackbar(
                  message: 'Không thể mở micro: $e',
                  icon: Icons.error_outline,
                  iconColor: AppTheme.errorColor,
                );
              }
            });
      } catch (e) {
        setState(() {
          _isSpeaking = false;
          _hasError = true;
        });
        if (mounted) {
          _showCustomSnackbar(
            message: 'Không thể mở micro: $e',
            icon: Icons.error_outline,
            iconColor: AppTheme.errorColor,
          );
        }
      }
    }
  }

  // Gửi lệnh ngắt lời robot
  void _sendAbortMessage() {
    _xiaozhiService?.sendAbortMessage();
    setState(() {
      _isRobotSpeaking = false;
      _isThinking = false;
      if (_isConnected) {
        _statusText = 'Đang lắng nghe...';
      }
    });

    if (mounted) {
      _showCustomSnackbar(
        message: 'Đã gửi tín hiệu ngắt lời',
        icon: Icons.pan_tool_rounded,
        iconColor: Colors.orangeAccent,
      );
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  /// Xác định trạng thái thật của mắt robot từ trạng thái cuộc gọi
  RobotEyeState _resolveRobotEyeState() {
    if (_showActivationOverlay) {
      return RobotEyeState.idle;
    }
    if (!_isConnected || _hasError) {
      return RobotEyeState.error;
    }
    if (_isRobotSpeaking) {
      return RobotEyeState.speaking;
    }
    if (_isThinking) {
      return RobotEyeState.thinking;
    }
    if (_isSpeaking) {
      return RobotEyeState.listening;
    }
    return RobotEyeState.idle;
  }

  @override
  Widget build(BuildContext context) {
    final robotEyeState = _resolveRobotEyeState();
    final double currentVolume =
        _audioLevels.isNotEmpty ? _audioLevels.last : 0.0;

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                // Thanh tiêu đề HUD nhỏ gọn
                _buildTopHudBar(),

                // Phần lớn màn hình: Mắt robot Mecha HUD
                Expanded(
                  flex: 6,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: RobotEyes(
                        state: robotEyeState,
                        volume: currentVolume,
                        height: 220,
                      ),
                    ),
                  ),
                ),

                // Dòng trạng thái cuộc gọi HUD
                _buildStatusBadge(robotEyeState),
                const SizedBox(height: 10),

                // Phụ đề câu nói gần nhất (người dùng hoặc robot)
                _buildSubtitlePanel(),
                const SizedBox(height: 12),

                // Thanh hiển thị dải âm thanh nhịp điệu HUD
                _buildAudioVisualizer(),
                const SizedBox(height: 16),

                // Các nút điều khiển cuộc gọi
                _buildBottomControls(),
                const SizedBox(height: 14),
              ],
            ),
          ),
          if (_showActivationOverlay) _buildActivationOverlay(),
        ],
      ),
    );
  }

  /// Lớp phủ kích hoạt thiết bị hiển thị mã 6 số phong cách Cyber HUD Cyan
  Widget _buildActivationOverlay() {
    return Positioned.fill(
      child: Container(
        color: AppTheme.backgroundColor.withOpacity(0.96),
        child: SafeArea(
          child: Column(
            children: [
              // Thanh tiêu đề với nút quay lại
              Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8.0, top: 4.0),
                  child: IconButton(
                    icon: const Icon(
                      Icons.arrow_back,
                      color: AppTheme.primaryColor,
                      size: 26,
                    ),
                    onPressed: () {
                      _otaCancelToken?.cancel();
                      Navigator.pop(context);
                    },
                  ),
                ),
              ),

              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24.0,
                        vertical: 28.0,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceColor,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppTheme.primaryColor.withOpacity(0.4),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryColor.withOpacity(0.15),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Tiêu đề
                          const Text(
                            'KÍCH HOẠT THIẾT BỊ',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2.0,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                          const SizedBox(height: 20),

                          if (_otaError != null) ...[
                            // Trạng thái LỖI
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppTheme.errorColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppTheme.errorColor.withOpacity(0.4),
                                ),
                              ),
                              child: Column(
                                children: [
                                  const Icon(
                                    Icons.error_outline_rounded,
                                    color: AppTheme.errorColor,
                                    size: 40,
                                  ),
                                  const SizedBox(height: 10),
                                  const Text(
                                    'Lỗi kết nối máy chủ',
                                    style: TextStyle(
                                      color: AppTheme.errorColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  SelectableText(
                                    _otaError!,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: AppTheme.textColor,
                                      fontSize: 13,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            ElevatedButton.icon(
                              onPressed: _startActivationFlow,
                              icon: const Icon(Icons.refresh, size: 20),
                              label: const Text(
                                'Thử lại',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryColor,
                                foregroundColor: AppTheme.backgroundColor,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 28,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ] else if (_isOtaConnecting && _activationCode == null) ...[
                            // Trạng thái ĐANG GỌI OTA
                            const SizedBox(height: 20),
                            const SizedBox(
                              width: 48,
                              height: 48,
                              child: CircularProgressIndicator(
                                strokeWidth: 3.5,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  AppTheme.primaryColor,
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            const Text(
                              'Đang kết nối máy chủ...',
                              style: TextStyle(
                                fontSize: 16,
                                color: AppTheme.textColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _otaStatus.isNotEmpty
                                  ? _otaStatus
                                  : 'Đang gửi yêu cầu kiểm tra OTA',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.secondaryTextColor,
                              ),
                            ),
                            const SizedBox(height: 20),
                          ] else if (_activationCode != null) ...[
                            // Trạng thái HIỂN THỊ MÃ KÍCH HOẠT
                            const Text(
                              'MÃ KÍCH HOẠT',
                              style: TextStyle(
                                fontSize: 13,
                                letterSpacing: 1.2,
                                color: AppTheme.secondaryTextColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.backgroundColor.withOpacity(0.8),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: AppTheme.accentColor.withOpacity(0.5),
                                  width: 1.5,
                                ),
                              ),
                              child: Text(
                                _activationCode!.split('').join(' '),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 44,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 6.0,
                                  color: AppTheme.accentColor,
                                  shadows: [
                                    Shadow(
                                      color: AppTheme.accentColor.withOpacity(0.8),
                                      blurRadius: 18,
                                    ),
                                    Shadow(
                                      color: AppTheme.primaryColor.withOpacity(0.6),
                                      blurRadius: 36,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppTheme.backgroundColor.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'Vào xiaozhi.me -> Bảng điều khiển -> Thêm thiết bị -> nhập mã này',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textColor,
                                  height: 1.4,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      AppTheme.accentColor,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    _otaStatus.isNotEmpty
                                        ? _otaStatus
                                        : 'Đang chờ kích hoạt...',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: AppTheme.secondaryTextColor,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            OutlinedButton.icon(
                              onPressed: _startActivationFlow,
                              icon: const Icon(Icons.refresh, size: 18),
                              label: const Text(
                                'Lấy mã mới',
                                style: TextStyle(fontSize: 14),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.accentColor,
                                side: BorderSide(
                                  color: AppTheme.accentColor.withOpacity(0.6),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                              ),
                            ),
                          ],

                          const SizedBox(height: 16),
                          Text(
                            'MAC: ${_currentConfig.macAddress}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.secondaryTextColor,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Thanh tiêu đề công nghệ trên cùng (nút quay lại, tên bot, thời lượng)
  Widget _buildTopHudBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Nút quay lại bo vát góc
          InkWell(
            onTap: () {
              _otaCancelToken?.cancel();
              _xiaozhiService?.stopPlayback();
              Navigator.pop(context);
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.borderColor),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: AppTheme.textColor,
                size: 18,
              ),
            ),
          ),

          // Tên robot và phòng đàm thoại
          Column(
            children: [
              const Text(
                'HDVbot',
                style: TextStyle(
                  color: AppTheme.accentColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              Text(
                widget.conversation.title.isNotEmpty
                    ? widget.conversation.title
                    : 'Đàm thoại AI',
                style: const TextStyle(
                  color: AppTheme.secondaryTextColor,
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),

          // Thời lượng cuộc gọi
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.borderColor),
            ),
            child: Text(
              _formatDuration(_callDuration),
              style: const TextStyle(
                color: AppTheme.textColor,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Huy hiệu trạng thái HUD công nghệ
  Widget _buildStatusBadge(RobotEyeState eyeState) {
    Color badgeColor;
    IconData badgeIcon;

    switch (eyeState) {
      case RobotEyeState.speaking:
        badgeColor = AppTheme.accentColor;
        badgeIcon = Icons.volume_up_rounded;
        break;
      case RobotEyeState.listening:
        badgeColor = const Color(0xFF00E676);
        badgeIcon = Icons.mic_rounded;
        break;
      case RobotEyeState.thinking:
        badgeColor = const Color(0xFFFFB300);
        badgeIcon = Icons.sync_rounded;
        break;
      case RobotEyeState.error:
        badgeColor = AppTheme.errorColor;
        badgeIcon = Icons.error_outline_rounded;
        break;
      case RobotEyeState.idle:
      default:
        badgeColor = _isConnected ? const Color(0xFF00E676) : AppTheme.secondaryTextColor;
        badgeIcon = _isConnected ? Icons.check_circle_outline_rounded : Icons.hourglass_empty_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: badgeColor.withOpacity(0.55), width: 1.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(badgeIcon, color: badgeColor, size: 14),
          const SizedBox(width: 8),
          Text(
            _statusText,
            style: TextStyle(
              color: badgeColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  /// Bảng hiển thị phụ đề câu nói gần nhất (Bạn / HDVbot)
  Widget _buildSubtitlePanel() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      constraints: const BoxConstraints(minHeight: 52),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor.withOpacity(0.9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.borderColor, width: 1.0),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(
            Icons.subtitles_rounded,
            color: AppTheme.accentColor,
            size: 16,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _latestSubtitle.isNotEmpty
                  ? _latestSubtitle
                  : 'Hãy nói điều gì đó để bắt đầu trò chuyện...',
              style: TextStyle(
                color: _latestSubtitle.isNotEmpty
                    ? AppTheme.textColor
                    : AppTheme.secondaryTextColor,
                fontSize: 13,
                height: 1.3,
                fontStyle: _latestSubtitle.isNotEmpty
                    ? FontStyle.normal
                    : FontStyle.italic,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// Dải sóng âm thanh cân bằng HUD
  Widget _buildAudioVisualizer() {
    return Container(
      width: 220,
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor.withOpacity(0.6),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.borderColor.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(
          _audioLevels.length,
          (index) => Container(
            width: 3.5,
            height: math.max(4.0, 24.0 * _audioLevels[index]),
            decoration: BoxDecoration(
              color: _getBarColor(index, _audioLevels[index]),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }

  Color _getBarColor(int index, double level) {
    if (_hasError) {
      return AppTheme.errorColor.withOpacity(0.8);
    }
    if (_isRobotSpeaking) {
      return AppTheme.accentColor.withOpacity(0.6 + (0.4 * level));
    }
    if (_isSpeaking) {
      return const Color(0xFF00E676).withOpacity(0.6 + (0.4 * level));
    }
    return AppTheme.secondaryTextColor.withOpacity(0.35);
  }

  /// Các nút điều khiển cuộc gọi dưới đáy
  Widget _buildBottomControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Nút kết thúc cuộc gọi
        _buildCircleButton(
          icon: Icons.call_end_rounded,
          color: Colors.white,
          backgroundColor: AppTheme.errorColor,
          size: 60,
          onPressed: () async {
            await _xiaozhiService?.sendAbortMessage();
            if (mounted) {
              Navigator.pop(context);
            }
          },
        ),
        const SizedBox(width: 32),

        // Nút ngắt lời robot
        _buildCircleButton(
          icon: Icons.pan_tool_rounded,
          color: Colors.white,
          backgroundColor: const Color(0xFFFF9100),
          size: 54,
          onPressed: _sendAbortMessage,
        ),
      ],
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    required Color color,
    required Color backgroundColor,
    required double size,
    required VoidCallback onPressed,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: backgroundColor.withOpacity(0.35),
            blurRadius: 8,
            spreadRadius: 1,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Center(
            child: Icon(icon, color: color, size: size * 0.46),
          ),
        ),
      ),
    );
  }

  /// Hiển thị thông báo Snackbar tùy biến
  void _showCustomSnackbar({
    required String message,
    required IconData icon,
    required Color iconColor,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    final snackBar = SnackBar(
      content: Row(
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF1E293B),
      duration: const Duration(seconds: 3),
      margin: const EdgeInsets.only(bottom: 24, left: 16, right: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      elevation: 6,
    );

    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }
}
