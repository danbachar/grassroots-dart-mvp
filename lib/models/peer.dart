import 'dart:typed_data';
import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';

/// Represents a peer in the network
/// If a peer is in your database, they are your friend
///
/// Simplified identity: just one Ed25519 public key (32 bytes)
class Peer {
  final Uint8List publicKey;       // 32 bytes Ed25519 - this IS the identity
  final String displayName;
  final DateTime addedAt;
  final DateTime? lastSeen;
  final bool isVerified;            // Out-of-band verification done
  final Peripheral? peripheral;     // BLE peripheral if currently connected

  Peer({
    required this.publicKey,
    required this.displayName,
    DateTime? addedAt,
    this.lastSeen,
    this.isVerified = false,
    this.peripheral,
  }) : addedAt = addedAt ?? DateTime.now() {
    if (publicKey.length != 32) {
      throw ArgumentError('Public key must be 32 bytes');
    }
  }

  /// Get public key as hex string
  String get publicKeyHex => publicKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// Copy with updated fields
  Peer copyWith({
    Uint8List? publicKey,
    String? displayName,
    DateTime? addedAt,
    DateTime? lastSeen,
    bool? isVerified,
    Peripheral? peripheral,
  }) {
    return Peer(
      publicKey: publicKey ?? this.publicKey,
      displayName: displayName ?? this.displayName,
      addedAt: addedAt ?? this.addedAt,
      lastSeen: lastSeen ?? this.lastSeen,
      isVerified: isVerified ?? this.isVerified,
      peripheral: peripheral ?? this.peripheral,
    );
  }

  /// Derive Service UUID from public key (last 128 bits)
  String deriveServiceUUID() {
    // Extract last 16 bytes (128 bits) from 32-byte public key
    final last16Bytes = publicKey.sublist(16, 32);

    // Format as UUID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    final hex = last16Bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }

  @override
  String toString() {
    return 'Peer(name: $displayName, pk: ${publicKeyHex.substring(0, 16)}..., verified: $isVerified)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Peer) return false;

    // Compare public keys byte by byte
    if (publicKey.length != other.publicKey.length) return false;
    for (int i = 0; i < publicKey.length; i++) {
      if (publicKey[i] != other.publicKey[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => publicKeyHex.hashCode;
}
