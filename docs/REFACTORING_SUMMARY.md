# Refactoring Summary

## What We've Built

We've created a properly layered architecture aligned with the protocol specification, without implementing cryptography yet.

### Protocol Layer (`lib/protocol/`)

**constants.dart**
- Message types (0x01-0xF2): chat, acks, handshakes, friend requests, fragments
- Packet flags: hasRecipient, hasSignature, isCompressed, hasRoute
- Timeouts: connection, handshake, idle, fragment, retry delays
- Limits: max message size, MTU, TTL, RSSI threshold
- Privacy levels (1-4): Silent, Visible, Open, Social
- Message status: pending, sent, delivered, read

**packet.dart**
- 14-byte header format: version, type, TTL, flags, timestamp, payloadLength
- Variable fields: senderId (8 bytes), recipientId (8 bytes), payload, signature (64 bytes)
- Serialization/deserialization with big-endian encoding
- TTL management for routing

**payloads.dart**
- ChatMessagePayload (0x01): messageId (16 bytes), content
- DeliveryAckPayload (0x02): messageId
- ReadReceiptPayload (0x03): messageId
- FriendRequestPayload (0x20): requesterPk, requesterSignPk, displayName, signature
- FriendAcceptPayload (0x21): accepterPk, accepterSignPk, displayName, signature
- FriendRejectPayload (0x22): empty
- FragmentPayload (0xF0-0xF2): header (4 bytes) + data

### Models (`lib/models/`)

**peer.dart**
- Peer: peerId (8 bytes), noisePk (32 bytes), signPk (32 bytes), displayName
- Service UUID derivation from public key (last 128 bits)
- If peer is in database → they are your friend (no separate flag)

**message.dart**
- Message: messageId (16 bytes), senderId, recipientId, content, timestamp, status, retryCount, TTL
- Status helpers: isPending, isSent, isDelivered, isRead
- Retry logic: shouldRetry(), getRetryDelay(), exponential backoff
- Expiry check for store-and-forward (24 hours)

**connection_state.dart**
- ConnectionState enum: idle, connecting, handshaking, established, disconnected
- PeerConnection: peripheralId (OS-assigned BLE UUID), state, timestamps, handshakeAttempts
- Timeout detection: handshake (10s), idle (60s)

### Services (`lib/services/`)

**friendship_service.dart**
- Friend list management (in-memory, will be replaced with DB)
- createFriendRequest(): Generate friend request packet
- handleFriendRequest(): Parse incoming request, return Peer object
- acceptFriendRequest(): Add friend, create accept packet
- rejectFriendRequest(): Set cooldown (5 min), create reject packet
- Cooldown tracking to prevent spam

**privacy_service.dart**
- Privacy level management (1-4)
- Behavior checks:
  - shouldAdvertise: Level 2+
  - shouldScanAll: Level 3+ (else scan friends only)
  - shouldAdvertiseName: Level 3+
  - shouldShareFriendList: Level 4 only
  - shouldRelayMessages: Level 2+

**message_service.dart**
- Chat message management (in-memory)
- createChatMessage(): Generate random messageId, create packet
- handleChatMessage(): Parse incoming message, store in chat history
- Delivery acks and read receipts
- Pending message queue for retry
- Expired message cleanup

**fragmentation_service.dart**
- Fragment large packets (> 512 bytes MTU)
- fragmentPacket(): Split into fragments with 4-byte headers
- processFragment(): Reassemble when all fragments received
- Fragment timeout cleanup (30s)

## Architecture Overview

```
lib/
├── protocol/           # Wire format (bytes ↔ packets)
│   ├── constants.dart
│   ├── packet.dart
│   └── payloads.dart
├── models/            # Data structures
│   ├── peer.dart
│   ├── message.dart
│   └── connection_state.dart
├── services/          # Business logic
│   ├── friendship_service.dart
│   ├── privacy_service.dart
│   ├── message_service.dart
│   └── fragmentation_service.dart
└── main.dart          # Existing UI (to be refactored)
```

## What's NOT Implemented Yet

1. **Cryptography** (intentionally skipped)
   - Noise Protocol Framework handshake
   - Ed25519 signatures
   - Key derivation from fingerprints

2. **Database Persistence**
   - SQLite for friends, messages, metadata
   - Currently using in-memory storage

3. **BLE Integration**
   - Need to refactor existing BLE code in main.dart
   - Connect protocol layer to BLE transport

4. **Routing & Store-and-Forward**
   - TTL-based flooding
   - Bloom filter for deduplication
   - Relay policy enforcement

5. **Bloom Filters**
   - Friend list sharing (Level 4)
   - Packet deduplication

6. **UI Updates**
   - Refactor existing UI to use new services
   - Privacy level selector
   - Friend request prompts

## Next Steps

### Option 1: Add Database Persistence
- Install sqflite package
- Create database schema (friends, messages, metadata)
- Create repositories for data access
- Replace in-memory storage in services

### Option 2: Integrate with Existing BLE Code
- Refactor main.dart to use new services
- Connect packet serialization to BLE GATT writes
- Handle incoming BLE data through packet deserialization
- Update UI to show connection states

### Option 3: Implement Routing Layer
- Bloom filter for packet deduplication
- TTL-based message forwarding
- Store-and-forward queue with expiry
- Relay policy based on friend/friend-of-friend

## How to Use (Example)

```dart
// Initialize services
final friendshipService = FriendshipService();
final messageService = MessageService();
final privacyService = PrivacyService();
final fragmentationService = FragmentationService();

// Set privacy level
privacyService.setPrivacyLevel(PrivacyLevel.open);

// Create friend request
final requestPacket = friendshipService.createFriendRequest(
  myPeerId: myPeerId,
  myNoisePk: myNoisePk,
  mySignPk: mySignPk,
  myDisplayName: 'Alice',
  recipientId: bobPeerId,
);

// Serialize and send via BLE
final bytes = requestPacket.serialize();
await bleManager.write(peripheral, characteristic, bytes);

// Receive and handle
final incomingPacket = Packet.deserialize(receivedBytes);
if (incomingPacket.type == MessageType.friendRequest) {
  final requester = friendshipService.handleFriendRequest(incomingPacket);

  // Show UI prompt
  if (userAccepts) {
    final acceptPacket = friendshipService.acceptFriendRequest(
      myPeerId: myPeerId,
      myNoisePk: myNoisePk,
      mySignPk: mySignPk,
      myDisplayName: 'Bob',
      requester: requester,
    );
    await bleManager.write(peripheral, characteristic, acceptPacket.serialize());
  }
}
```

## Protocol Compliance

| Feature | Protocol Spec | Implementation Status |
|---------|---------------|----------------------|
| 14-byte packet header | Required | ✅ Complete |
| Message types 0x01-0xF2 | Required | ✅ Complete |
| Fragmentation | Required | ✅ Complete |
| Privacy levels 1-4 | Required | ✅ Complete |
| Friend requests | Required | ✅ Complete |
| Connection state machine | Required | ✅ Complete |
| TTL-based routing | Required | ⏳ Pending |
| Noise Protocol | Required | 🔜 Deferred (crypto skipped) |
| Ed25519 signatures | Required | 🔜 Deferred (crypto skipped) |
| Bloom filters | Required | ⏳ Pending |
| SQLite persistence | Required | ⏳ Pending |

## Key Design Decisions

1. **No viaFriend in Peer model**: Friend-of-friend relationships computed dynamically using Bloom filters (Level 4), not stored statically

2. **Separate Peer vs PeerConnection**: Peer = persistent friend in DB; PeerConnection = ephemeral BLE connection state

3. **Service UUID vs Peripheral UUID**: Service UUID derived from public key (discovery); Peripheral UUID assigned by OS (connection management)

4. **Services return Packet objects**: Caller decides when/how to send over BLE; services don't touch transport layer

5. **In-memory storage first**: Easier to test and refactor; database can be added without changing interfaces
