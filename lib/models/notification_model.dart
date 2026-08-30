import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationModel {
  final String id;
  final String userId;
  final String title;
  final String body;
  final String type; // 'feedback_released' | 'practice_completed' | 'security' | 'system'
  final Timestamp timestamp;
  final bool isRead;
  final String? relatedSessionId;

  const NotificationModel({
    required this.id,
    required this.userId,
    required this.title,
    required this.body,
    required this.type,
    required this.timestamp,
    this.isRead = false,
    this.relatedSessionId,
  });

  factory NotificationModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return NotificationModel(
      id: doc.id,
      userId: data['userId'] as String? ?? '',
      title: data['title'] as String? ?? 'Notification',
      body: data['body'] as String? ?? '',
      type: data['type'] as String? ?? 'system',
      timestamp: data['timestamp'] as Timestamp? ?? Timestamp.now(),
      isRead: data['isRead'] as bool? ?? false,
      relatedSessionId: data['relatedSessionId'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'userId': userId,
        'title': title,
        'body': body,
        'type': type,
        'timestamp': timestamp,
        'isRead': isRead,
        if (relatedSessionId != null) 'relatedSessionId': relatedSessionId,
      };

  NotificationModel copyWith({
    String? id,
    String? userId,
    String? title,
    String? body,
    String? type,
    Timestamp? timestamp,
    bool? isRead,
    String? relatedSessionId,
  }) {
    return NotificationModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      body: body ?? this.body,
      type: type ?? this.type,
      timestamp: timestamp ?? this.timestamp,
      isRead: isRead ?? this.isRead,
      relatedSessionId: relatedSessionId ?? this.relatedSessionId,
    );
  }
}
