import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:ai_assistant/models/conversation.dart';
import 'package:ai_assistant/models/xiaozhi_config.dart';
import 'package:ai_assistant/providers/config_provider.dart';
import 'package:ai_assistant/utils/app_theme.dart';

class ConversationTile extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const ConversationTile({
    super.key,
    required this.conversation,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 4,
            spreadRadius: 0,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                _buildAvatar(),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Text(
                                  conversation.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: AppTheme.textColor,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                _buildTypeTag(context),
                              ],
                            ),
                          ),
                          Text(
                            _formatTime(conversation.lastMessageTime),
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppTheme.secondaryTextColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        conversation.lastMessage,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppTheme.secondaryTextColor,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  child: const Icon(
                    Icons.chevron_right,
                    color: AppTheme.secondaryTextColor,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTypeTag(BuildContext context) {
    String label = 'Thoại';

    if (conversation.configId.isNotEmpty) {
      final configProvider = Provider.of<ConfigProvider>(
        context,
        listen: false,
      );

      final matchingConfig =
          configProvider.xiaozhiConfigs
              .where((config) => config.id == conversation.configId)
              .firstOrNull;
      if (matchingConfig != null) {
        label = matchingConfig.name;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.backgroundColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppTheme.primaryColor.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          color: AppTheme.primaryColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppTheme.primaryColor.withOpacity(0.5)),
      ),
      child: const CircleAvatar(
        radius: 24,
        backgroundColor: AppTheme.surfaceColor,
        child: Icon(Icons.mic, color: AppTheme.primaryColor, size: 24),
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0 && difference.inDays <= 1) {
      return 'Hôm qua';
    } else if (difference.inDays > 1 && difference.inDays <= 7) {
      return 'Thứ ${_getWeekday(dateTime.weekday)}';
    } else {
      final hour = dateTime.hour.toString().padLeft(2, '0');
      final minute = dateTime.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    }
  }

  String _getWeekday(int weekday) {
    switch (weekday) {
      case 1:
        return 'Hai';
      case 2:
        return 'Ba';
      case 3:
        return 'Tư';
      case 4:
        return 'Năm';
      case 5:
        return 'Sáu';
      case 6:
        return 'Bảy';
      case 7:
        return 'CN';
      default:
        return '';
    }
  }
}
