import 'dart:async';
import 'dart:typed_data';
import 'package:bluetooth_low_energy/bluetooth_low_energy.dart'
    hide ConnectionState;
import 'package:bluetooth_low_energy/bluetooth_low_energy.dart'
    as ble
    show ConnectionState;
import 'package:flutter/material.dart' hide ConnectionState;

import 'ble/ble_manager.dart';
import 'models/connection_state.dart';
import 'models/message.dart';
import 'models/peer.dart';
import 'protocol/constants.dart';
import 'protocol/packet.dart';
import 'services/fragmentation_service.dart';
import 'services/friendship_service.dart';
import 'services/message_service.dart';
import 'services/privacy_service.dart';

/// Coordinates BLE operations with protocol services
/// This is the main controller that ties everything together
class AppCoordinator extends ChangeNotifier {
  // My identity (temporary - will be generated/loaded from storage)
  late final Uint8List myPeerId;
  late final Uint8List myNoisePk;
  late final Uint8List mySignPk;
  late final String myDisplayName;
  late final String myServiceUUID;

  // Managers and services
  final BLEManager _bleManager;
  final FriendshipService _friendshipService;
  final MessageService _messageService;
  final PrivacyService _privacyService;
  final FragmentationService _fragmentationService;

  // State
  final Map<String, PeerConnection> _connections = {}; // peerId -> connection
  final List<DiscoveredEventArgs> _scanResults = [];

  // Track centrals that sent us friend requests (deviceId -> Peer info)
  // Used to send responses back via notifications
  final Map<String, Peer> _pendingIncomingRequests = {};

  // Track connected centrals for messaging (deviceId -> peerId)
  // When they connect to us as Peripheral, we store their device ID to peer ID mapping
  final Map<String, String> _centralDeviceIdToPeerId = {};
  // Reverse mapping: peerId hex -> deviceId
  final Map<String, String> _peerIdToCentralDeviceId = {};

  // Callbacks for UI
  void Function(Peer)? onFriendRequestReceived;

  AppCoordinator({required this.myDisplayName})
    : _bleManager = BLEManager(),
      _friendshipService = FriendshipService(),
      _messageService = MessageService(),
      _privacyService = PrivacyService(),
      _fragmentationService = FragmentationService() {
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
    _bleManager.onCentralConnectionChanged = _handleCentralConnectionChanged;
    _bleManager.onDataReceived = _handleDataReceived;
    // Use characteristic-aware callback to handle friend requests specifically
    _bleManager.onCharacteristicDataReceived = _handleCharacteristicData;
  }

  /// Initialize BLE (request permissions)
  Future<void> initialize() async {
    await _bleManager.initialize();
    notifyListeners();
  }

  // ==================== Getters ====================

  List<Peer> get friends => _friendshipService.friends;
  List<DiscoveredEventArgs> get scanResults => _scanResults;
  bool get isScanning => _bleManager.isScanning;
  bool get isAdvertising => _bleManager.isAdvertising;
  int get privacyLevel => _privacyService.privacyLevel;
  String get privacyLevelName => _privacyService.privacyLevelName;

  // ==================== Privacy ====================

  void setPrivacyLevel(int level) {
    _privacyService.setPrivacyLevel(level);
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
          .where((uuid) => uuid != null)
          .map((uuid) => UUID.fromString(uuid!))
          .toList();

      if (friendUUIDs.isNotEmpty) {
        await _bleManager.startScan(serviceUUIDs: friendUUIDs);
      }
    }
    notifyListeners();
  }

  Future<void> stopScan() async {
    await _bleManager.stopScan();
    _scanResults.clear();
    notifyListeners();
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

  // ==================== Connections ====================

  /// Pair with a device and send a friend request
  /// This is the unified flow: BLE connect -> GATT discover -> send friend request
  Future<void> pairDevice(DiscoveredEventArgs deviceArgs) async {
    final peripheral = deviceArgs.peripheral;
    final peripheralId = peripheral.uuid.toString();
    final deviceName = deviceArgs.advertisement.name ?? 'Unknown';

    print('Starting pairing with $deviceName ($peripheralId)...');

    // Connect via BLE
    await _bleManager.connect(peripheral);

    // Connection state and friend request will be handled in _handleCentralConnectionChanged
    // Store the device name temporarily so we can use it when creating the peer
    _pendingPairings[peripheralId] = deviceArgs;
  }

  // Store pending pairings to access advertisement data after connection
  final Map<String, DiscoveredEventArgs> _pendingPairings = {};

  // ==================== Messaging ====================

  Future<void> sendMessage(Peer peer, String content) async {
    final packet = _messageService.createChatMessage(
      senderId: myPeerId,
      recipientId: peer.peerId,
      content: content,
    );

    await _sendPacketToPeer(peer, packet);
  }

  /// Send a packet to a peer, handling both Central and Peripheral roles
  Future<void> _sendPacketToPeer(Peer peer, Packet packet) async {
    final peerIdHex = _bytesToHex(peer.peerId);

    // First, check if they connected to us (we are Peripheral, they are Central)
    final centralDeviceId = _peerIdToCentralDeviceId[peerIdHex];
    if (centralDeviceId != null) {
      print('Sending packet to peer via notification (we are Peripheral)');
      final bytes = packet.serialize();
      await _bleManager.notifyCharacteristic(
        deviceId: centralDeviceId,
        characteristicId: FIXED_CHARACTERISTIC_UUID,
        data: bytes,
      );
      return;
    }

    // Second, check if we connected to them (we are Central, they are Peripheral)
    if (peer.peripheral != null) {
      print('Sending packet to peer via write (we are Central)');
      await _sendPacket(peer, packet);
      return;
    }

    throw Exception(
      'No connection to peer - neither Central nor Peripheral path available',
    );
  }

  List<Message> getChat(Peer peer) {
    return _messageService.getChat(peer.peerId);
  }

  // ==================== Friendship ====================

  Future<void> sendFriendRequest(Peer peer) async {
    final packet = _friendshipService.createFriendRequest(
      myPeerId: myPeerId,
      myNoisePk: myNoisePk,
      mySignPk: mySignPk,
      myDisplayName: myDisplayName,
      recipientId: peer.peerId,
    );

    await _sendPacket(peer, packet);
  }

  Future<void> acceptFriendRequest(Peer requester) async {
    // Check if we already processed this request (prevent double-tap)
    final alreadyFriend = _friendshipService.isFriend(requester.peerId);
    if (alreadyFriend) {
      print(
        'Already friends with ${requester.displayName}, ignoring duplicate accept',
      );
      return;
    }

    final packet = _friendshipService.acceptFriendRequest(
      myPeerId: myPeerId,
      myNoisePk: myNoisePk,
      mySignPk: mySignPk,
      myDisplayName: myDisplayName,
      requester: requester,
    );

    // Find the deviceId for this requester (they connected to us as Central)
    final deviceId = _pendingIncomingRequests.entries
        .firstWhere(
          (e) => _bytesEqual(e.value.peerId, requester.peerId),
          orElse: () => MapEntry('', requester),
        )
        .key;

    if (deviceId.isNotEmpty) {
      // Send response via notification (we are the Peripheral, they are the Central)
      print('Sending friend accept via notification to $deviceId');
      await _sendResponseViaNotification(deviceId, packet);

      // Store the mapping so we can send messages to this peer later
      final peerIdHex = _bytesToHex(requester.peerId);
      _centralDeviceIdToPeerId[deviceId] = peerIdHex;
      _peerIdToCentralDeviceId[peerIdHex] = deviceId;
      print('Stored peer mapping: deviceId=$deviceId <-> peerId=$peerIdHex');

      _pendingIncomingRequests.remove(deviceId);
    } else if (requester.peripheral != null) {
      // Fallback: we connected to them (we are Central, they are Peripheral)
      await _sendPacket(requester, packet);
    } else {
      print('Warning: Cannot send accept - no connection path to requester');
    }

    notifyListeners();
  }

  Future<void> rejectFriendRequest(Peer requester) async {
    final packet = _friendshipService.rejectFriendRequest(
      myPeerId: myPeerId,
      requester: requester,
    );

    // Find the deviceId for this requester
    final deviceId = _pendingIncomingRequests.entries
        .firstWhere(
          (e) => _bytesEqual(e.value.peerId, requester.peerId),
          orElse: () => MapEntry('', requester),
        )
        .key;

    if (deviceId.isNotEmpty) {
      // Send response via notification
      print('Sending friend reject via notification to $deviceId');
      await _sendResponseViaNotification(deviceId, packet);
      _pendingIncomingRequests.remove(deviceId);
    } else if (requester.peripheral != null) {
      // Fallback: we connected to them
      await _sendPacket(requester, packet);
    } else {
      print('Warning: Cannot send reject - no connection path to requester');
    }
  }

  /// Helper to reject via notification (used for auto-reject on cooldown)
  Future<void> _rejectFriendRequestViaNotification(
    String deviceId,
    Peer requester,
  ) async {
    final packet = _friendshipService.rejectFriendRequest(
      myPeerId: myPeerId,
      requester: requester,
    );

    await _sendResponseViaNotification(deviceId, packet);
    _pendingIncomingRequests.remove(deviceId);
  }

  /// Send a packet response via BLE notification (as Peripheral to connected Central)
  Future<void> _sendResponseViaNotification(
    String deviceId,
    Packet packet,
  ) async {
    final bytes = packet.serialize();
    print('Sending ${bytes.length} bytes via notification to $deviceId');

    await _bleManager.notifyCharacteristic(
      deviceId: deviceId,
      characteristicId: FRIEND_RESPONSE_CHARACTERISTIC_UUID,
      data: bytes,
    );
  }

  /// Remove a friend and disconnect BLE connection
  Future<void> removeFriend(Peer friend) async {
    // Disconnect BLE if connected
    if (friend.peripheral != null) {
      try {
        await _bleManager.disconnect(friend.peripheral!);
        print('Disconnected from ${friend.displayName}');
      } catch (e) {
        print('Error disconnecting from ${friend.displayName}: $e');
      }
    }

    // Remove from connections map
    final peripheralId = friend.peripheral?.uuid.toString();
    if (peripheralId != null) {
      _connections.remove(peripheralId);
    }

    // Remove from friends list
    _friendshipService.removeFriend(friend.peerId);
    print('Removed ${friend.displayName} from friends list');

    notifyListeners();
  }

  // ==================== Internal Handlers ====================

  void _handleDeviceDiscovered(DiscoveredEventArgs eventArgs) {
    // Update scan results
    final index = _scanResults.indexWhere(
      (r) => r.peripheral == eventArgs.peripheral,
    );
    if (index >= 0) {
      _scanResults[index] = eventArgs;
    } else {
      _scanResults.add(eventArgs);
    }
    notifyListeners();
  }

  void _handleCentralConnectionChanged(
    Peripheral peripheral,
    ble.ConnectionState state,
  ) {
    final peripheralId = peripheral.uuid.toString();
    print('Connection changed: $peripheralId -> $state');

    if (state == ble.ConnectionState.connected) {
      // Track connection
      _connections[peripheralId] = PeerConnection(
        peripheralId: peripheralId,
        state: ConnectionState.connecting,
      );

      // Discover GATT services and then send friend request
      _bleManager
          .discoverServices(peripheral)
          .then((services) async {
            print('Discovered ${services.length} services:');
            for (final service in services) {
              print('  Service: ${service.uuid}');
              for (final char in service.characteristics) {
                print('    Characteristic: ${char.uuid}');
              }
            }

            // Find the characteristic we need to write to
            GATTCharacteristic? friendRequestCharacteristic;
            GATTCharacteristic? friendResponseCharacteristic;
            for (final service in services) {
              for (final char in service.characteristics) {
                final charUuid = char.uuid.toString().toLowerCase();
                if (charUuid ==
                    FRIEND_REQUEST_CHARACTERISTIC_UUID.toLowerCase()) {
                  friendRequestCharacteristic = char;
                  print('Found friend request characteristic: ${char.uuid}');
                } else if (charUuid ==
                    FRIEND_RESPONSE_CHARACTERISTIC_UUID.toLowerCase()) {
                  friendResponseCharacteristic = char;
                  print('Found friend response characteristic: ${char.uuid}');
                } else if (charUuid ==
                    FIXED_CHARACTERISTIC_UUID.toLowerCase()) {
                  print('Found general characteristic: ${char.uuid}');
                }
              }
            }

            if (services.isNotEmpty) {
              // Update connection state
              _connections[peripheralId] = PeerConnection(
                peripheralId: peripheralId,
                state: ConnectionState.established,
              );

              // Check if this was a pending pairing (we initiated the connection)
              final pendingPairing = _pendingPairings.remove(peripheralId);
              if (pendingPairing != null) {
                // Use friend request characteristic if available, else fall back to general
                final writeCharUuid = friendRequestCharacteristic != null
                    ? FRIEND_REQUEST_CHARACTERISTIC_UUID
                    : FIXED_CHARACTERISTIC_UUID;

                if (friendRequestCharacteristic == null) {
                  print(
                    'Warning: Friend request characteristic not found, using general characteristic',
                  );
                }

                // Subscribe to friend response characteristic to receive accept/reject
                if (friendResponseCharacteristic != null) {
                  try {
                    print('Subscribing to friend response characteristic...');
                    await _bleManager.subscribeToCharacteristic(
                      peripheral: peripheral,
                      characteristic: friendResponseCharacteristic,
                    );
                    print(
                      'Successfully subscribed to friend response notifications',
                    );
                  } catch (e) {
                    print('Warning: Could not subscribe to responses: $e');
                  }
                } else {
                  print(
                    'Warning: Friend response characteristic not found, will not receive accept/reject',
                  );
                }

                print('Sending friend request to $peripheralId...');

                // Create a temporary peer to send the friend request
                // We use empty keys since we don't know them yet - they'll be exchanged via the protocol
                final tempPeer = Peer(
                  peerId: Uint8List(8), // Will be filled in by response
                  noisePk: Uint8List(32),
                  signPk: Uint8List(32),
                  displayName: pendingPairing.advertisement.name ?? 'Unknown',
                  peripheral: peripheral,
                );

                // Create and send the friend request packet
                final packet = _friendshipService.createFriendRequest(
                  myPeerId: myPeerId,
                  myNoisePk: myNoisePk,
                  mySignPk: mySignPk,
                  myDisplayName: myDisplayName,
                  recipientId: tempPeer.peerId,
                );

                try {
                  // Serialize and send directly - transport layer handles chunking
                  final bytes = packet.serialize();
                  print(
                    'Sending friend request: ${bytes.length} bytes on $writeCharUuid',
                  );

                  await _bleManager.writeCharacteristic(
                    peripheral: peripheral,
                    characteristicUUID: UUID.fromString(writeCharUuid),
                    data: bytes,
                  );

                  print('Friend request sent to ${tempPeer.displayName}');
                } catch (e, stackTrace) {
                  print('Error sending friend request: $e');
                  print('Stack trace: $stackTrace');
                }
              }
            }

            notifyListeners();
          })
          .catchError((e, stackTrace) {
            print('Error discovering services: $e');
            print('Stack trace: $stackTrace');
          });
    } else if (state == ble.ConnectionState.disconnected) {
      _connections.remove(peripheralId);
      _pendingPairings.remove(peripheralId);
    }

    notifyListeners();
  }

  void _handleDataReceived(String deviceId, Uint8List data) {
    print('Received ${data.length} bytes from $deviceId');

    try {
      // Transport layer has already reassembled chunks into complete packet bytes
      // Just deserialize and process
      final packet = Packet.deserialize(data);
      print('Received packet type: 0x${packet.type.toRadixString(16)}');

      _processPacket(deviceId, packet);
    } catch (e) {
      print('Error handling received data: $e');
    }
  }

  /// Handle data received on a specific characteristic
  /// This allows us to track which deviceId sent friend requests so we can respond
  void _handleCharacteristicData(
    String deviceId,
    String characteristicId,
    Uint8List data,
  ) {
    print(
      'Received ${data.length} bytes from $deviceId on characteristic $characteristicId',
    );

    try {
      final packet = Packet.deserialize(data);
      print(
        'Received packet type: 0x${packet.type.toRadixString(16)} on $characteristicId',
      );

      // If this is a friend request on the friend request characteristic, track the deviceId
      if (packet.type == MessageType.friendRequest) {
        final requester = _friendshipService.handleFriendRequest(packet);
        print('Received friend request from ${requester.displayName}');

        // Store the deviceId so we can send the response back via notification
        _pendingIncomingRequests[deviceId] = requester;
        print('Stored pending request from deviceId: $deviceId');

        // Check conditions
        if (_friendshipService.isFriend(requester.peerId)) {
          print('Already friends, ignoring');
          _pendingIncomingRequests.remove(deviceId);
          return;
        }

        if (_friendshipService.isOnCooldown(requester.peerId)) {
          print('On cooldown, auto-rejecting');
          _rejectFriendRequestViaNotification(deviceId, requester);
          return;
        }

        // Notify UI
        onFriendRequestReceived?.call(requester);
      } else if (packet.type == MessageType.friendAccept) {
        // We received an acceptance (as Central, via notification subscription)
        final friend = _friendshipService.handleFriendAccept(packet);
        print('Friend request accepted by ${friend.displayName}');
        notifyListeners();
      } else if (packet.type == MessageType.friendReject) {
        _friendshipService.handleFriendReject(packet);
        print('Friend request rejected');
        notifyListeners();
      } else {
        // For other packet types, use the regular handler
        _processPacket(deviceId, packet);
      }
    } catch (e) {
      print('Error handling characteristic data: $e');
    }
  }

  void _processPacket(String deviceId, Packet packet) {
    try {
      // Handle based on message type
      switch (packet.type) {
        case MessageType.message:
          final message = _messageService.handleChatMessage(packet);
          print('Received chat message: ${message.content}');

          // Send delivery ack
          final ack = _messageService.createDeliveryAck(
            senderId: myPeerId,
            recipientId: message.senderId,
            messageId: message.messageId,
          );
          // TODO: Send ack back

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

        case MessageType.friendRequest:
          final requester = _friendshipService.handleFriendRequest(packet);
          print('Received friend request from ${requester.displayName}');

          // Check conditions
          if (_friendshipService.isFriend(requester.peerId)) {
            print('Already friends, ignoring');
            return;
          }

          if (_friendshipService.isOnCooldown(requester.peerId)) {
            print('On cooldown, auto-rejecting');
            rejectFriendRequest(requester);
            return;
          }

          // Notify UI
          onFriendRequestReceived?.call(requester);
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

        default:
          print('Unhandled message type: 0x${packet.type.toRadixString(16)}');
      }
    } catch (e) {
      print('Error handling received data: $e');
    }
  }

  /// Send a packet to a peer via BLE
  Future<void> _sendPacket(Peer peer, Packet packet) async {
    // Find the connection
    final connection = _connections.values.firstWhere(
      (c) => c.peripheralId == peer.peripheral?.uuid.toString(),
      orElse: () => throw Exception('No connection to peer'),
    );

    final peripheral = _bleManager.getPeripheral(connection.peripheralId);
    if (peripheral == null) {
      throw Exception('Peripheral not found');
    }

    // Serialize and send - transport layer handles chunking
    final bytes = packet.serialize();

    await _bleManager.writeCharacteristic(
      peripheral: peripheral,
      characteristicUUID: UUID.fromString(FIXED_CHARACTERISTIC_UUID),
      data: bytes,
    );
  }

  String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _bleManager.dispose();
    super.dispose();
  }
}
