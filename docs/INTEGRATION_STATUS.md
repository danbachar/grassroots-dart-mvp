# BLE Integration Status

## What We've Built

### ✅ Phase 1: Protocol Layer (Completed)
- **Packet format**: 14-byte header, serialization, deserialization
- **Message types**: All 15+ types from spec (chat, acks, friend requests, fragments)
- **Payload formats**: Chat, delivery ack, read receipt, friend request/accept/reject
- **Fragmentation**: Split/reassemble packets > 512 bytes
- **Constants**: Timeouts, limits, privacy levels, message status

### ✅ Phase 2: Core Services (Completed)
- **FriendshipService**: Friend request/accept/reject flows with cooldown tracking
- **MessageService**: Chat messages, acks, read receipts, retry queue
- **PrivacyService**: 4 privacy levels with behavior rules
- **FragmentationService**: Packet fragmentation and reassembly

### ✅ Phase 3: BLE Integration (Completed)

#### Fixed Library Issue
- **Problem**: `bluetooth_low_energy` doesn't allow both central and peripheral permissions
- **Solution**: Use **two libraries**:
  - `bluetooth_low_energy: ^6.1.0` - for Central (scanning/connecting)
  - `ble_peripheral: ^2.4.0` - for Peripheral (advertising)

#### BLEManager (`lib/ble/ble_manager.dart`)
- Abstracts both libraries behind a single interface
- Central operations: scanning, connecting, service discovery, writing characteristics
- Peripheral operations: advertising, handling write requests
- Callbacks for: device discovered, connection changed, data received

#### AppCoordinator (`lib/app_coordinator.dart`)
- Main controller that ties everything together
- Manages identity (PeerID, public keys, Service UUID)
- Coordinates BLE operations with protocol services
- Handles incoming packets and routes to appropriate services
- Provides clean interface for UI layer

Key features:
- Privacy-aware scanning (friends-only vs all devices)
- Automatic packet serialization/deserialization
- Fragment handling for large messages
- Friend request workflow
- Chat message delivery with acks

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                      UI Layer                            │
│  (BluetoothPage, ChatPage, Settings - TO BE UPDATED)    │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│                AppCoordinator                            │
│  - Ties everything together                              │
│  - Manages identity & connections                        │
│  - Routes packets to services                            │
└──┬──────────────┬──────────────┬────────────────────┬───┘
   │              │              │                    │
   ▼              ▼              ▼                    ▼
┌──────┐  ┌─────────────┐  ┌──────────┐   ┌─────────────┐
│ BLE  │  │ Friendship  │  │ Message  │   │   Privacy   │
│Manager│  │   Service   │  │ Service  │   │   Service   │
└───┬──┘  └─────────────┘  └──────────┘   └─────────────┘
    │
    │     ┌──────────────────┐  ┌──────────────────┐
    ├─────│bluetooth_low     │  │ ble_peripheral   │
    │     │_energy (Central) │  │ (Peripheral)     │
    └─────└──────────────────┘  └──────────────────┘
```

## How It Works

### 1. Initialization
```dart
final coordinator = AppCoordinator(myDisplayName: 'Alice');
await coordinator.initialize(); // Request BLE permissions
```

### 2. Advertising (Level 2+)
```dart
coordinator.setPrivacyLevel(PrivacyLevel.visible);
await coordinator.startAdvertising();
// Advertises with Service UUID derived from your public key
```

### 3. Scanning
```dart
await coordinator.startScan();
// Privacy Level 1-2: Scans only for friends' UUIDs
// Privacy Level 3-4: Scans for all devices
```

### 4. Pairing
```dart
final discovered = coordinator.scanResults.first;
await coordinator.pairDevice(discovered);
// Connects, discovers services, tracks connection
```

### 5. Sending Friend Request
```dart
await coordinator.sendFriendRequest(peer);
// Creates packet, serializes, sends via BLE characteristic
```

### 6. Receiving Data
```dart
coordinator.onFriendRequestReceived = (requester) {
  // Show UI dialog
  showFriendRequestDialog(requester);
};

// Coordinator automatically:
// 1. Receives bytes via BLE
// 2. Deserializes packet
// 3. Routes to appropriate service
// 4. Calls UI callbacks
```

### 7. Sending Messages
```dart
await coordinator.sendMessage(peer, 'Hello!');
// Creates packet, fragments if needed, sends via BLE
```

## What's Next

### ⏳ Phase 4: UI Refactoring (Pending)

Need to update existing UI to use new coordinator:

1. **BluetoothPage** (`lib/main.dart:222-709`)
   - Replace direct BLE calls with `AppCoordinator`
   - Use `coordinator.friends` instead of `_pairedDevices`
   - Use `coordinator.scanResults` instead of `_scanResults`
   - Remove BLE subscription boilerplate

2. **ChatPage** (`lib/main.dart:711-858`)
   - Use `coordinator.getChat(peer)` for messages
   - Use `Message` model instead of `ChatMessage`
   - Show delivery/read status from protocol

3. **Add Privacy Selector**
   - New UI for selecting privacy level (1-4)
   - Show current level and description
   - Update advertising/scanning behavior on change

4. **Add Friend Request Dialog**
   - Show when `onFriendRequestReceived` fires
   - Display requester name and public key fingerprint
   - Accept/Reject buttons
   - Show cooldown status if rejected

### ⏳ Phase 5: Database Persistence (Pending)

Replace in-memory storage with SQLite:

1. Add `sqflite` dependency
2. Create schema (friends, messages, metadata tables)
3. Create repositories
4. Update services to use repositories

### ⏳ Phase 6: Routing & Store-and-Forward (Pending)

1. Bloom filter for packet deduplication
2. TTL-based message forwarding
3. Relay policy (friends & friends-of-friends)
4. Store-and-forward queue with expiry

### 🔜 Phase 7: Cryptography (Deferred)

1. Key generation (Curve25519, Ed25519)
2. Noise Protocol Framework handshake
3. Packet encryption/decryption
4. Signature verification

## Key Design Decisions

### 1. Dual BLE Library Approach
- **Why**: Single library doesn't support both central and peripheral permissions
- **How**: `bluetooth_low_energy` for central, `ble_peripheral` for peripheral
- **Benefit**: Clean abstraction in BLEManager hides implementation details

### 2. Service UUID Derivation
- **Protocol**: Last 128 bits of Curve25519 public key
- **Current**: Placeholder implementation (generates random keys)
- **TODO**: Generate proper cryptographic keys on first launch

### 3. Coordinator Pattern
- **Why**: Decouple UI from BLE and protocol layers
- **Benefit**: Easy to test, swap implementations, add features
- **Trade-off**: Extra layer of indirection

### 4. In-Memory Storage First
- **Why**: Faster to implement and test
- **Benefit**: Can add persistence without changing interfaces
- **Next**: Add SQLite repositories

## Testing the Integration

### Manual Test Plan

1. **Start two devices**
   ```dart
   Device A: Alice
   Device B: Bob
   ```

2. **Advertise on Device A**
   ```dart
   alice.setPrivacyLevel(PrivacyLevel.visible);
   alice.startAdvertising();
   // Should see "Started advertising" in logs
   ```

3. **Scan on Device B**
   ```dart
   bob.startScan();
   // Should discover Alice's Service UUID
   ```

4. **Pair from Device B**
   ```dart
   bob.pairDevice(aliceDiscovered);
   // Should connect, discover services
   ```

5. **Send Friend Request**
   ```dart
   bob.sendFriendRequest(alicePeer);
   // Should serialize packet, send via BLE
   ```

6. **Receive on Device A**
   ```dart
   // Alice's coordinator should:
   // 1. Receive bytes
   // 2. Deserialize packet
   // 3. Call onFriendRequestReceived
   ```

7. **Accept Request**
   ```dart
   alice.acceptFriendRequest(bobPeer);
   // Should send accept packet back to Bob
   ```

8. **Send Message**
   ```dart
   bob.sendMessage(alice, 'Hello!');
   // Should appear in Alice's chat
   ```

## Files Created

```
lib/
├── protocol/
│   ├── constants.dart         ✅ Protocol constants
│   ├── packet.dart            ✅ Packet serialization
│   └── payloads.dart          ✅ Message payloads
├── models/
│   ├── peer.dart              ✅ Peer model
│   ├── message.dart           ✅ Message model
│   └── connection_state.dart  ✅ Connection state machine
├── services/
│   ├── friendship_service.dart      ✅ Friend management
│   ├── message_service.dart         ✅ Chat messages
│   ├── privacy_service.dart         ✅ Privacy levels
│   └── fragmentation_service.dart   ✅ Packet fragmentation
├── ble/
│   └── ble_manager.dart       ✅ BLE abstraction
└── app_coordinator.dart       ✅ Main coordinator
```

## Next Steps

To continue the integration:

1. **Update BluetoothPage**: Replace direct BLE with AppCoordinator
2. **Update ChatPage**: Use Message model and packet protocol
3. **Add Privacy UI**: Selector for privacy levels
4. **Add Friend Request Dialog**: Accept/reject UI
5. **Test end-to-end**: Two devices exchanging friend requests and messages

Would you like me to start refactoring the UI layer (BluetoothPage and ChatPage)?
