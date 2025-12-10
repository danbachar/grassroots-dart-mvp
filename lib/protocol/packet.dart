import 'dart:typed_data';
import 'constants.dart';

/// Represents a protocol packet with 14-byte header + variable payload
class Packet {
  // Header fields (14 bytes)
  final int version;        // 1 byte
  final int type;           // 1 byte (MessageType)
  final int ttl;            // 1 byte
  final int flags;          // 1 byte
  final int timestamp;      // 8 bytes (Unix timestamp in milliseconds)
  final int payloadLength;  // 2 bytes

  // Variable fields
  final Uint8List? senderId;      // 32 bytes (Ed25519 public key)
  final Uint8List? recipientId;   // 32 bytes (Ed25519 public key, optional)
  final Uint8List payload;        // Variable length
  final Uint8List? signature;     // 64 bytes (Ed25519, optional)

  Packet({
    this.version = 1,
    required this.type,
    this.ttl = Limits.defaultTTL,
    this.flags = 0,
    int? timestamp,
    int? payloadLength,
    this.senderId,
    this.recipientId,
    required this.payload,
    this.signature,
  }) : timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch,
       payloadLength = payloadLength ?? payload.length {

    // Validate
    if (this.ttl < 0 || this.ttl > 255) {
      throw ArgumentError('TTL must be 0-255');
    }
    if (this.payload.length > Limits.maxMessageSize) {
      throw ArgumentError('Payload exceeds maximum size');
    }
    if (senderId != null && senderId!.length != 32) {
      throw ArgumentError('Sender ID must be 32 bytes (Ed25519 public key)');
    }
    if (recipientId != null && recipientId!.length != 32) {
      throw ArgumentError('Recipient ID must be 32 bytes (Ed25519 public key)');
    }
    if (signature != null && signature!.length != 64) {
      throw ArgumentError('Signature must be 64 bytes');
    }
  }

  /// Serialize packet to bytes
  Uint8List serialize() {
    final buffer = BytesBuilder();

    // Write header (14 bytes)
    buffer.addByte(version);
    buffer.addByte(type);
    buffer.addByte(ttl);
    buffer.addByte(flags);
    buffer.add(_uint64ToBytes(timestamp));
    buffer.add(_uint16ToBytes(payloadLength));

    // Write variable fields
    if (senderId != null) {
      buffer.add(senderId!);
    }

    if (hasFlag(PacketFlags.hasRecipient) && recipientId != null) {
      buffer.add(recipientId!);
    }

    buffer.add(payload);

    if (hasFlag(PacketFlags.hasSignature) && signature != null) {
      buffer.add(signature!);
    }

    return buffer.toBytes();
  }

  /// Deserialize packet from bytes
  static Packet deserialize(Uint8List bytes) {
    if (bytes.length < 14) {
      throw FormatException('Packet too short (< 14 bytes)');
    }

    final data = ByteData.view(bytes.buffer);
    int offset = 0;

    // Read header
    final version = data.getUint8(offset++);
    final type = data.getUint8(offset++);
    final ttl = data.getUint8(offset++);
    final flags = data.getUint8(offset++);
    final timestamp = data.getUint64(offset, Endian.big);
    offset += 8;
    final payloadLength = data.getUint16(offset, Endian.big);
    offset += 2;
    // Skip 2 bytes padding (offset is now 14)

    // Read sender ID (always present in our implementation)
    Uint8List? senderId;
    if (offset + 32 <= bytes.length) {
      senderId = bytes.sublist(offset, offset + 32);
      offset += 32;
    }

    // Read recipient ID if flag is set
    Uint8List? recipientId;
    if ((flags & PacketFlags.hasRecipient) != 0) {
      if (offset + 32 <= bytes.length) {
        recipientId = bytes.sublist(offset, offset + 32);
        offset += 32;
      }
    }

    // Read payload
    if (offset + payloadLength > bytes.length) {
      throw FormatException('Payload length exceeds packet size');
    }
    final payload = bytes.sublist(offset, offset + payloadLength);
    offset += payloadLength;

    // Read signature if flag is set
    Uint8List? signature;
    if ((flags & PacketFlags.hasSignature) != 0) {
      if (offset + 64 <= bytes.length) {
        signature = bytes.sublist(offset, offset + 64);
        offset += 64;
      }
    }

    return Packet(
      version: version,
      type: type,
      ttl: ttl,
      flags: flags,
      timestamp: timestamp,
      payloadLength: payloadLength,
      senderId: senderId,
      recipientId: recipientId,
      payload: payload,
      signature: signature,
    );
  }

  /// Check if a specific flag is set
  bool hasFlag(int flag) => (flags & flag) != 0;

  /// Create a copy with decremented TTL (for relay)
  Packet decrementTTL() {
    return Packet(
      version: version,
      type: type,
      ttl: ttl - 1,
      flags: flags,
      timestamp: timestamp,
      payloadLength: payloadLength,
      senderId: senderId,
      recipientId: recipientId,
      payload: payload,
      signature: signature,
    );
  }

  /// Helper: Convert uint64 to big-endian bytes
  static Uint8List _uint64ToBytes(int value) {
    final data = ByteData(8);
    data.setUint64(0, value, Endian.big);
    return data.buffer.asUint8List();
  }

  /// Helper: Convert uint16 to big-endian bytes
  static Uint8List _uint16ToBytes(int value) {
    final data = ByteData(2);
    data.setUint16(0, value, Endian.big);
    return data.buffer.asUint8List();
  }

  @override
  String toString() {
    return 'Packet(type: 0x${type.toRadixString(16)}, ttl: $ttl, '
           'flags: 0x${flags.toRadixString(16)}, '
           'payloadLen: $payloadLength, '
           'timestamp: ${DateTime.fromMillisecondsSinceEpoch(timestamp)})';
  }
}
