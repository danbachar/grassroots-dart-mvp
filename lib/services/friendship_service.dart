import 'dart:typed_data';
import '../models/peer.dart';
import '../protocol/constants.dart';
import '../protocol/payloads.dart';
import '../protocol/packet.dart';
import 'database_service.dart';

/// Manages friendship requests and friend list
class FriendshipService {
  final DatabaseService _db;
  
  // In-memory cache (synced with database)
  final Map<String, Peer> _friends = {};
  final Map<String, DateTime> _pendingRequests = {}; // peerId -> request time
  final Map<String, DateTime> _rejectionCooldowns = {}; // peerId -> rejection time
  
  bool _initialized = false;
  
  FriendshipService(this._db);
  
  /// Initialize service - load friends from database
  Future<void> initialize() async {
    if (_initialized) return;
    
    final dbFriends = await _db.getAllFriends();
    for (final friend in dbFriends) {
      final key = _publicKeyToString(friend.publicKey);
      _friends[key] = friend;
    }
    _initialized = true;
    print('FriendshipService: Loaded ${_friends.length} friends from database');
  }

  /// Get all friends
  List<Peer> get friends => _friends.values.toList();

  /// Check if peer is a friend
  bool isFriend(Uint8List publicKey) {
    final key = _publicKeyToString(publicKey);
    return _friends.containsKey(key);
  }

  /// Get friend by public key
  Peer? getFriend(Uint8List publicKey) {
    final key = _publicKeyToString(publicKey);
    return _friends[key];
  }

  /// Add a friend to the list
  void addFriend(Peer peer) {
    final key = _publicKeyToString(peer.publicKey);
    _friends[key] = peer;

    // Clear any pending request or cooldown
    _pendingRequests.remove(key);
    _rejectionCooldowns.remove(key);
    
    // Persist to database (fire and forget)
    _db.insertFriend(peer);
  }

  /// Remove a friend from the list
  void removeFriend(Uint8List publicKey) {
    final key = _publicKeyToString(publicKey);
    _friends.remove(key);

    // Remove from database (fire and forget)
    _db.deleteFriend(publicKey);
  }

  /// Create a friend request packet
  Packet createFriendRequest({
    required Uint8List myPublicKey,
    required String myDisplayName,
    required Uint8List recipientId,
  }) {
    final payload = FriendRequestPayload(
      publicKey: myPublicKey,
      displayName: myDisplayName,
      // signature: null, // TODO: Add signature when crypto is implemented
    );

    final packet = Packet(
      type: MessageType.friendRequest,
      flags: PacketFlags.hasRecipient,
      senderId: myPublicKey,
      recipientId: recipientId,
      payload: payload.serialize(),
    );

    // Track pending request
    final key = _publicKeyToString(recipientId);
    _pendingRequests[key] = DateTime.now();

    return packet;
  }

  /// Handle incoming friend request - parse and return peer info
  /// Caller decides whether to accept/reject based on their logic
  Peer handleFriendRequest(Packet packet) {
    if (packet.type != MessageType.friendRequest) {
      throw ArgumentError('Packet is not a friend request');
    }
    if (packet.senderId == null) {
      throw ArgumentError('Friend request missing sender ID');
    }

    final payload = FriendRequestPayload.deserialize(packet.payload);
    final publicKey = payload.publicKey;

    // Create and return peer object
    return Peer(
      publicKey: publicKey,
      displayName: payload.displayName,
      isVerified: false,
    );
  }

  /// Create friend accept packet
  Packet createFriendAccept({
    required Uint8List myPublicKey,
    required String myDisplayName,
    required Uint8List recipientId,
  }) {
    final payload = FriendAcceptPayload(
      publicKey: myPublicKey,
      displayName: myDisplayName,
      // signature: null, // TODO: Add signature when crypto is implemented
    );

    return Packet(
      type: MessageType.friendAccept,
      flags: PacketFlags.hasRecipient,
      senderId: myPublicKey,
      recipientId: recipientId,
      payload: payload.serialize(),
    );
  }

  /// Handle incoming friend accept - parse, add friend, return peer
  Peer handleFriendAccept(Packet packet) {
    if (packet.type != MessageType.friendAccept) {
      throw ArgumentError('Packet is not a friend accept');
    }
    if (packet.senderId == null) {
      throw ArgumentError('Friend accept missing sender ID');
    }

    final payload = FriendAcceptPayload.deserialize(packet.payload);
    final publicKey = payload.publicKey;

    // Create peer object
    final peer = Peer(
      publicKey: publicKey,
      displayName: payload.displayName,
      isVerified: false,
    );

    // Add to friends list
    addFriend(peer);

    return peer;
  }

  /// Create friend reject packet
  Packet createFriendReject({
    required Uint8List myPublicKey,
    required Uint8List recipientId,
  }) {
    final payload = FriendRejectPayload();

    return Packet(
      type: MessageType.friendReject,
      flags: PacketFlags.hasRecipient,
      senderId: myPublicKey,
      recipientId: recipientId,
      payload: payload.serialize(),
    );
  }

  /// Handle incoming friend reject - clear pending request, set cooldown
  void handleFriendReject(Packet packet) {
    if (packet.type != MessageType.friendReject) {
      throw ArgumentError('Packet is not a friend reject');
    }
    if (packet.senderId == null) {
      throw ArgumentError('Friend reject missing sender ID');
    }

    final peerId = packet.senderId!;
    final key = _publicKeyToString(peerId);

    // Clear pending request
    _pendingRequests.remove(key);

    // Set cooldown
    _rejectionCooldowns[key] = DateTime.now();
  }

  /// Accept a friend request
  /// Returns the accept packet to send
  Packet acceptFriendRequest({
    required Uint8List myPublicKey,
    required String myDisplayName,
    required Peer requester,
  }) {
    // Add to friends list
    addFriend(requester);

    // Create and return accept packet
    return createFriendAccept(
      myPublicKey: myPublicKey,
      myDisplayName: myDisplayName,
      recipientId: requester.publicKey,
    );
  }

  /// Reject a friend request
  /// Returns the reject packet to send
  Packet rejectFriendRequest({
    required Uint8List myPublicKey,
    required Peer requester,
  }) {
    final key = _publicKeyToString(requester.publicKey);

    // Set cooldown
    _rejectionCooldowns[key] = DateTime.now();

    // Create and return reject packet
    return createFriendReject(
      myPublicKey: myPublicKey,
      recipientId: requester.publicKey,
    );
  }

  /// Check if there's a pending request to this peer
  bool hasPendingRequest(Uint8List publicKey) {
    final key = _publicKeyToString(publicKey);
    return _pendingRequests.containsKey(key);
  }

  /// Check if peer is on cooldown (recently rejected us)
  bool isOnCooldown(Uint8List publicKey) {
    final key = _publicKeyToString(publicKey);
    final cooldown = _rejectionCooldowns[key];
    if (cooldown == null) return false;

    final elapsed = DateTime.now().difference(cooldown);
    return elapsed.inMilliseconds < Timeouts.friendCooldown;
  }

  /// Helper: Convert public key to string key
  String _publicKeyToString(Uint8List publicKey) {
    return publicKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
