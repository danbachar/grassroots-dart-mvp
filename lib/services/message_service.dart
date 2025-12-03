import 'dart:math';
import 'dart:typed_data';
import '../models/message.dart';
import '../protocol/constants.dart';
import '../protocol/payloads.dart';
import '../protocol/packet.dart';

/// Manages chat messages, routing, and store-and-forward
class MessageService {
  // In-memory storage (will be replaced with database later)
  final Map<String, Message> _messages = {}; // messageId -> Message
  final Map<String, List<String>> _chatHistory = {}; // peerId -> [messageIds]
  final List<String> _pendingMessages = []; // messageIds waiting for delivery
  final Random _random = Random.secure();

  /// Get all messages
  List<Message> get allMessages => _messages.values.toList();

  /// Get messages for a specific chat (with a peer)
  List<Message> getChat(Uint8List peerId) {
    final key = _peerIdToString(peerId);
    final messageIds = _chatHistory[key] ?? [];
    return messageIds
        .map((id) => _messages[id])
        .where((msg) => msg != null)
        .cast<Message>()
        .toList();
  }

  /// Get pending messages (waiting for delivery)
  List<Message> get pendingMessages {
    return _pendingMessages
        .map((id) => _messages[id])
        .where((msg) => msg != null)
        .cast<Message>()
        .toList();
  }

  /// Create a new chat message
  Packet createChatMessage({
    required Uint8List senderId,
    required Uint8List recipientId,
    required String content,
  }) {
    // Generate random message ID (16 bytes)
    final messageId = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      messageId[i] = _random.nextInt(256);
    }

    // Create message object
    final message = Message(
      messageId: messageId,
      senderId: senderId,
      recipientId: recipientId,
      content: content,
      status: MessageStatus.pending,
    );

    // Store message
    final msgKey = _messageIdToString(messageId);
    _messages[msgKey] = message;

    // Add to chat history
    final peerKey = _peerIdToString(recipientId);
    _chatHistory[peerKey] = (_chatHistory[peerKey] ?? [])..add(msgKey);

    // Add to pending queue
    _pendingMessages.add(msgKey);

    // Create chat message payload
    final payload = ChatMessagePayload(
      messageId: messageId,
      content: content,
    );

    // Create packet
    return Packet(
      type: MessageType.message,
      flags: PacketFlags.hasRecipient,
      senderId: senderId,
      recipientId: recipientId,
      payload: payload.serialize(),
    );
  }

  /// Handle incoming chat message
  Message handleChatMessage(Packet packet) {
    if (packet.type != MessageType.message) {
      throw ArgumentError('Packet is not a chat message');
    }
    if (packet.senderId == null) {
      throw ArgumentError('Chat message missing sender ID');
    }

    final payload = ChatMessagePayload.deserialize(packet.payload);
    final senderId = packet.senderId!;
    final recipientId = packet.recipientId;

    // Create message object
    final message = Message(
      messageId: payload.messageId,
      senderId: senderId,
      recipientId: recipientId,
      content: payload.content,
      timestamp: DateTime.fromMillisecondsSinceEpoch(packet.timestamp),
      status: MessageStatus.delivered, // Mark as delivered since we received it
      ttl: packet.ttl,
    );

    // Store message
    final msgKey = _messageIdToString(payload.messageId);
    _messages[msgKey] = message;

    // Add to chat history
    final peerKey = _peerIdToString(senderId);
    _chatHistory[peerKey] = (_chatHistory[peerKey] ?? [])..add(msgKey);

    return message;
  }

  /// Create delivery acknowledgment
  Packet createDeliveryAck({
    required Uint8List senderId,
    required Uint8List recipientId,
    required Uint8List messageId,
  }) {
    final payload = DeliveryAckPayload(messageId: messageId);

    return Packet(
      type: MessageType.deliveryAck,
      flags: PacketFlags.hasRecipient,
      senderId: senderId,
      recipientId: recipientId,
      payload: payload.serialize(),
    );
  }

  /// Handle delivery acknowledgment
  void handleDeliveryAck(Packet packet) {
    if (packet.type != MessageType.deliveryAck) {
      throw ArgumentError('Packet is not a delivery ack');
    }

    final payload = DeliveryAckPayload.deserialize(packet.payload);
    final msgKey = _messageIdToString(payload.messageId);

    // Update message status
    final message = _messages[msgKey];
    if (message != null) {
      _messages[msgKey] = message.withStatus(MessageStatus.delivered);

      // Remove from pending queue
      _pendingMessages.remove(msgKey);
    }
  }

  /// Create read receipt
  Packet createReadReceipt({
    required Uint8List senderId,
    required Uint8List recipientId,
    required Uint8List messageId,
  }) {
    final payload = ReadReceiptPayload(messageId: messageId);

    return Packet(
      type: MessageType.readReceipt,
      flags: PacketFlags.hasRecipient,
      senderId: senderId,
      recipientId: recipientId,
      payload: payload.serialize(),
    );
  }

  /// Handle read receipt
  void handleReadReceipt(Packet packet) {
    if (packet.type != MessageType.readReceipt) {
      throw ArgumentError('Packet is not a read receipt');
    }

    final payload = ReadReceiptPayload.deserialize(packet.payload);
    final msgKey = _messageIdToString(payload.messageId);

    // Update message status
    final message = _messages[msgKey];
    if (message != null) {
      _messages[msgKey] = message.withStatus(MessageStatus.read);
    }
  }

  /// Mark message as sent
  void markAsSent(Uint8List messageId) {
    final msgKey = _messageIdToString(messageId);
    final message = _messages[msgKey];
    if (message != null) {
      _messages[msgKey] = message.withStatus(MessageStatus.sent);
    }
  }

  /// Mark message as delivered
  void markAsDelivered(Uint8List messageId) {
    final msgKey = _messageIdToString(messageId);
    final message = _messages[msgKey];
    if (message != null) {
      _messages[msgKey] = message.withStatus(MessageStatus.delivered);
      _pendingMessages.remove(msgKey);
    }
  }

  /// Mark message as read
  void markAsRead(Uint8List messageId) {
    final msgKey = _messageIdToString(messageId);
    final message = _messages[msgKey];
    if (message != null) {
      _messages[msgKey] = message.withStatus(MessageStatus.read);
    }
  }

  /// Get messages that need retry
  List<Message> getMessagesForRetry() {
    return _pendingMessages
        .map((id) => _messages[id])
        .where((msg) => msg != null && msg.shouldRetry() && !msg.isExpired())
        .cast<Message>()
        .toList();
  }

  /// Retry a message (increment retry count)
  void retryMessage(Uint8List messageId) {
    final msgKey = _messageIdToString(messageId);
    final message = _messages[msgKey];
    if (message != null) {
      _messages[msgKey] = message.withRetry();
    }
  }

  /// Clean up expired messages
  void cleanupExpiredMessages() {
    final now = DateTime.now();
    final expiredIds = <String>[];

    for (final entry in _messages.entries) {
      if (entry.value.isExpired()) {
        expiredIds.add(entry.key);
      }
    }

    for (final id in expiredIds) {
      _messages.remove(id);
      _pendingMessages.remove(id);

      // Remove from chat history
      for (final history in _chatHistory.values) {
        history.remove(id);
      }
    }
  }

  /// Helper: Convert message ID to string key
  String _messageIdToString(Uint8List messageId) {
    return messageId.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Helper: Convert peer ID to string key
  String _peerIdToString(Uint8List peerId) {
    return peerId.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
