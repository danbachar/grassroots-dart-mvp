import 'dart:typed_data';
import '../models/peer.dart';
import '../protocol/constants.dart';
import '../protocol/payloads.dart';
import '../protocol/packet.dart';

/// Manages friendship requests and friend list
class FriendshipService {
  // In-memory storage (will be replaced with database later)
  final Map<String, Peer> _friends = {};
  final Map<String, DateTime> _pendingRequests = {}; // peerId -> request time
  final Map<String, DateTime> _rejectionCooldowns = {}; // peerId -> rejection time

  /// Get all friends
  List<Peer> get friends => _friends.values.toList();

  /// Check if peer is a friend
  bool isFriend(Uint8List peerId) {
    final key = _peerIdToString(peerId);
    return _friends.containsKey(key);
  }

  /// Get friend by peer ID
  Peer? getFriend(Uint8List peerId) {
    final key = _peerIdToString(peerId);
    return _friends[key];
  }

  /// Add a friend to the list
  void addFriend(Peer peer) {
    final key = _peerIdToString(peer.peerId);
    _friends[key] = peer;

    // Clear any pending request or cooldown
    _pendingRequests.remove(key);
    _rejectionCooldowns.remove(key);
  }

  /// Remove a friend from the list
  void removeFriend(Uint8List peerId) {
    final key = _peerIdToString(peerId);
    _friends.remove(key);
  }

  /// Create a friend request packet
  Packet createFriendRequest({
    required Uint8List myPeerId,
    required Uint8List myNoisePk,
    required Uint8List mySignPk,
    required String myDisplayName,
    required Uint8List recipientId,
  }) {
    final payload = FriendRequestPayload(
      requesterPk: myNoisePk,
      requesterSignPk: mySignPk,
      displayName: myDisplayName,
      // signature: null, // TODO: Add signature when crypto is implemented
    );

    final packet = Packet(
      type: MessageType.friendRequest,
      flags: PacketFlags.hasRecipient,
      senderId: myPeerId,
      recipientId: recipientId,
      payload: payload.serialize(),
    );

    // Track pending request
    final key = _peerIdToString(recipientId);
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
    final peerId = packet.senderId!;

    // Create and return peer object
    return Peer(
      peerId: peerId,
      noisePk: payload.requesterPk,
      signPk: payload.requesterSignPk,
      displayName: payload.displayName,
      isVerified: false,
    );
  }

  /// Create friend accept packet
  Packet createFriendAccept({
    required Uint8List myPeerId,
    required Uint8List myNoisePk,
    required Uint8List mySignPk,
    required String myDisplayName,
    required Uint8List recipientId,
  }) {
    final payload = FriendAcceptPayload(
      accepterPk: myNoisePk,
      accepterSignPk: mySignPk,
      displayName: myDisplayName,
      // signature: null, // TODO: Add signature when crypto is implemented
    );

    return Packet(
      type: MessageType.friendAccept,
      flags: PacketFlags.hasRecipient,
      senderId: myPeerId,
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
    final peerId = packet.senderId!;

    // Create peer object
    final peer = Peer(
      peerId: peerId,
      noisePk: payload.accepterPk,
      signPk: payload.accepterSignPk,
      displayName: payload.displayName,
      isVerified: false,
    );

    // Add to friends list
    addFriend(peer);

    return peer;
  }

  /// Create friend reject packet
  Packet createFriendReject({
    required Uint8List myPeerId,
    required Uint8List recipientId,
  }) {
    final payload = FriendRejectPayload();

    return Packet(
      type: MessageType.friendReject,
      flags: PacketFlags.hasRecipient,
      senderId: myPeerId,
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
    final key = _peerIdToString(peerId);

    // Clear pending request
    _pendingRequests.remove(key);

    // Set cooldown
    _rejectionCooldowns[key] = DateTime.now();
  }

  /// Accept a friend request
  /// Returns the accept packet to send
  Packet acceptFriendRequest({
    required Uint8List myPeerId,
    required Uint8List myNoisePk,
    required Uint8List mySignPk,
    required String myDisplayName,
    required Peer requester,
  }) {
    // Add to friends list
    addFriend(requester);

    // Create and return accept packet
    return createFriendAccept(
      myPeerId: myPeerId,
      myNoisePk: myNoisePk,
      mySignPk: mySignPk,
      myDisplayName: myDisplayName,
      recipientId: requester.peerId,
    );
  }

  /// Reject a friend request
  /// Returns the reject packet to send
  Packet rejectFriendRequest({
    required Uint8List myPeerId,
    required Peer requester,
  }) {
    final key = _peerIdToString(requester.peerId);

    // Set cooldown
    _rejectionCooldowns[key] = DateTime.now();

    // Create and return reject packet
    return createFriendReject(
      myPeerId: myPeerId,
      recipientId: requester.peerId,
    );
  }

  /// Check if there's a pending request to this peer
  bool hasPendingRequest(Uint8List peerId) {
    final key = _peerIdToString(peerId);
    return _pendingRequests.containsKey(key);
  }

  /// Check if peer is on cooldown (recently rejected us)
  bool isOnCooldown(Uint8List peerId) {
    final key = _peerIdToString(peerId);
    final cooldown = _rejectionCooldowns[key];
    if (cooldown == null) return false;

    final elapsed = DateTime.now().difference(cooldown);
    return elapsed.inMilliseconds < Timeouts.friendCooldown;
  }

  /// Helper: Convert peer ID to string key
  String _peerIdToString(Uint8List peerId) {
    return peerId.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
