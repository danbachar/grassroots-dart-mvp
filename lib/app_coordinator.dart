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
  // My identity (temporary - will be generated/loaded from storage)
  late final Uint8List myPeerId;
  late final Uint8List myNoisePk;
  late final Uint8List mySignPk;
  late final String myDisplayName;
  late final String myServiceUUID;

  // Managers and services
  final BLEManager _bleManager;
  final DatabaseService _databaseService;
  late final FriendshipService _friendshipService;
  late final MessageService _messageService;
  final PrivacyService _privacyService;

  // State - simplified
  final List<DiscoveredEventArgs> _scanResults = [];

  // Cache discovered peripherals by their peripheral UUID for sending messages
  final Map<String, DiscoveredEventArgs> _discoveredDevices =
      {}; // peripheralId -> DiscoveredEventArgs

  // Pending operations - temporarily store info for async operations
  final Map<String, DiscoveredEventArgs> _pendingFriendRequests =
      {}; // peripheralId -> device (waiting for connection)
  final Map<String, Peer> _pendingResponses =
      {}; // peripheralId -> requester (waiting to send accept/reject)

  // Pending message queue for offline delivery
  final Map<String, List<Packet>> _pendingMessages = {}; // peerIdHex -> packets

  // Track friends who are in range (their service UUID was discovered)
  final Set<String> _friendsInRange = {}; // peerIdHex

  // Track friends we're currently auto-connecting to (prevent duplicate connections)
  final Set<String> _autoConnectingTo = {}; // peerIdHex

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

  // Track currently open chat for immediate read receipts
  Uint8List? _activeChatPeerId;

  AppCoordinator({required this.myDisplayName})
    : _bleManager = BLEManager(),
      _databaseService = DatabaseService(),
      _privacyService = PrivacyService() {
    // Initialize services with shared database instance
    _friendshipService = FriendshipService(_databaseService);
    _messageService = MessageService(_databaseService);
    _initializeIdentity();
    _setupBLECallbacks();
  }

  /// Initialize identity (temporary implementation - generates random keys)
  void _initializeIdentity() {
    // TODO: Load from secure storage or generate on first launch
    // For now, using placeholder values
    myPeerId = Uint8List(8);
    myNoisePk = Uint8List(32);
    mySignPk = Uint8List(32);

    // Fill with random-ish data (not cryptographically secure, just for testing)
    for (int i = 0; i < 8; i++) {
      myPeerId[i] = DateTime.now().millisecondsSinceEpoch % 256;
    }
    for (int i = 0; i < 32; i++) {
      myNoisePk[i] = (DateTime.now().millisecondsSinceEpoch + i) % 256;
      mySignPk[i] = (DateTime.now().millisecondsSinceEpoch + i + 100) % 256;
    }

    // Derive service UUID from noise PK (last 128 bits)
    final last16Bytes = myNoisePk.sublist(16, 32);
    final hex = last16Bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    myServiceUUID =
        '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';

    print('My Peer ID: ${_bytesToHex(myPeerId)}');
    print('My Service UUID: $myServiceUUID');
  }

  /// Setup BLE callbacks
  void _setupBLECallbacks() {
    _bleManager.onDeviceDiscovered = _handleDeviceDiscovered;
    _bleManager.onCentralConnectionChanged = _handleConnectionChanged;
    _bleManager.onCharacteristicDataReceived = _handleCharacteristicData;
  }

  /// Initialize BLE (request permissions) and start continuous operation
  Future<void> initialize() async {
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
      startAdvertising();
    } else {
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

  /// Clean up expired entries from device cache
  void _cleanupExpiredCache() {
    final expiredKeys = <String>[];

    for (final entry in _deviceCache.entries) {
      if (entry.value.isExpired) {
        expiredKeys.add(entry.key);
      }
    }

    for (final key in expiredKeys) {
      _deviceCache.remove(key);
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

    final name = _privacyService.shouldAdvertiseName
        ? myDisplayName
        : 'Voyager';
    await _bleManager.startAdvertising(
      serviceUUID: myServiceUUID,
      deviceName: name,
    );
    notifyListeners();
  }

  Future<void> stopAdvertising() async {
    await _bleManager.stopAdvertising();
    notifyListeners();
  }

  // ==================== Friend Requests ====================

  /// Send a friend request to a discovered device
  /// New architecture: connect -> write to FRIEND_REQUEST characteristic -> stay connected for response
  Future<void> sendFriendRequest(DiscoveredEventArgs deviceArgs) async {
    final peripheral = deviceArgs.peripheral;
    final peripheralId = peripheral.uuid.toString();
    final deviceName = deviceArgs.advertisement.name ?? 'Unknown';

    print('Sending friend request to $deviceName ($peripheralId)...');

    // Store pending operation
    _pendingFriendRequests[peripheralId] = deviceArgs;

    // Connect via BLE (rest happens in _handleConnectionChanged)
    await _bleManager.connect(peripheral);
  }

  /// Accept a friend request from a peer
  /// New architecture: we're already receiving (they wrote to us), now we connect to them and write response
  Future<void> acceptFriendRequest(Peer requester) async {
    // Check if we already processed this request (prevent double-tap)
    if (_friendshipService.isFriend(requester.peerId)) {
      print(
        'Already friends with ${requester.displayName}, ignoring duplicate accept',
      );
      return;
    }

    // Add as friend
    final packet = _friendshipService.acceptFriendRequest(
      myPeerId: myPeerId,
      myNoisePk: myNoisePk,
      mySignPk: mySignPk,
      myDisplayName: myDisplayName,
      requester: requester,
    );

    // Find the device to connect to and send response
    // The requester should have a service UUID derived from their noisePk
    final serviceUUID = requester.deriveServiceUUID();

    // Look for the device in our discovered devices
    DiscoveredEventArgs? targetDevice;
    for (final device in _discoveredDevices.values) {
      // Check if any advertised service matches
      for (final uuid in device.advertisement.serviceUUIDs) {
        if (uuid.toString().toLowerCase() == serviceUUID.toLowerCase()) {
          targetDevice = device;
          break;
        }
      }
      if (targetDevice != null) break;
    }

    if (targetDevice != null) {
      // Connect and send response
      print('Connecting to requester to send accept...');
      _pendingResponses[targetDevice.peripheral.uuid.toString()] = requester;
      await _bleManager.connect(targetDevice.peripheral);
    } else {
      // Queue for later delivery when they're discovered
      print('Requester not in range, queuing response for later');
      final peerIdHex = _bytesToHex(requester.peerId);
      _pendingMessages[peerIdHex] ??= [];
      _pendingMessages[peerIdHex]!.add(packet);
    }

    notifyListeners();
  }

  /// Reject a friend request from a peer
  Future<void> rejectFriendRequest(Peer requester) async {
    // Create reject packet (will be sent when we connect)
    // The packet is created but we store the requester for sending

    // Similar to accept, try to send response
    final serviceUUID = requester.deriveServiceUUID();

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
      _pendingResponses[targetDevice.peripheral.uuid.toString()] = requester;
      await _bleManager.connect(targetDevice.peripheral);
    } else {
      print('Requester not in range, reject not sent');
    }
  }

  /// Remove a friend
  Future<void> removeFriend(Peer friend) async {
    _friendshipService.removeFriend(friend.peerId);
    print('Removed ${friend.displayName} from friends list');
    notifyListeners();
  }

  // ==================== Messaging ====================

  /// Send a chat message to a friend
  Future<void> sendMessage(Peer peer, String content) async {
    final packet = _messageService.createChatMessage(
      senderId: myPeerId,
      recipientId: peer.peerId,
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
      final peerIdHex = _bytesToHex(peer.peerId);
      _pendingMessages[peerIdHex] ??= [];
      _pendingMessages[peerIdHex]!.add(packet);
    }
  }

  /// Get chat history with a peer
  List<Message> getChat(Peer peer) {
    return _messageService.getChat(peer.peerId);
  }

  /// Mark all messages from a peer as read (when user opens the chat)
  /// Also sends read receipts to the peer if they're in range
  Future<void> markMessagesAsRead(Peer peer) async {
    final messages = _messageService.getChat(peer.peerId);
    final unreadMessages = <Message>[];

    // Find messages from this peer that aren't yet marked as read
    for (final message in messages) {
      // Only mark messages FROM the friend (not our own messages)
      final isFromFriend = !_bytesEqual(message.senderId, myPeerId);
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
          senderId: myPeerId,
          recipientId: peer.peerId,
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
      if (_bytesEqual(friend.peerId, senderPeerId)) {
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
        senderId: myPeerId,
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
    _activeChatPeerId = peer?.peerId;
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
      await _bleManager.connect(peripheral);

      // Wait a bit for connection to establish
      await Future.delayed(Duration(milliseconds: 500));

      // Discover services
      final services = await _bleManager.discoverServices(peripheral);

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
        await _bleManager.disconnect(peripheral);
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

      print('Packet sent, disconnecting...');
      await _bleManager.disconnect(peripheral);
      return true;
    } catch (e) {
      print('Error in connect-and-send: $e');
      try {
        await _bleManager.disconnect(peripheral);
      } catch (_) {}
      return false;
    }
  }

  // ==================== Internal Handlers ====================

  void _handleDeviceDiscovered(DiscoveredEventArgs eventArgs) {
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
    
    // Already verified
    if (_compatibleDevices.contains(peripheralId)) return;
    
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
      }
    }
  }

  /// Check if a discovered device is a friend and mark them as in-range
  void _checkIfFriendAndAutoConnect(DiscoveredEventArgs device) {
    for (final friend in friends) {
      final serviceUUID = friend.deriveServiceUUID();

      // Check if this device advertises the friend's service UUID
      for (final uuid in device.advertisement.serviceUUIDs) {
        if (uuid.toString().toLowerCase() == serviceUUID.toLowerCase()) {
          final peerIdHex = _bytesToHex(friend.peerId);

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

  /// Auto-connect to a friend who came into range
  Future<void> _autoConnectToFriend(
    Peer friend,
    DiscoveredEventArgs device,
  ) async {
    final peerIdHex = _bytesToHex(friend.peerId);

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
          final peerIdHex = _bytesToHex(friend.peerId);
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

      // Check if this is a pending response (accept/reject)
      final pendingResponse = _pendingResponses.remove(peripheralId);
      if (pendingResponse != null) {
        _handleResponseConnection(peripheral, pendingResponse);
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
        await _bleManager.disconnect(peripheral);
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
        myPeerId: myPeerId,
        myNoisePk: myNoisePk,
        mySignPk: mySignPk,
        myDisplayName: myDisplayName,
        recipientId: Uint8List(8), // Unknown at this point
      );

      final bytes = packet.serialize();
      print('Sending friend request: ${bytes.length} bytes');

      await _bleManager.writeCharacteristic(
        peripheral: peripheral,
        characteristicUUID: UUID.fromString(FRIEND_REQUEST_CHARACTERISTIC_UUID),
        data: bytes,
      );

      print('Friend request sent to $deviceName');
      // Stay connected to receive response via notification
    } catch (e) {
      print('Error sending friend request: $e');
      try {
        await _bleManager.disconnect(peripheral);
      } catch (_) {}
    }
  }

  /// Handle connection established for sending a response (accept/reject)
  Future<void> _handleResponseConnection(
    Peripheral peripheral,
    Peer requester,
  ) async {
    print('Connected to ${requester.displayName}, sending response...');

    try {
      final services = await _bleManager.discoverServices(peripheral);

      // Find response characteristic
      GATTCharacteristic? responseChar;
      for (final service in services) {
        for (final char in service.characteristics) {
          if (char.uuid.toString().toLowerCase() ==
              FRIEND_RESPONSE_CHARACTERISTIC_UUID.toLowerCase()) {
            responseChar = char;
            break;
          }
        }
        if (responseChar != null) break;
      }

      if (responseChar == null) {
        print('Warning: Friend response characteristic not found');
        await _bleManager.disconnect(peripheral);
        return;
      }

      // Determine if this is an accept or reject
      final isFriend = _friendshipService.isFriend(requester.peerId);

      Packet packet;
      if (isFriend) {
        // Already friends, this must be an accept we're sending
        packet = _friendshipService.createFriendAccept(
          myPeerId: myPeerId,
          myNoisePk: myNoisePk,
          mySignPk: mySignPk,
          myDisplayName: myDisplayName,
          recipientId: requester.peerId,
        );
      } else {
        // Reject
        packet = _friendshipService.rejectFriendRequest(
          myPeerId: myPeerId,
          requester: requester,
        );
      }

      final bytes = packet.serialize();
      print('Sending response: ${bytes.length} bytes');

      await _bleManager.writeCharacteristic(
        peripheral: peripheral,
        characteristicUUID: UUID.fromString(
          FRIEND_RESPONSE_CHARACTERISTIC_UUID,
        ),
        data: bytes,
      );

      print('Response sent, disconnecting...');
      await _bleManager.disconnect(peripheral);
    } catch (e) {
      print('Error sending response: $e');
      try {
        await _bleManager.disconnect(peripheral);
      } catch (_) {}
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
    print('Received friend request from ${requester.displayName}');

    // Check conditions
    if (_friendshipService.isFriend(requester.peerId)) {
      print('Already friends, ignoring');
      return;
    }

    if (_friendshipService.isOnCooldown(requester.peerId)) {
      print('On cooldown, auto-rejecting');
      // Note: In new architecture, we'd need to connect to them to send reject
      // For now, just ignore
      return;
    }

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
