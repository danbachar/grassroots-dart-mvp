import 'dart:typed_data';
import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';

/// Represents a peer in the network
/// If a peer is in your database, they are your friend
class Peer {
  final Uint8List peerId;           // 8 bytes (truncated fingerprint)
  final Uint8List noisePk;          // 32 bytes Curve25519
  final Uint8List signPk;           // 32 bytes Ed25519
  final String displayName;
  final DateTime addedAt;
  final DateTime? lastSeen;
  final bool isVerified;            // Out-of-band verification done
  final Peripheral? peripheral;     // BLE peripheral if currently connected

  Peer({
    required this.peerId,
    required this.noisePk,
    required this.signPk,
    required this.displayName,
    DateTime? addedAt,
    this.lastSeen,
    this.isVerified = false,
    this.peripheral,
  }) : addedAt = addedAt ?? DateTime.now() {
    if (peerId.length != 8) {
      throw ArgumentError('PeerID must be 8 bytes');
    }
    if (noisePk.length != 32) {
      throw ArgumentError('Noise PK must be 32 bytes');
    }
    if (signPk.length != 32) {
      throw ArgumentError('Sign PK must be 32 bytes');
    }
  }

  /// Get peer ID as hex string
  String get peerIdHex => peerId.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// Copy with updated fields
  Peer copyWith({
    Uint8List? peerId,
    Uint8List? noisePk,
    Uint8List? signPk,
    String? displayName,
    DateTime? addedAt,
    DateTime? lastSeen,
    bool? isVerified,
    Peripheral? peripheral,
  }) {
    return Peer(
      peerId: peerId ?? this.peerId,
      noisePk: noisePk ?? this.noisePk,
      signPk: signPk ?? this.signPk,
      displayName: displayName ?? this.displayName,
      addedAt: addedAt ?? this.addedAt,
      lastSeen: lastSeen ?? this.lastSeen,
      isVerified: isVerified ?? this.isVerified,
      peripheral: peripheral ?? this.peripheral,
    );
  }

  /// Derive Service UUID from Noise public key (last 128 bits)
  String deriveServiceUUID() {
    // Extract last 16 bytes (128 bits) from 32-byte public key
    final last16Bytes = noisePk.sublist(16, 32);

    // Format as UUID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    final hex = last16Bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }

  @override
  String toString() {
    return 'Peer(name: $displayName, id: ${peerIdHex.substring(0, 8)}..., verified: $isVerified)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Peer) return false;

    // Compare peer IDs byte by byte
    if (peerId.length != other.peerId.length) return false;
    for (int i = 0; i < peerId.length; i++) {
      if (peerId[i] != other.peerId[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => peerIdHex.hashCode;
}
