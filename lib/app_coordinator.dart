import 'dart:async';
import 'dart:typed_data';
import 'package:bluetooth_low_energy/bluetooth_low_energy.dart'
    hide ConnectionState;
import 'package:bluetooth_low_energy/bluetooth_low_energy.dart'
    as ble
    show ConnectionState;
import 'package:flutter/material.dart' hide ConnectionState;

import 'ble/ble_manager.dart';
import 'models/message.dart';
import 'models/peer.dart';
import 'protocol/constants.dart';
import 'protocol/packet.dart';
import 'services/database_service.dart';
import 'services/friendship_service.dart';
import 'services/identity_service.dart';
import 'services/message_service.dart';
import 'services/privacy_service.dart';

/// Coordinates BLE operations with protocol services
/// This is the main controller that ties everything together
///
/// Architecture: "Always Advertising + Connect-to-Send"
/// - All devices continuously advertise their service UUID
/// - To send any message, sender connects to target, writes to characteristic, disconnects
/// - Three characteristics: friend requests, friend responses, messages
class AppCoordinator extends ChangeNotifier {
  /// Get the current display name
  String get myDisplayName => _identityService.displayName;

  /// Get my public key (Ed25519, 32 bytes) - this IS my identity
  Uint8List get myPublicKey => _identityService.publicKey;

  /// Get my service UUID (derived from public key)
  String get myServiceUUID => _identityService.deriveServiceUUID();

  // Managers and services
  final BLEManager _bleManager;
  final DatabaseService _databaseService;
  final IdentityService _identityService;
  late final FriendshipService _friendshipService;
  late final MessageService _messageService;
  final PrivacyService _privacyService;

  // Nearby peers - automatically discovered Grassroots devices (not persisted)
  final List<Peer> _nearbyPeers = [];

  // State - simplified
  final List<DiscoveredEventArgs> _scanResults = [];

  // Cache discovered peripherals by their peripheral UUID for sending messages
  final Map<String, DiscoveredEventArgs> _discoveredDevices =
      {}; // peripheralId -> DiscoveredEventArgs

  // Pending operations - temporarily store info for async operations
  final Map<String, DiscoveredEventArgs> _pendingFriendRequests =
      {}; // peripheralId -> device (waiting for connection)

  // Pending message queue for offline delivery
  final Map<String, List<Packet>> _pendingMessages = {}; // peerIdHex -> packets

  // Track friends who are in range (their service UUID was discovered)
  final Set<String> _friendsInRange = {}; // peerIdHex

  // Track friends we're currently auto-connecting to (prevent duplicate connections)
  final Set<String> _autoConnectingTo = {}; // peerIdHex

  // Track the deviceId of requesters so we can notify them back
  final Map<String, Peer> _friendRequestSenders = {}; // deviceId -> requester

  // Device cache with timestamps (10-minute TTL)
  // peripheralId -> (DiscoveredEventArgs, DateTime lastSeen)
  final Map<String, _CachedDevice> _deviceCache = {};
  static const Duration _cacheTTL = Duration(minutes: 10);

  // Track devices verified to have our required characteristics
  final Set<String> _compatibleDevices = {}; // peripheralId

  // Scanning/advertising runs continuously while app is open
  Timer? _scanRestartTimer;
  Timer? _cacheCleanupTimer;
  
  // Scan settings - continuous scanning with brief pauses
  static const Duration _scanDuration = Duration(seconds: 10);
  static const Duration _scanPause = Duration(seconds: 5);
  static const Duration _cacheCleanupInterval = Duration(minutes: 1);

  // Callbacks for UI
  void Function(Peer)? onFriendRequestReceived;
  void Function(Message, Peer)? onMessageReceived;  // For notifications
  void Function(Peer)? onFriendAdded;  // Called when a friend request is accepted (for snackbar)

  // Track pending outgoing friend requests (peripheral UUID -> true)
  final Set<String> _pendingOutgoingRequests = {};

  // Track currently open chat for immediate read receipts
  Uint8List? _activeChatPeerId;

  AppCoordinator()
    : _bleManager = BLEManager(),
      _databaseService = DatabaseService(),
      _identityService = IdentityService(),
      _privacyService = PrivacyService() {
    // Initialize services with shared database instance
    _friendshipService = FriendshipService(_databaseService);
    _messageService = MessageService(_databaseService);
    _setupBLECallbacks();
  }

  /// Regenerate identity (new key pairs, new service UUID)
  Future<void> regenerateIdentity() async {
    await _identityService.generateNewIdentity();

    print('Generated new identity');
    print('Service UUID: $myServiceUUID');
    print('Public Key: ${_bytesToHex(myPublicKey)}');

    // Restart advertising with new identity if currently advertising
    if (_bleManager.isAdvertising) {
      await stopAdvertising();
      await startAdvertising();
    }

    notifyListeners();
  }
  
  /// Update the display name
  Future<void> setDisplayName(String name) async {
    if (name.trim().isEmpty) return;

    await _identityService.setDisplayName(name);

    // Restart advertising with new name if currently advertising
    if (_bleManager.isAdvertising) {
      await stopAdvertising();
      await startAdvertising();
    }

    notifyListeners();
  }

  /// Setup BLE callbacks
  void _setupBLECallbacks() {
    _bleManager.onDeviceDiscovered = _handleDeviceDiscovered;
    _bleManager.onCentralConnectionChanged = _handleConnectionChanged;
    _bleManager.onCharacteristicDataReceived = _handleCharacteristicData;
  }

  /// Initialize BLE (request permissions) and start continuous operation
  Future<void> initialize() async {
    // Initialize cryptographic identity (load or generate keys and display name)
    await _identityService.initialize();
    print('Identity initialized');
    print('Service UUID: $myServiceUUID');
    print('Public Key: ${_bytesToHex(myPublicKey)}');
    print('Display Name: $myDisplayName');

    // Load persisted data from database
    await _friendshipService.initialize();
    await _messageService.initialize();
    print('AppCoordinator: Database initialized with ${friends.length} friends');

    await _bleManager.initialize();

    // Start cache cleanup timer
    _cacheCleanupTimer = Timer.periodic(_cacheCleanupInterval, (_) {
      _cleanupExpiredCache();
    });

    // Start continuous scanning and advertising
    _startContinuousOperation();

    notifyListeners();
  }

  // ==================== Getters ====================

  List<Peer> get friends => _friendshipService.friends;
  
  /// Get list of auto-discovered nearby Grassroots peers (not persisted)
  List<Peer> get nearbyPeers => List.unmodifiable(_nearbyPeers);
  
  /// Check if a peer is in the nearby peers list by peripheral ID
  bool isNearbyPeer(String peripheralId) {
    return _nearbyPeers.any((p) => p.peripheral?.uuid.toString() == peripheralId);
  }
  
  /// Get set of peripheral UUIDs with pending friend requests
  Set<String> get pendingOutgoingRequests => Set.unmodifiable(_pendingOutgoingRequests);
  
  /// Check if a friend request is pending for a specific peripheral
  bool isPendingFriendRequest(String peripheralId) {
    return _pendingOutgoingRequests.contains(peripheralId);
  }
  
  /// Get scan results filtered to only show compatible Grassroots devices
  List<DiscoveredEventArgs> get scanResults {
    return _scanResults.where((r) {
      final peripheralId = r.peripheral.uuid.toString();
      return _compatibleDevices.contains(peripheralId);
    }).toList();
  }
  
  /// Get all discovered devices (including non-compatible)
  List<DiscoveredEventArgs> get allDiscoveredDevices => _scanResults;
  
  bool get isScanning => _bleManager.isScanning;
  bool get isAdvertising => _bleManager.isAdvertising;
  int get privacyLevel => _privacyService.privacyLevel;
  String get privacyLevelName => _privacyService.privacyLevelName;

  /// Check if a friend is currently in range (found in cache within TTL)
  bool isFriendInRange(Peer friend) {
    final serviceUUID = friend.deriveServiceUUID().toLowerCase();

    for (final cached in _deviceCache.values) {
      if (cached.isExpired) continue;

      for (final uuid in cached.device.advertisement.serviceUUIDs) {
        if (uuid.toString().toLowerCase() == serviceUUID) {
          return true;
        }
      }
    }
    return false;
  }

  /// Get list of friends currently in range
  List<Peer> get friendsInRange {
    return friends.where((f) => isFriendInRange(f)).toList();
  }

  // ==================== Privacy ====================

  void setPrivacyLevel(int level) {
    _privacyService.setPrivacyLevel(level);
    // Restart operation with new privacy settings
    _startContinuousOperation();
    notifyListeners();
  }

  // ==================== Scanning ====================

  Future<void> startScan() async {
    if (_privacyService.shouldScanAll) {
      // Level 3+: Scan for all devices
      await _bleManager.startScan();
    } else {
      // Level 1-2: Scan only for friends' service UUIDs
      final friendUUIDs = friends
          .map((f) => f.deriveServiceUUID())
          .map((uuid) => UUID.fromString(uuid))
          .toList();

      if (friendUUIDs.isNotEmpty) {
        await _bleManager.startScan(serviceUUIDs: friendUUIDs);
      }
    }
    notifyListeners();
  }

  Future<void> stopScan() async {
    await _bleManager.stopScan();
    // Note: Don't clear scan results or cache
    notifyListeners();
  }

  // ==================== Continuous Operation ====================

  /// Start continuous scanning and advertising (respects privacy settings)
  void _startContinuousOperation() {
    // Stop any existing timers
    _scanRestartTimer?.cancel();
    
    // Start advertising if privacy allows
    if (_privacyService.shouldAdvertise) {
      print("App coordinator starting advertisement");
      startAdvertising();
    } else {
      print("App coordinator stopping advertisement");
      stopAdvertising();
    }
    
    // Start continuous scanning cycle
    _runContinuousScan();
  }

  /// Run continuous scan cycle
  Future<void> _runContinuousScan() async {
    // Start scanning
    await startScan();
    
    // After scan duration, pause briefly then restart
    _scanRestartTimer = Timer(_scanDuration, () async {
      if (_bleManager.isScanning) {
        await _bleManager.stopScan();
        notifyListeners();
      }
      
      // Brief pause then restart
      _scanRestartTimer = Timer(_scanPause, () {
        _runContinuousScan();
      });
    });
  }

  /// Stop all continuous operation
  void stopContinuousOperation() {
    _scanRestartTimer?.cancel();
    _scanRestartTimer = null;
    stopScan();
    stopAdvertising();
    print('Stopped continuous operation');
    notifyListeners();
  }

  /// Clear all discovered devices and nearby peers, then force start a fresh scan
  Future<void> clearAndRescan() async {
    print('Clearing nearby peers and restarting scan...');
    
    // Clear all discovered data
    _nearbyPeers.clear();
    _scanResults.clear();
    _discoveredDevices.clear();
    _deviceCache.clear();
    _compatibleDevices.clear();
    _friendsInRange.clear();
    
    // Notify UI immediately to show cleared state
    notifyListeners();
    
    // Stop current scan if running
    if (_bleManager.isScanning) {
      await _bleManager.stopScan();
    }
    
    // Cancel any existing scan timer
    _scanRestartTimer?.cancel();
    
    // Start fresh scan
    await startScan();
    
    // Restart the continuous scan cycle
    _scanRestartTimer = Timer(_scanDuration, () async {
      if (_bleManager.isScanning) {
        await _bleManager.stopScan();
        notifyListeners();
      }
      _scanRestartTimer = Timer(_scanPause, () {
        _runContinuousScan();
      });
    });
  }

  /// Clean up expired entries from device cache and nearby peers
  void _cleanupExpiredCache() {
    final expiredKeys = <String>[];

    for (final entry in _deviceCache.entries) {
      if (entry.value.isExpired) {
        expiredKeys.add(entry.key);
      }
    }

    for (final key in expiredKeys) {
      _deviceCache.remove(key);
      _compatibleDevices.remove(key);
      
      // Also remove from nearby peers
      _nearbyPeers.removeWhere(
        (p) => p.peripheral?.uuid.toString() == key,
      );
    }

    if (expiredKeys.isNotEmpty) {
      print('Cleaned up ${expiredKeys.length} expired cache entries');
      _friendsInRange.clear(); // Recalculate on next discovery
      notifyListeners();
    }
  }

  /// Get a device from cache by service UUID (if not expired)
  DiscoveredEventArgs? getDeviceByServiceUUID(String serviceUUID) {
    final lowerUUID = serviceUUID.toLowerCase();

    for (final cached in _deviceCache.values) {
      if (cached.isExpired) continue;

      for (final uuid in cached.device.advertisement.serviceUUIDs) {
        if (uuid.toString().toLowerCase() == lowerUUID) {
          return cached.device;
        }
      }
    }
    return null;
  }

  // ==================== Advertising ====================

  Future<void> startAdvertising() async {
    if (!_privacyService.shouldAdvertise) {
      print(
        'Cannot advertise at privacy level ${_privacyService.privacyLevel}',
      );
      return;
    }

    // Use display name if privacy allows, otherwise use generic name
    // Truncate to 10 chars max to fit in BLE advertising packet (31 bytes total)
    // 128-bit UUID (18 bytes) + name (10 bytes) + flags (3 bytes) = 31 bytes
    String name;
    if (_privacyService.shouldAdvertiseName) {
      name = myDisplayName.length > 10
          ? myDisplayName.substring(0, 10)
          : myDisplayName;
    } else {
      name = 'Grassroots'; // 10 chars
    }

    print("Starting advertising as $name with UUID $myServiceUUID in appCoordinator");
    await _bleManager.startAdvertising(
      serviceUUID: myServiceUUID,
      deviceName: name
    );
    notifyListeners();
  }

  Future<void> stopAdvertising() async {
    await _bleManager.stopAdvertising();
    notifyListeners();
  }

  // ==================== Friend Requests ====================

  /// Send a friend request to a discovered device
  /// With auto-connect: devices should already be connected, just write directly
  Future<void> sendFriendRequest(DiscoveredEventArgs deviceArgs) async {
    final peripheral = deviceArgs.peripheral;
    final peripheralId = peripheral.uuid.toString();
    final deviceName = deviceArgs.advertisement.name ?? 'Unknown';

    print('Sending friend request to $deviceName ($peripheralId)...');

    // Track as pending outgoing request (for UI to show greyed out state)
    _pendingOutgoingRequests.add(peripheralId);
    notifyListeners();

    // Check if already connected and services are cached
    if (_bleManager.hasDiscoveredServices(peripheralId)) {
      // Already connected with services cached - send directly!
      print('Using existing connection to send friend request');
      await _sendFriendRequestDirect(peripheral, deviceName);
    } else {
      // Not connected yet - use old flow via connection callback
      print('Not yet connected, this should not be possible...');
      // _pendingFriendRequests[peripheralId] = deviceArgs;
      // await _bleManager.connect(peripheral);
    }
  }

  /// Send friend request directly on an existing connection
  Future<void> _sendFriendRequestDirect(Peripheral peripheral, String deviceName) async {
    final peripheralId = peripheral.uuid.toString();

    try {
      // Get cached services
      final services = _bleManager.getDiscoveredServices(peripheralId)!;

      // Find friend request and response characteristics
      GATTCharacteristic? friendRequestChar;
      GATTCharacteristic? friendResponseChar;

      for (final service in services) {
        for (final char in service.characteristics) {
          final charUuid = char.uuid.toString().toLowerCase();
          if (charUuid == FRIEND_REQUEST_CHARACTERISTIC_UUID.toLowerCase()) {
            friendRequestChar = char;
          } else if (charUuid == FRIEND_RESPONSE_CHARACTERISTIC_UUID.toLowerCase()) {
            friendResponseChar = char;
          }
        }
      }

      if (friendRequestChar == null) {
        print('Warning: Friend request characteristic not found');
        return;
      }

      // Subscribe to friend response to receive accept/reject
      if (friendResponseChar != null) {
        try {
          print('Subscribing to friend response characteristic...');
          await _bleManager.subscribeToCharacteristic(
            peripheral: peripheral,
            characteristic: friendResponseChar,
          );
        } catch (e) {
          print('Warning: Could not subscribe to responses: $e');
        }
      }

      // Create and send the friend request
      final packet = _friendshipService.createFriendRequest(
        myPublicKey: myPublicKey,
        myDisplayName: myDisplayName,
        recipientId: Uint8List(32), // Unknown at this point (32 bytes for public key)
      );

      final bytes = packet.serialize();
      print('Sending friend request: ${bytes.length} bytes');

      await _bleManager.writeCharacteristic(
        peripheral: peripheral,
        characteristicUUID: UUID.fromString(FRIEND_REQUEST_CHARACTERISTIC_UUID),
        data: bytes,
      );

      print('Friend request sent to $deviceName (using existing connection)');
    } catch (e) {
      print('Error sending friend request directly: $e');
    }
  }

  /// Accept a friend request from a peer
  /// Notify the requester who is still connected and subscribed
  Future<void> acceptFriendRequest(Peer requester) async {
    // Check if we already processed this request (prevent double-tap)
    if (_friendshipService.isFriend(requester.publicKey)) {
      print(
        'Already friends with ${requester.displayName}, ignoring duplicate accept',
      );
      return;
    }

    // Add as friend
    final packet = _friendshipService.acceptFriendRequest(
      myPublicKey: myPublicKey,
      myDisplayName: myDisplayName,
      requester: requester,
    );

    // Find the deviceId of the requester (they should still be connected)
    String? requesterDeviceId;
    for (final entry in _friendRequestSenders.entries) {
      if (_bytesEqual(entry.value.publicKey, requester.publicKey)) {
        requesterDeviceId = entry.key;
        break;
      }
    }

    if (requesterDeviceId != null) {
      // Notify the requester with acceptance
      print('Notifying requester $requesterDeviceId with acceptance...');
      try {
        final bytes = packet.serialize();
        await _bleManager.notifyCharacteristic(
          deviceId: requesterDeviceId,
          characteristicId: FRIEND_RESPONSE_CHARACTERISTIC_UUID,
          data: bytes,
        );
        print('Accept notification sent to requester');

        // Clean up
        _friendRequestSenders.remove(requesterDeviceId);
      } catch (e) {
        print('Error notifying requester: $e');
      }
    } else {
      print('Requester not connected to receive accept notification');
      // Friend is added locally, they will see us as friend when they reconnect
    }

    notifyListeners();
  }

  /// Reject a friend request from a peer
  Future<void> rejectFriendRequest(Peer requester) async {
    // Create reject packet
    final packet = _friendshipService.rejectFriendRequest(
      myPublicKey: myPublicKey,
      requester: requester,
    );

    // Find the deviceId of the requester (they should still be connected)
    String? requesterDeviceId;
    for (final entry in _friendRequestSenders.entries) {
      if (_bytesEqual(entry.value.publicKey, requester.publicKey)) {
        requesterDeviceId = entry.key;
        break;
      }
    }

    if (requesterDeviceId != null) {
      // Notify the requester with rejection
      print('Notifying requester $requesterDeviceId with rejection...');
      try {
        final bytes = packet.serialize();
        await _bleManager.notifyCharacteristic(
          deviceId: requesterDeviceId,
          characteristicId: FRIEND_RESPONSE_CHARACTERISTIC_UUID,
          data: bytes,
        );
        print('Reject notification sent to requester');

        // Clean up
        _friendRequestSenders.remove(requesterDeviceId);
      } catch (e) {
        print('Error notifying requester: $e');
      }
    } else {
      print('Requester not connected to receive reject notification');
    }
  }

  /// Remove a friend
  Future<void> removeFriend(Peer friend) async {
    _friendshipService.removeFriend(friend.publicKey);
    print('Removed ${friend.displayName} from friends list');
    notifyListeners();
  }

  // ==================== Messaging ====================

  /// Send a chat message to a friend
  Future<void> sendMessage(Peer peer, String content) async {
    final packet = _messageService.createChatMessage(
      senderId: myPublicKey,
      recipientId: peer.publicKey,
      content: content,
    );

    // Extract messageId from packet payload for status tracking
    // ChatMessagePayload stores messageId in first 16 bytes
    final messageId = packet.payload.sublist(0, 16);

    // Find the friend's device by their service UUID
    final serviceUUID = peer.deriveServiceUUID();

    // Look for the device
    DiscoveredEventArgs? targetDevice;
    for (final device in _discoveredDevices.values) {
      for (final uuid in device.advertisement.serviceUUIDs) {
        if (uuid.toString().toLowerCase() == serviceUUID.toLowerCase()) {
          targetDevice = device;
          break;
        }
      }
      if (targetDevice != null) break;
    }

    // Notify UI immediately to show pending message
    notifyListeners();

    if (targetDevice != null) {
      // Connect and send - pass messageId to mark as sent on success
      await _connectAndSend(
        targetDevice.peripheral,
        MESSAGE_CHARACTERISTIC_UUID,
        packet,
        messageId: messageId,
      );
    } else {
      // Queue for later
      print('Friend not in range, queuing message for later');
      final peerIdHex = _bytesToHex(peer.publicKey);
      _pendingMessages[peerIdHex] ??= [];
      _pendingMessages[peerIdHex]!.add(packet);
    }
  }

  /// Get chat history with a peer
  List<Message> getChat(Peer peer) {
    return _messageService.getChat(peer.publicKey);
  }

  /// Count unread messages from a specific peer
  int getUnreadCount(Peer peer) {
    final messages = _messageService.getChat(peer.publicKey);
    int count = 0;
    for (final message in messages) {
      // Count messages FROM this peer that aren't read yet
      final isFromPeer = !_bytesEqual(message.senderId, myPublicKey);
      if (isFromPeer && message.status != MessageStatus.read) {
        count++;
      }
    }
    return count;
  }

  /// Check if there are any unread messages from a peer
  bool hasUnreadMessages(Peer peer) {
    return getUnreadCount(peer) > 0;
  }

  /// Mark all messages from a peer as read (when user opens the chat)
  /// Also sends read receipts to the peer if they're in range
  Future<void> markMessagesAsRead(Peer peer) async {
    final messages = _messageService.getChat(peer.publicKey);
    final unreadMessages = <Message>[];

    // Find messages from this peer that aren't yet marked as read
    for (final message in messages) {
      // Only mark messages FROM the friend (not our own messages)
      final isFromFriend = !_bytesEqual(message.senderId, myPublicKey);
      if (isFromFriend && message.status != MessageStatus.read) {
        _messageService.markAsRead(message.messageId);
        unreadMessages.add(message);
      }
    }

    if (unreadMessages.isEmpty) return;

    print('Marked ${unreadMessages.length} messages as read');
    notifyListeners();

    // Try to send read receipts if friend is in range
    final serviceUUID = peer.deriveServiceUUID();
    DiscoveredEventArgs? targetDevice;
    for (final device in _discoveredDevices.values) {
      for (final uuid in device.advertisement.serviceUUIDs) {
        if (uuid.toString().toLowerCase() == serviceUUID.toLowerCase()) {
          targetDevice = device;
          break;
        }
      }
      if (targetDevice != null) break;
    }

    if (targetDevice != null) {
      // Send read receipts for each message
      for (final message in unreadMessages) {
        final packet = _messageService.createReadReceipt(
          senderId: myPublicKey,
          recipientId: peer.publicKey,
          messageId: message.messageId,
        );
        // Fire and forget - don't wait for each one
        _connectAndSend(
          targetDevice.peripheral,
          MESSAGE_CHARACTERISTIC_UUID,
          packet,
        );
      }
    }
  }

  /// Send a read receipt for a single message (used for immediate receipts)
  Future<void> _sendReadReceiptForMessage(Message message) async {
    // Find the sender's device
    final senderPeerId = message.senderId;
    
    // Find sender in friends list to get their service UUID
    Peer? sender;
    for (final friend in friends) {
      if (_bytesEqual(friend.publicKey, senderPeerId)) {
        sender = friend;
        break;
      }
    }
    
    if (sender == null) {
      print('Cannot send read receipt - sender not in friends list');
      return;
    }
    
    final serviceUUID = sender.deriveServiceUUID();
    
    // Look for the device
    DiscoveredEventArgs? targetDevice;
    for (final device in _discoveredDevices.values) {
      for (final uuid in device.advertisement.serviceUUIDs) {
        if (uuid.toString().toLowerCase() == serviceUUID.toLowerCase()) {
          targetDevice = device;
          break;
        }
      }
      if (targetDevice != null) break;
    }
    
    if (targetDevice != null) {
      final packet = _messageService.createReadReceipt(
        senderId: myPublicKey,
        recipientId: senderPeerId,
        messageId: message.messageId,
      );
      // Fire and forget
      _connectAndSend(
        targetDevice.peripheral,
        MESSAGE_CHARACTERISTIC_UUID,
        packet,
      );
    } else {
      print('Sender not in range, cannot send read receipt immediately');
    }
  }

  /// Helper to compare byte arrays
  bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Set the currently active/open chat (for immediate read receipts)
  void setActiveChat(Peer? peer) {
    _activeChatPeerId = peer?.publicKey;
    print('Active chat set to: ${peer?.displayName ?? "none"}');
  }

  /// Check if a chat with this peer is currently open
  bool isChatOpen(Uint8List peerId) {
    if (_activeChatPeerId == null) return false;
    return _bytesEqual(_activeChatPeerId!, peerId);
  }

  // ==================== Internal: Connect and Send ====================

  /// Connect to a peripheral, write data to a characteristic, then disconnect
  /// Returns true if the write was successful (with response acknowledged)
  Future<bool> _connectAndSend(
    Peripheral peripheral,
    String characteristicUUID,
    Packet packet, {
    Uint8List? messageId, // Optional: message ID to mark as sent on success
  }) async {
    final peripheralId = peripheral.uuid.toString();
    print('Connecting to $peripheralId to send packet...');

    try {
      // Only connect if not already connected
      await _bleManager.connect(peripheral);

      // Wait a bit for connection to establish
      await Future.delayed(Duration(milliseconds: 500));

      // Check if we already have discovered services cached
      List<GATTService> services;
      if (_bleManager.hasDiscoveredServices(peripheralId)) {
        print('Reusing cached services for $peripheralId');
        services = _bleManager.getDiscoveredServices(peripheralId)!;
      } else {
        // Discover services
        services = await _bleManager.discoverServices(peripheral);
      }

      // Find the characteristic
      GATTCharacteristic? targetChar;
      for (final service in services) {
        for (final char in service.characteristics) {
          if (char.uuid.toString().toLowerCase() ==
              characteristicUUID.toLowerCase()) {
            targetChar = char;
            break;
          }
        }
        if (targetChar != null) break;
      }

      if (targetChar == null) {
        print('Warning: Characteristic $characteristicUUID not found');
        // Keep connection alive - maybe characteristics will appear later or for other operations
        return false;
      }

      // Send the packet
      final bytes = packet.serialize();
      print('Sending ${bytes.length} bytes to $characteristicUUID');

      await _bleManager.writeCharacteristic(
        peripheral: peripheral,
        characteristicUUID: UUID.fromString(characteristicUUID),
        data: bytes,
      );

      // Write with response succeeded - mark message as sent if messageId provided
      if (messageId != null) {
        _messageService.markAsSent(messageId);
        print('Message marked as sent');
        notifyListeners();
      }

      print('Packet sent successfully');
      // Keep connection alive for multi-hop routing - don't disconnect
      return true;
    } catch (e) {
      print('Error in connect-and-send: $e');
      // On error, still keep connection - it will be cleaned up by connection state monitoring
      return false;
    }
  }

  // ==================== Internal Handlers ====================

  void _handleDeviceDiscovered(DiscoveredEventArgs eventArgs) {
    // var arr = eventArgs.advertisement.manufacturerSpecificData;
    // for (final data in arr) {
    //   print('Manufacturer ID=${data.id}, Data=${data.data}');
    // }
    // print(eventArgs.advertisement.manufacturerSpecificData)
    final peripheralId = eventArgs.peripheral.uuid.toString();

    // Update device cache with timestamp
    _deviceCache[peripheralId] = _CachedDevice(eventArgs, DateTime.now());

    // Also keep in legacy discovered devices map for compatibility
    _discoveredDevices[peripheralId] = eventArgs;

    // Update scan results (keep all discovered for now)
    final index = _scanResults.indexWhere(
      (r) => r.peripheral.uuid.toString() == peripheralId,
    );
    if (index >= 0) {
      _scanResults[index] = eventArgs;
    } else {
      _scanResults.add(eventArgs);
    }

    // TODO: move these checks up, to show only supporting devices

    // Check if this device is compatible (has our characteristics)
    // We verify by checking if it advertises a service UUID that looks like ours
    // or by connecting and checking characteristics
    _verifyDeviceCompatibility(eventArgs);

    // Check if this device is a friend (by service UUID match)
    _checkIfFriendAndAutoConnect(eventArgs);

    // Check if this device matches any pending messages (by service UUID)
    _checkPendingMessagesForDevice(eventArgs);

    notifyListeners();
  }

  /// Verify if a device is a compatible Grassroots device
  Future<void> _verifyDeviceCompatibility(DiscoveredEventArgs device) async {
    final peripheralId = device.peripheral.uuid.toString();
    
    // Already verified - just update timestamp
    if (_compatibleDevices.contains(peripheralId)) {
      _updateNearbyPeerLastSeen(peripheralId, device);
      return;
    }
    
    // Quick check: if it has service UUIDs in advertisement, check format
    // Grassroots devices advertise a UUID derived from their noise PK
    // Format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx (standard UUID)
    if (device.advertisement.serviceUUIDs.isNotEmpty) {
      // For now, mark any device advertising services as potentially compatible
      // A more thorough check would connect and verify characteristics exist
      // But that's expensive, so we do it lazily when actually trying to communicate
      
      // Check if the device is advertising (has a name that's not empty)
      // This is a heuristic - Grassroots devices advertise with a name
      final name = device.advertisement.name;
      if (name != null && name.isNotEmpty) {
        _compatibleDevices.add(peripheralId);
        print('Device $name marked as compatible (has service UUIDs)');

        // Add to nearby peers list
        _addOrUpdateNearbyPeer(device);

        // Auto-connect to nearby Grassroots peer for multi-hop routing
        _autoConnectToNearbyPeer(device);
      }
    }
  }
  
  /// Add or update a nearby peer from a discovered device
  void _addOrUpdateNearbyPeer(DiscoveredEventArgs device) {
    final peripheralId = device.peripheral.uuid.toString();
    final deviceName = device.advertisement.name ?? 'Unknown Device';
    
    // Check if already in nearby peers
    final existingIndex = _nearbyPeers.indexWhere(
      (p) => p.peripheral?.uuid.toString() == peripheralId,
    );
    
    if (existingIndex >= 0) {
      // Update existing peer with fresh peripheral reference
      _nearbyPeers[existingIndex] = Peer(
        publicKey: _nearbyPeers[existingIndex].publicKey,
        displayName: deviceName,
        peripheral: device.peripheral,
        isVerified: false,
      );
    } else {
      // Create a temporary public key based on peripheral UUID
      // This will be replaced with actual public key after identity exchange
      final tempPublicKey = Uint8List(32);
      final peripheralBytes = peripheralId.codeUnits;
      for (int i = 0; i < 32 && i < peripheralBytes.length; i++) {
        tempPublicKey[i] = peripheralBytes[i] % 256;
      }
      
      final newPeer = Peer(
        publicKey: tempPublicKey,
        displayName: deviceName,
        peripheral: device.peripheral,
        isVerified: false,
      );
      
      _nearbyPeers.add(newPeer);
      print('Added nearby peer: $deviceName');
    }
  }
  
  /// Update lastSeen for an existing nearby peer
  void _updateNearbyPeerLastSeen(String peripheralId, DiscoveredEventArgs device) {
    final existingIndex = _nearbyPeers.indexWhere(
      (p) => p.peripheral?.uuid.toString() == peripheralId,
    );
    
    if (existingIndex >= 0) {
      // Update peripheral reference to keep it fresh
      final existing = _nearbyPeers[existingIndex];
      _nearbyPeers[existingIndex] = Peer(
        publicKey: existing.publicKey,
        displayName: device.advertisement.name ?? existing.displayName,
        peripheral: device.peripheral,
        isVerified: existing.isVerified,
      );
    }
  }

  /// Check if a discovered device is a friend and mark them as in-range
  void _checkIfFriendAndAutoConnect(DiscoveredEventArgs device) {
    for (final friend in friends) {
      final serviceUUID = friend.deriveServiceUUID();

      // Check if this device advertises the friend's service UUID
      for (final uuid in device.advertisement.serviceUUIDs) {
        if (uuid.toString().toLowerCase() == serviceUUID.toLowerCase()) {
          final peerIdHex = _bytesToHex(friend.publicKey);

          // Mark friend as in range
          if (!_friendsInRange.contains(peerIdHex)) {
            print('Friend ${friend.displayName} is now in range!');
            _friendsInRange.add(peerIdHex);

            // Auto-connect if not already connecting
            if (!_autoConnectingTo.contains(peerIdHex)) {
              _autoConnectToFriend(friend, device);
            }
          }
          return;
        }
      }
    }
  }

  /// Auto-connect to a nearby Grassroots peer for multi-hop routing
  Future<void> _autoConnectToNearbyPeer(DiscoveredEventArgs device) async {
    final peripheralId = device.peripheral.uuid.toString();
    final deviceName = device.advertisement.name ?? 'Unknown';

    // Prevent duplicate connection attempts (use peripheral ID as key)
    if (_autoConnectingTo.contains(peripheralId)) {
      return;
    }

    _autoConnectingTo.add(peripheralId);
    print('Auto-connecting to nearby peer $deviceName ($peripheralId)...');

    try {
      // Connect to the peer
      await _bleManager.connect(device.peripheral);
      print('Auto-connected to $deviceName');

      // Wait for connection to stabilize
      await Future.delayed(Duration(milliseconds: 500));

      // Discover and cache services so they're ready for later use
      final services = await _bleManager.discoverServices(device.peripheral);
      print('Discovered ${services.length} services for $deviceName');

      // Keep connection alive for multi-hop routing
      // Don't disconnect - we want to stay connected to all nearby peers
    } catch (e) {
      print('Error auto-connecting to nearby peer: $e');
    } finally {
      _autoConnectingTo.remove(peripheralId);
    }
  }

  /// Auto-connect to a friend who came into range
  Future<void> _autoConnectToFriend(
    Peer friend,
    DiscoveredEventArgs device,
  ) async {
    final peerIdHex = _bytesToHex(friend.publicKey);

    // Prevent duplicate connection attempts
    if (_autoConnectingTo.contains(peerIdHex)) {
      return;
    }

    _autoConnectingTo.add(peerIdHex);
    print('Auto-connecting to friend ${friend.displayName}...');

    try {
      // Check if there are pending messages to send
      final pending = _pendingMessages[peerIdHex];
      if (pending != null && pending.isNotEmpty) {
        print(
          'Sending ${pending.length} pending messages to ${friend.displayName}',
        );
        await _sendPendingMessages(device.peripheral, peerIdHex, pending);
      }
    } catch (e) {
      print('Error auto-connecting to friend: $e');
    } finally {
      _autoConnectingTo.remove(peerIdHex);
    }
  }

  void _checkPendingMessagesForDevice(DiscoveredEventArgs device) {
    // Check each friend's pending messages
    for (final friend in friends) {
      final serviceUUID = friend.deriveServiceUUID();

      // Check if this device advertises the friend's service UUID
      for (final uuid in device.advertisement.serviceUUIDs) {
        if (uuid.toString().toLowerCase() == serviceUUID.toLowerCase()) {
          final peerIdHex = _bytesToHex(friend.publicKey);
          final pending = _pendingMessages[peerIdHex];
          if (pending != null && pending.isNotEmpty) {
            print('Found device for pending messages to ${friend.displayName}');
            // Send pending messages
            _sendPendingMessages(device.peripheral, peerIdHex, pending);
          }
          break;
        }
      }
    }
  }

  Future<void> _sendPendingMessages(
    Peripheral peripheral,
    String peerIdHex,
    List<Packet> packets,
  ) async {
    print('Sending ${packets.length} pending messages...');

    // Clear pending list first to avoid duplicates
    _pendingMessages.remove(peerIdHex);

    for (final packet in packets) {
      // Determine characteristic based on packet type
      String charUUID;
      switch (packet.type) {
        case MessageType.friendAccept:
        case MessageType.friendReject:
          charUUID = FRIEND_RESPONSE_CHARACTERISTIC_UUID;
          break;
        case MessageType.message:
          charUUID = MESSAGE_CHARACTERISTIC_UUID;
          break;
        default:
          charUUID = MESSAGE_CHARACTERISTIC_UUID;
      }

      await _connectAndSend(peripheral, charUUID, packet);
    }
  }

  void _handleConnectionChanged(
    Peripheral peripheral,
    ble.ConnectionState state,
  ) {
    final peripheralId = peripheral.uuid.toString();
    print('Connection changed: $peripheralId -> $state');

    if (state == ble.ConnectionState.connected) {
      // Check if this is a pending friend request (we initiated)
      final pendingRequest = _pendingFriendRequests.remove(peripheralId);
      if (pendingRequest != null) {
        _handleFriendRequestConnection(peripheral, pendingRequest);
        return;
      }
    }

    notifyListeners();
  }

  /// Handle connection established for sending a friend request
  Future<void> _handleFriendRequestConnection(
    Peripheral peripheral,
    DiscoveredEventArgs deviceArgs,
  ) async {
    final deviceName = deviceArgs.advertisement.name ?? 'Unknown';

    print('Connected to $deviceName, discovering services...');

    try {
      final services = await _bleManager.discoverServices(peripheral);
      print('Discovered ${services.length} services');

      // Find friend request and response characteristics
      GATTCharacteristic? friendRequestChar;
      GATTCharacteristic? friendResponseChar;

      for (final service in services) {
        for (final char in service.characteristics) {
          final charUuid = char.uuid.toString().toLowerCase();
          if (charUuid == FRIEND_REQUEST_CHARACTERISTIC_UUID.toLowerCase()) {
            friendRequestChar = char;
          } else if (charUuid ==
              FRIEND_RESPONSE_CHARACTERISTIC_UUID.toLowerCase()) {
            friendResponseChar = char;
          }
        }
      }

      if (friendRequestChar == null) {
        print('Warning: Friend request characteristic not found');
        // Keep connection alive for multi-hop routing
        return;
      }

      // Subscribe to friend response to receive accept/reject
      if (friendResponseChar != null) {
        try {
          print('Subscribing to friend response characteristic...');
          await _bleManager.subscribeToCharacteristic(
            peripheral: peripheral,
            characteristic: friendResponseChar,
          );
        } catch (e) {
          print('Warning: Could not subscribe to responses: $e');
        }
      }

      // Create and send the friend request
      final packet = _friendshipService.createFriendRequest(
        myPublicKey: myPublicKey,
        myDisplayName: myDisplayName,
        recipientId: Uint8List(32), // Unknown at this point (32 bytes for public key)
      );

      final bytes = packet.serialize();
      print('Sending friend request: ${bytes.length} bytes');

      await _bleManager.writeCharacteristic(
        peripheral: peripheral,
        characteristicUUID: UUID.fromString(FRIEND_REQUEST_CHARACTERISTIC_UUID),
        data: bytes,
      );

      print('Friend request sent to $deviceName');
      // Stay connected to receive response via notification and for multi-hop routing
    } catch (e) {
      print('Error sending friend request: $e');
      // Keep connection alive even on error - for multi-hop routing
    }
  }

  /// Handle data received on a specific characteristic
  void _handleCharacteristicData(
    String deviceId,
    String characteristicId,
    Uint8List data,
  ) {
    print('Received ${data.length} bytes from $deviceId on $characteristicId');

    try {
      final packet = Packet.deserialize(data);
      print('Received packet type: 0x${packet.type.toRadixString(16)}');

      switch (packet.type) {
        case MessageType.friendRequest:
          _handleIncomingFriendRequest(deviceId, packet);
          break;

        case MessageType.friendAccept:
          final friend = _friendshipService.handleFriendAccept(packet);
          print('Friend request accepted by ${friend.displayName}');

          // Clear pending request for this friend (find by service UUID match)
          final acceptedServiceUUID = friend.deriveServiceUUID().toLowerCase();
          String? matchingPeripheralId;
          for (final entry in _deviceCache.entries) {
            for (final uuid in entry.value.device.advertisement.serviceUUIDs) {
              if (uuid.toString().toLowerCase() == acceptedServiceUUID) {
                matchingPeripheralId = entry.key;
                break;
              }
            }
            if (matchingPeripheralId != null) break;
          }
          if (matchingPeripheralId != null) {
            _pendingOutgoingRequests.remove(matchingPeripheralId);
          }

          // Notify UI for snackbar
          onFriendAdded?.call(friend);
          notifyListeners();
          break;

        case MessageType.friendReject:
          _friendshipService.handleFriendReject(packet);
          print('Friend request rejected');

          notifyListeners();
          break;

        case MessageType.message:
          final message = _messageService.handleChatMessage(packet);
          print('Received chat message: ${message.content}');
          
          // If the chat with this sender is currently open, immediately send read receipt
          if (isChatOpen(message.senderId)) {
            print('Chat is open, sending immediate read receipt');
            _messageService.markAsRead(message.messageId);
            _sendReadReceiptForMessage(message);
          } else {
            // Chat is not open - notify UI for banner notification
            final sender = _friendshipService.getFriend(message.senderId);
            if (sender != null) {
              onMessageReceived?.call(message, sender);
            }
          }
          
          notifyListeners();
          break;

        case MessageType.deliveryAck:
          _messageService.handleDeliveryAck(packet);
          notifyListeners();
          break;

        case MessageType.readReceipt:
          _messageService.handleReadReceipt(packet);
          notifyListeners();
          break;

        default:
          print('Unhandled message type: 0x${packet.type.toRadixString(16)}');
      }
    } catch (e) {
      print('Error handling characteristic data: $e');
    }
  }

  void _handleIncomingFriendRequest(String deviceId, Packet packet) {
    final requester = _friendshipService.handleFriendRequest(packet);
    print('Received friend request from ${requester.displayName} (deviceId: $deviceId)');

    // Check conditions
    if (_friendshipService.isFriend(requester.publicKey)) {
      print('Already friends, ignoring');
      return;
    }

    if (_friendshipService.isOnCooldown(requester.publicKey)) {
      print('On cooldown, auto-rejecting');
      // Note: In new architecture, we'd need to connect to them to send reject
      // For now, just ignore
      return;
    }

    // Store deviceId so we can send response later via notification
    _friendRequestSenders[deviceId] = requester;
    print('Stored requester deviceId for response');

    // Notify UI
    onFriendRequestReceived?.call(requester);
  }

  // ==================== Helpers ====================

  String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  @override
  void dispose() {
    _scanRestartTimer?.cancel();
    _cacheCleanupTimer?.cancel();
    _bleManager.dispose();
    super.dispose();
  }
}

/// Cached device with timestamp for TTL expiration
class _CachedDevice {
  final DiscoveredEventArgs device;
  final DateTime lastSeen;

  _CachedDevice(this.device, this.lastSeen);

  bool get isExpired =>
      DateTime.now().difference(lastSeen) > AppCoordinator._cacheTTL;
}
