import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/notification_model.dart';
import '../models/session_model.dart';
import '../screens/student/session_detail_screen.dart';
import '../services/notification_service.dart';

// ─── Brand Colours ────────────────────────────────────────────────────────────
const _navy      = Color(0xFF003366);
const _surface   = Color(0xFFF8FAFC);
const _white     = Color(0xFFFFFFFF);
const _border    = Color(0xFFE2EAF4);
const _textDark  = Color(0xFF1A2B3C);
const _textMid   = Color(0xFF4A5568);
const _textLight = Color(0xFF8A9BB0);
const _green     = Color(0xFF16A34A);
const _greenBg   = Color(0x1A16A34A);
const _amber     = Color(0xFFD97706);
const _amberBg   = Color(0x1AD97706);
const _blue      = Color(0xFF2563EB);
const _blueBg    = Color(0x1A2563EB);

class NotificationCenterSheet extends StatelessWidget {
  const NotificationCenterSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const NotificationCenterSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? '';
    final notifService = NotificationService();

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.78,
      ),
      decoration: const BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          StreamBuilder<List<NotificationModel>>(
            stream: notifService.watchNotifications(uid),
            builder: (context, snapshot) {
              final notifs = snapshot.data ?? [];
              final unreadCount = notifs.where((n) => !n.isRead).length;

              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Row(
                  children: [
                    const Text(
                      'Notifications',
                      style: TextStyle(
                        color: _textDark,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    if (unreadCount > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _navy,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$unreadCount new',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    if (unreadCount > 0)
                      GestureDetector(
                        onTap: () => notifService.markAllAsRead(uid),
                        child: const Text(
                          'Mark all read',
                          style: TextStyle(
                            color: _blue,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
          const Divider(height: 1, color: _border),

          // Notification List
          Expanded(
            child: StreamBuilder<List<NotificationModel>>(
              stream: notifService.watchNotifications(uid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator(color: _navy));
                }

                final notifs = snapshot.data ?? [];

                if (notifs.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: _navy.withValues(alpha: 0.08),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.notifications_none_rounded,
                              size: 32,
                              color: _navy,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'No notifications yet',
                            style: TextStyle(
                              color: _textDark,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Updates on return-demonstrations and AI feedback will appear here.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _textLight,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  itemCount: notifs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = notifs[index];
                    return _NotificationTile(
                      notif: item,
                      onTap: () async {
                        if (!item.isRead) {
                          notifService.markAsRead(uid, item.id);
                        }
                        if (item.relatedSessionId != null && item.relatedSessionId!.isNotEmpty) {
                          try {
                            final doc = await FirebaseFirestore.instance
                                .collection('sessions')
                                .doc(item.relatedSessionId)
                                .get();
                            if (doc.exists && context.mounted) {
                              final session = SessionModel.fromFirestore(doc);
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => SessionDetailScreen(session: session),
                                ),
                              );
                            }
                          } catch (_) {}
                        }
                      },
                      onDelete: () => notifService.deleteNotification(uid, item.id),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final NotificationModel notif;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _NotificationTile({
    required this.notif,
    required this.onTap,
    required this.onDelete,
  });

  ({Color bg, Color iconColor, IconData icon}) _styleForType(String type) {
    switch (type) {
      case 'feedback_released':
        return (bg: _greenBg, iconColor: _green, icon: Icons.verified_rounded);
      case 'practice_completed':
        return (bg: _blueBg, iconColor: _blue, icon: Icons.videocam_rounded);
      case 'security':
        return (bg: _amberBg, iconColor: _amber, icon: Icons.shield_rounded);
      default:
        return (bg: const Color(0x14003366), iconColor: _navy, icon: Icons.notifications_rounded);
    }
  }

  String _formatTime(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final style = _styleForType(notif.type);
    final date = notif.timestamp.toDate();

    return Dismissible(
      key: Key(notif.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: const Color(0xFFEF4444),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 22),
      ),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: notif.isRead ? _white : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: notif.isRead ? _border : const Color(0x33003366),
              width: notif.isRead ? 1.0 : 1.4,
            ),
            boxShadow: [
              BoxShadow(
                color: _navy.withValues(alpha: 0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: style.bg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(style.icon, size: 20, color: style.iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notif.title,
                            style: TextStyle(
                              color: _textDark,
                              fontSize: 14,
                              fontWeight: notif.isRead ? FontWeight.w600 : FontWeight.w800,
                            ),
                          ),
                        ),
                        Text(
                          _formatTime(date),
                          style: TextStyle(
                            color: notif.isRead ? _textLight : _blue,
                            fontSize: 11,
                            fontWeight: notif.isRead ? FontWeight.w500 : FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notif.body,
                      style: const TextStyle(
                        color: _textMid,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              if (!notif.isRead) ...[
                const SizedBox(width: 8),
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 6),
                  decoration: const BoxDecoration(
                    color: _blue,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
