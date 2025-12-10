import 'dart:convert';
import 'dart:typed_data';

/// Base class for message payloads
abstract class MessagePayload {
  /// Serialize payload to bytes
  Uint8List serialize();

  /// Get payload type
  int get type;
}

/// Chat message payload (0x01)
class ChatMessagePayload extends MessagePayload {
  final Uint8List messageId;  // 16 bytes UUID
  final String content;

  ChatMessagePayload({
    required this.messageId,
    required this.content,
  }) {
    if (messageId.length != 16) {
      throw ArgumentError('Message ID must be 16 bytes');
    }
  }

  @override
  int get type => 0x01;

  @override
  Uint8List serialize() {
    final contentBytes = utf8.encode(content);
    final buffer = BytesBuilder();

    buffer.add(messageId);
    buffer.add(_uint16ToBytes(contentBytes.length));
    buffer.add(contentBytes);

    return buffer.toBytes();
  }

  static ChatMessagePayload deserialize(Uint8List bytes) {
    if (bytes.length < 18) {
      throw FormatException('Chat message payload too short');
    }

    final messageId = bytes.sublist(0, 16);
    final data = ByteData.view(bytes.buffer);
    final contentLength = data.getUint16(16, Endian.big);

    if (bytes.length < 18 + contentLength) {
      throw FormatException('Content length exceeds payload size');
    }

    final contentBytes = bytes.sublist(18, 18 + contentLength);
    final content = utf8.decode(contentBytes);

    return ChatMessagePayload(
      messageId: messageId,
      content: content,
    );
  }

  static Uint8List _uint16ToBytes(int value) {
    final data = ByteData(2);
    data.setUint16(0, value, Endian.big);
    return data.buffer.asUint8List();
  }
}

/// Delivery acknowledgment payload (0x02)
class DeliveryAckPayload extends MessagePayload {
  final Uint8List messageId;  // 16 bytes UUID

  DeliveryAckPayload({required this.messageId}) {
    if (messageId.length != 16) {
      throw ArgumentError('Message ID must be 16 bytes');
    }
  }

  @override
  int get type => 0x02;

  @override
  Uint8List serialize() => messageId;

  static DeliveryAckPayload deserialize(Uint8List bytes) {
    if (bytes.length != 16) {
      throw FormatException('Delivery ack payload must be 16 bytes');
    }
    return DeliveryAckPayload(messageId: bytes);
  }
}

/// Read receipt payload (0x03)
class ReadReceiptPayload extends MessagePayload {
  final Uint8List messageId;  // 16 bytes UUID

  ReadReceiptPayload({required this.messageId}) {
    if (messageId.length != 16) {
      throw ArgumentError('Message ID must be 16 bytes');
    }
  }

  @override
  int get type => 0x03;

  @override
  Uint8List serialize() => messageId;

  static ReadReceiptPayload deserialize(Uint8List bytes) {
    if (bytes.length != 16) {
      throw FormatException('Read receipt payload must be 16 bytes');
    }
    return ReadReceiptPayload(messageId: bytes);
  }
}

/// Friend request payload (0x20)
class FriendRequestPayload extends MessagePayload {
  final Uint8List publicKey;       // 32 bytes Ed25519
  final String displayName;
  final Uint8List? signature;      // 64 bytes Ed25519 signature

  FriendRequestPayload({
    required this.publicKey,
    required this.displayName,
    this.signature,
  }) {
    if (publicKey.length != 32) {
      throw ArgumentError('Public key must be 32 bytes');
    }
    if (displayName.length > 63) {
      throw ArgumentError('Display name must be <= 63 bytes');
    }
    if (signature != null && signature!.length != 64) {
      throw ArgumentError('Signature must be 64 bytes');
    }
  }

  @override
  int get type => 0x20;

  @override
  Uint8List serialize() {
    final nameBytes = utf8.encode(displayName);
    final buffer = BytesBuilder();

    buffer.add(publicKey);
    buffer.addByte(nameBytes.length);
    buffer.add(nameBytes);
    if (signature != null) {
      buffer.add(signature!);
    }

    return buffer.toBytes();
  }

  static FriendRequestPayload deserialize(Uint8List bytes) {
    if (bytes.length < 33) {  // 32 + 1 minimum
      throw FormatException('Friend request payload too short');
    }

    final publicKey = bytes.sublist(0, 32);
    final nameLength = bytes[32];

    if (bytes.length < 33 + nameLength) {
      throw FormatException('Name length exceeds payload size');
    }

    final nameBytes = bytes.sublist(33, 33 + nameLength);
    final displayName = utf8.decode(nameBytes);

    Uint8List? signature;
    if (bytes.length >= 33 + nameLength + 64) {
      signature = bytes.sublist(33 + nameLength, 33 + nameLength + 64);
    }

    return FriendRequestPayload(
      publicKey: publicKey,
      displayName: displayName,
      signature: signature,
    );
  }
}

/// Friend accept payload (0x21)
class FriendAcceptPayload extends MessagePayload {
  final Uint8List publicKey;      // 32 bytes Ed25519
  final String displayName;
  final Uint8List? signature;     // 64 bytes Ed25519 signature

  FriendAcceptPayload({
    required this.publicKey,
    required this.displayName,
    this.signature,
  }) {
    if (publicKey.length != 32) {
      throw ArgumentError('Public key must be 32 bytes');
    }
    if (displayName.length > 63) {
      throw ArgumentError('Display name must be <= 63 bytes');
    }
    if (signature != null && signature!.length != 64) {
      throw ArgumentError('Signature must be 64 bytes');
    }
  }

  @override
  int get type => 0x21;

  @override
  Uint8List serialize() {
    final nameBytes = utf8.encode(displayName);
    final buffer = BytesBuilder();

    buffer.add(publicKey);
    buffer.addByte(nameBytes.length);
    buffer.add(nameBytes);
    if (signature != null) {
      buffer.add(signature!);
    }

    return buffer.toBytes();
  }

  static FriendAcceptPayload deserialize(Uint8List bytes) {
    if (bytes.length < 33) {  // 32 + 1 minimum
      throw FormatException('Friend accept payload too short');
    }

    final publicKey = bytes.sublist(0, 32);
    final nameLength = bytes[32];

    if (bytes.length < 33 + nameLength) {
      throw FormatException('Name length exceeds payload size');
    }

    final nameBytes = bytes.sublist(33, 33 + nameLength);
    final displayName = utf8.decode(nameBytes);

    Uint8List? signature;
    if (bytes.length >= 33 + nameLength + 64) {
      signature = bytes.sublist(33 + nameLength, 33 + nameLength + 64);
    }

    return FriendAcceptPayload(
      publicKey: publicKey,
      displayName: displayName,
      signature: signature,
    );
  }
}

/// Friend reject payload (0x22) - empty
class FriendRejectPayload extends MessagePayload {
  @override
  int get type => 0x22;

  @override
  Uint8List serialize() => Uint8List(0);

  static FriendRejectPayload deserialize(Uint8List bytes) {
    return FriendRejectPayload();
  }
}

/// Fragment header (4 bytes)
class FragmentHeader {
  final int messageId;      // 2 bytes
  final int fragmentIndex;  // 1 byte (0-based)
  final int totalFragments; // 1 byte

  FragmentHeader({
    required this.messageId,
    required this.fragmentIndex,
    required this.totalFragments,
  }) {
    if (fragmentIndex >= totalFragments) {
      throw ArgumentError('Fragment index must be < total fragments');
    }
    if (totalFragments > 255) {
      throw ArgumentError('Total fragments must be <= 255');
    }
  }

  Uint8List serialize() {
    final data = ByteData(4);
    data.setUint16(0, messageId, Endian.big);
    data.setUint8(2, fragmentIndex);
    data.setUint8(3, totalFragments);
    return data.buffer.asUint8List();
  }

  static FragmentHeader deserialize(Uint8List bytes) {
    if (bytes.length < 4) {
      throw FormatException('Fragment header must be 4 bytes');
    }

    final data = ByteData.view(bytes.buffer);
    return FragmentHeader(
      messageId: data.getUint16(0, Endian.big),
      fragmentIndex: data.getUint8(2),
      totalFragments: data.getUint8(3),
    );
  }
}

/// Fragment payload (0xF0, 0xF1, 0xF2)
class FragmentPayload extends MessagePayload {
  final FragmentHeader header;
  final Uint8List data;
  final int fragmentType;  // 0xF0, 0xF1, or 0xF2

  FragmentPayload({
    required this.header,
    required this.data,
    required this.fragmentType,
  }) {
    if (fragmentType != 0xF0 && fragmentType != 0xF1 && fragmentType != 0xF2) {
      throw ArgumentError('Invalid fragment type');
    }
  }

  @override
  int get type => fragmentType;

  @override
  Uint8List serialize() {
    final buffer = BytesBuilder();
    buffer.add(header.serialize());
    buffer.add(data);
    return buffer.toBytes();
  }

  static FragmentPayload deserialize(Uint8List bytes, int fragmentType) {
    if (bytes.length < 4) {
      throw FormatException('Fragment payload too short');
    }

    final header = FragmentHeader.deserialize(bytes.sublist(0, 4));
    final data = bytes.sublist(4);

    return FragmentPayload(
      header: header,
      data: data,
      fragmentType: fragmentType,
    );
  }
}
