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
import 'package:ai_assistant/widgets/robot_face.dart';

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

  // Cảm xúc robot từ server và đếm giờ về trung tính
  FaceEmotion _currentEmotion = FaceEmotion.neutral;
  Timer? _idleEmotionTimer;

  // Thanh điều khiển nhỏ mờ ở mép dưới
  bool _showControls = false;
  Timer? _controlsTimer;

  late AnimationController _animationController;
  final List<double> _audioLevels = List.filled(24, 0.05);
  Timer? _audioVisualizerTimer;

  @override
  void initState() {
    super.initState();
    _currentConfig = widget.xiaozhiConfig;

    // Bật chế độ toàn màn hình ẩn hoàn toàn thanh trạng thái & điều hướng
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

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

      // Huỷ đăng ký listener cũ nếu có trước khi tạo service mới
      _xiaozhiService?.removeListener(_handleServiceEvent);
      _xiaozhiService?.emotionNotifier.removeListener(_handleEmotionChange);

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
      _xiaozhiService!.emotionNotifier.addListener(_handleEmotionChange);

      // Lấy cảm xúc ban đầu nếu đã có
      _currentEmotion = RobotFace.faceEmotionFromServer(
        _xiaozhiService!.emotionNotifier.value,
      );

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

  void _handleEmotionChange() {
    if (!mounted) return;
    final rawEmotion = _xiaozhiService?.emotionNotifier.value;
    final parsed = RobotFace.faceEmotionFromServer(rawEmotion);
    _idleEmotionTimer?.cancel();
    setState(() {
      _currentEmotion = parsed;
    });
  }

  void _startIdleEmotionTimer() {
    _idleEmotionTimer?.cancel();
    _idleEmotionTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) {
        setState(() {
          _currentEmotion = FaceEmotion.neutral;
        });
      }
    });
  }

  void _handleServerMessage(dynamic message) {
    if (!mounted) return;
    if (message is Map<String, dynamic>) {
      final String type = message['type'] ?? '';

      // Cập nhật cảm xúc nếu tin nhắn có chứa trường 'emotion'
      final dynamic emotion = message['emotion'];
      if (emotion is String && emotion.isNotEmpty) {
        _idleEmotionTimer?.cancel();
        _currentEmotion = RobotFace.faceEmotionFromServer(emotion);
      }

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
          _idleEmotionTimer?.cancel();
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
          // Khi robot nói xong và về idle qua 6 giây thì trả về neutral
          _startIdleEmotionTimer();
        }
      } else if (type == 'stt') {
        final String text = message['text'] ?? '';
        if (text.isNotEmpty) {
          _idleEmotionTimer?.cancel();
          setState(() {
            _latestSubtitle = 'Bạn: $text';
            _isThinking = true;
            _statusText = 'Đang suy nghĩ...';
          });
        }
      } else if (type == 'llm') {
        _idleEmotionTimer?.cancel();
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
        _idleEmotionTimer?.cancel();
        setState(() {
          if (event.data is String && (event.data as String).isNotEmpty) {
            _latestSubtitle = 'Bạn: ${event.data}';
          }
          _isThinking = true;
          _statusText = 'Đang suy nghĩ...';
        });
        break;

      case XiaozhiServiceEventType.textMessage:
        _idleEmotionTimer?.cancel();
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
    // Khôi phục lại chế độ màn hình thông thường
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    _otaCancelToken?.cancel();
    _idleEmotionTimer?.cancel();
    _controlsTimer?.cancel();
    _xiaozhiService?.removeListener(_handleServiceEvent);
    _xiaozhiService?.emotionNotifier.removeListener(_handleEmotionChange);
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
    _startIdleEmotionTimer();

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

  /// Xác định trạng thái thật của khuôn mặt robot từ trạng thái cuộc gọi
  FaceState _resolveFaceState() {
    if (_showActivationOverlay) {
      if (_otaError != null) {
        return FaceState.error;
      }
      return FaceState.connecting;
    }
    if (_hasError) {
      return FaceState.error;
    }
    if (!_isConnected || !_serverReady) {
      return FaceState.connecting;
    }
    if (_isRobotSpeaking) {
      return FaceState.speaking;
    }
    if (_isThinking) {
      return FaceState.thinking;
    }
    if (_isSpeaking) {
      return FaceState.listening;
    }
    return FaceState.idle;
  }

  void _toggleControls() {
    if (_showControls) {
      setState(() {
        _showControls = false;
      });
      _controlsTimer?.cancel();
    } else {
      setState(() {
        _showControls = true;
      });
      _resetControlsTimer();
    }
  }

  void _resetControlsTimer() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final faceState = _resolveFaceState();
    final double currentVolume =
        _audioLevels.isNotEmpty ? _audioLevels.last : 0.0;

    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Khuôn mặt robot chiếm toàn màn hình nền đen tuyền
            Positioned.fill(
              child: Container(
                color: const Color(0xFF000000),
                child: RobotFace(
                  state: faceState,
                  emotion: _currentEmotion,
                  volume: currentVolume,
                  color: const Color(0xFF00F0FF),
                ),
              ),
            ),

            // Thanh điều khiển nhỏ mờ ở mép dưới khi chạm vào màn hình (tự ẩn sau 4 giây)
            if (_showControls && !_showActivationOverlay)
              Positioned(
                left: 16,
                right: 16,
                bottom: 12,
                child: _buildBottomControlBar(),
              ),

            // Lớp phủ kích hoạt (hiển thị mã 6 số) và lớp phủ lỗi khi cần (đặt trên khuôn mặt)
            if (_showActivationOverlay) _buildActivationOverlay(),
          ],
        ),
      ),
    );
  }

  /// Thanh điều khiển nhỏ mờ ở mép dưới màn hình
  Widget _buildBottomControlBar() {
    final isMuted = _xiaozhiService?.isMuted ?? false;

    return Center(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _resetControlsTimer,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xCC000000), // Nền đen mờ 80%
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: const Color(0x5500F0FF),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.6),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Nút quay lại bo tròn nhỏ
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                color: Colors.white70,
                tooltip: 'Quay lại',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: () {
                  _otaCancelToken?.cancel();
                  _xiaozhiService?.stopPlayback();
                  Navigator.pop(context);
                },
              ),
              const SizedBox(width: 8),

              // Dòng trạng thái ngắn
              Container(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _hasError
                            ? AppTheme.errorColor
                            : (_isConnected
                                ? const Color(0xFF00E676)
                                : Colors.orangeAccent),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        _statusText,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // Nút tắt / mở mic
              _buildSmallCircleButton(
                icon: isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                color: isMuted ? AppTheme.errorColor : const Color(0xFF00F0FF),
                backgroundColor: const Color(0x3300F0FF),
                size: 38,
                onPressed: () {
                  _xiaozhiService?.toggleMute();
                  setState(() {});
                  _resetControlsTimer();
                },
              ),
              const SizedBox(width: 10),

              // Nút ngắt lời robot
              _buildSmallCircleButton(
                icon: Icons.pan_tool_rounded,
                color: Colors.white,
                backgroundColor: const Color(0xCCFF9100),
                size: 38,
                onPressed: () {
                  _sendAbortMessage();
                  _resetControlsTimer();
                },
              ),
              const SizedBox(width: 10),

              // Nút kết thúc cuộc gọi
              _buildSmallCircleButton(
                icon: Icons.call_end_rounded,
                color: Colors.white,
                backgroundColor: AppTheme.errorColor,
                size: 42,
                onPressed: () async {
                  _otaCancelToken?.cancel();
                  await _xiaozhiService?.sendAbortMessage();
                  _xiaozhiService?.stopPlayback();
                  if (mounted) {
                    Navigator.pop(context);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSmallCircleButton({
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
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Center(
            child: Icon(icon, color: color, size: size * 0.5),
          ),
        ),
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
