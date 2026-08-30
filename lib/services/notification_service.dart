import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/notification_model.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference _notifsRef(String uid) =>
      _db.collection('users').doc(uid).collection('notifications');

  /// Stream of user notifications ordered by newest first.
  Stream<List<NotificationModel>> watchNotifications(String uid) {
    if (uid.isEmpty) return Stream.value([]);
    return _notifsRef(uid)
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) => snap.docs.map((d) => NotificationModel.fromFirestore(d)).toList());
  }

  /// Sends a new notification to a specific user.
  Future<void> sendNotification({
    required String uid,
    required String title,
    required String body,
    required String type,
    String? relatedSessionId,
  }) async {
    if (uid.isEmpty) return;
    try {
      final notif = NotificationModel(
        id: '',
        userId: uid,
        title: title,
        body: body,
        type: type,
        timestamp: Timestamp.now(),
        isRead: false,
        relatedSessionId: relatedSessionId,
      );
      await _notifsRef(uid).add(notif.toFirestore());
    } catch (e) {
      debugPrint('[NotificationService] Error sending notification: $e');
    }
  }

  /// Marks a specific notification as read.
  Future<void> markAsRead(String uid, String notifId) async {
    if (uid.isEmpty || notifId.isEmpty) return;
    try {
      await _notifsRef(uid).doc(notifId).update({'isRead': true});
    } catch (e) {
      debugPrint('[NotificationService] Error marking as read: $e');
    }
  }

  /// Marks all unread notifications as read for the user.
  Future<void> markAllAsRead(String uid) async {
    if (uid.isEmpty) return;
    try {
      final snap = await _notifsRef(uid).where('isRead', isEqualTo: false).get();
      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.update(doc.reference, {'isRead': true});
      }
      await batch.commit();
    } catch (e) {
      debugPrint('[NotificationService] Error marking all as read: $e');
    }
  }

  /// Deletes a specific notification.
  Future<void> deleteNotification(String uid, String notifId) async {
    if (uid.isEmpty || notifId.isEmpty) return;
    try {
      await _notifsRef(uid).doc(notifId).delete();
    } catch (e) {
      debugPrint('[NotificationService] Error deleting notification: $e');
    }
  }
}
