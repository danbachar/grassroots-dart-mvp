import 'dart:typed_data';
import '../protocol/constants.dart';

/// Represents a chat message
class Message {
  final Uint8List messageId;    // 16 bytes UUID
  final Uint8List senderId;     // 8 bytes PeerID
  final Uint8List? recipientId; // 8 bytes PeerID (null for broadcast)
  final String content;
  final DateTime timestamp;
  final int status;             // MessageStatus constant
  final int retryCount;
  final int ttl;                // Remaining TTL for routing

  Message({
    required this.messageId,
    required this.senderId,
    this.recipientId,
    required this.content,
    DateTime? timestamp,
    this.status = MessageStatus.pending,
    this.retryCount = 0,
    this.ttl = Limits.defaultTTL,
  }) : timestamp = timestamp ?? DateTime.now() {
    if (messageId.length != 16) {
      throw ArgumentError('Message ID must be 16 bytes');
    }
    if (senderId.length != 8) {
      throw ArgumentError('Sender ID must be 8 bytes');
    }
    if (recipientId != null && recipientId!.length != 8) {
      throw ArgumentError('Recipient ID must be 8 bytes');
    }
  }

  /// Get message ID as hex string
  String get messageIdHex => messageId.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// Get sender ID as hex string
  String get senderIdHex => senderId.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// Get recipient ID as hex string (or "broadcast")
  String get recipientIdHex => recipientId == null
      ? 'broadcast'
      : recipientId!.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// Check if this is a broadcast message
  bool get isBroadcast => recipientId == null;

  /// Check if message is pending delivery
  bool get isPending => status == MessageStatus.pending;

  /// Check if message is sent
  bool get isSent => status == MessageStatus.sent;

  /// Check if message is delivered
  bool get isDelivered => status == MessageStatus.delivered;

  /// Check if message is read
  bool get isRead => status == MessageStatus.read;

  /// Copy with updated fields
  Message copyWith({
    Uint8List? messageId,
    Uint8List? senderId,
    Uint8List? recipientId,
    String? content,
    DateTime? timestamp,
    int? status,
    int? retryCount,
    int? ttl,
  }) {
    return Message(
      messageId: messageId ?? this.messageId,
      senderId: senderId ?? this.senderId,
      recipientId: recipientId ?? this.recipientId,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
      ttl: ttl ?? this.ttl,
    );
  }

  /// Create a message with incremented retry count
  Message withRetry() {
    return copyWith(retryCount: retryCount + 1);
  }

  /// Create a message with updated status
  Message withStatus(int newStatus) {
    return copyWith(status: newStatus);
  }

  /// Create a message with decremented TTL (for routing)
  Message decrementTTL() {
    return copyWith(ttl: ttl - 1);
  }

  /// Check if message should be retried
  bool shouldRetry() {
    return isPending && retryCount < RetryConfig.maxRetries;
  }

  /// Get next retry delay in milliseconds
  int getRetryDelay() {
    if (retryCount >= RetryConfig.backoffDelays.length) {
      return RetryConfig.backoffDelays.last;
    }
    return RetryConfig.backoffDelays[retryCount];
  }

  /// Check if message has expired (for store-and-forward)
  bool isExpired() {
    final age = DateTime.now().difference(timestamp);
    return age.inMilliseconds > Timeouts.messageExpiry;
  }

  @override
  String toString() {
    return 'Message(id: ${messageIdHex.substring(0, 8)}..., '
           'from: ${senderIdHex.substring(0, 8)}..., '
           'to: ${recipientIdHex.substring(0, 8)}..., '
           'status: $status, ttl: $ttl)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Message) return false;

    // Compare message IDs byte by byte
    if (messageId.length != other.messageId.length) return false;
    for (int i = 0; i < messageId.length; i++) {
      if (messageId[i] != other.messageId[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => messageIdHex.hashCode;
}
