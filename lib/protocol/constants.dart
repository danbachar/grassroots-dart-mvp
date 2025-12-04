/// Protocol constants from the specification

// GATT Service/Characteristic UUIDs
const String FIXED_CHARACTERISTIC_UUID = 'A1B2C3D4-E5F6-4A5B-8C9D-0E1F2A3B4C5D';

// Dedicated characteristic for friend requests (sender connects and writes)
const String FRIEND_REQUEST_CHARACTERISTIC_UUID =
    'A1B2C3D4-E5F6-4A5B-8C9D-0E1F2A3B4C6D';

// Characteristic for friend responses (sender connects and writes accept/reject)
const String FRIEND_RESPONSE_CHARACTERISTIC_UUID =
    'A1B2C3D4-E5F6-4A5B-8C9D-0E1F2A3B4C7D';

// Characteristic for chat messages (sender connects and writes)
const String MESSAGE_CHARACTERISTIC_UUID =
    'A1B2C3D4-E5F6-4A5B-8C9D-0E1F2A3B4C8D';

// Message Types
class MessageType {
  // Chat messages
  static const int message = 0x01;
  static const int deliveryAck = 0x02;
  static const int readReceipt = 0x03;

  // Noise handshake (placeholders for future crypto implementation)
  static const int noiseHandshakeInit = 0x10;
  static const int noiseHandshakeResp = 0x11;
  static const int noiseHandshakeFinal = 0x12;

  // Friendship management
  static const int friendRequest = 0x20;
  static const int friendAccept = 0x21;
  static const int friendReject = 0x22;

  // Social features
  static const int introduction = 0x30;
  static const int friendListShare = 0x31;

  // Fragmentation
  static const int fragmentStart = 0xF0;
  static const int fragmentContinue = 0xF1;
  static const int fragmentEnd = 0xF2;
}

// Flags
class PacketFlags {
  static const int hasRecipient = 1 << 0; // Bit 0
  static const int hasSignature = 1 << 1; // Bit 1
  static const int isCompressed = 1 << 2; // Bit 2
  static const int hasRoute = 1 << 3; // Bit 3
}

// Timeouts (in milliseconds)
class Timeouts {
  static const int connection = 10000; // 10s
  static const int handshake = 10000; // 10s
  static const int idle = 60000; // 60s
  static const int fragment = 30000; // 30s
  static const int retryInitial = 2000; // 2s
  static const int retryMax = 16000; // 16s
  static const int friendCooldown = 300000; // 300s (5 min)
  static const int messageExpiry = 86400000; // 24 hours
  static const int bloomRotation = 300000; // 5 min
}

// Limits
class Limits {
  static const int maxMessageSize = 65535;
  static const int maxDisplayName = 63;
  static const int maxFriends = 1000;
  static const int maxPendingMessages = 100;
  static const int maxFragments = 255;
  static const int defaultTTL = 7;
  static const int bleMTU = 512;
  static const int rssiThreshold = -50; // dBm for proximity check
}

// Privacy Levels
class PrivacyLevel {
  static const int silent = 1; // No advertising
  static const int visible = 2; // Advertise with UUID only
  static const int open = 3; // Advertise with name, scan all
  static const int social = 4; // Share friend lists
}

// Message Status
class MessageStatus {
  static const int pending = 0;
  static const int sent = 1;
  static const int delivered = 2;
  static const int read = 3;
}

// Retry Configuration
class RetryConfig {
  static const int maxRetries = 4;
  static const List<int> backoffDelays = [2000, 4000, 8000, 16000]; // ms
}
