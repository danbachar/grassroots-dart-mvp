import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Manages cryptographic identity (single key pair) and user profile with secure persistence
///
/// Simplified Architecture:
/// - Single key: Ed25519 for both signing and key agreement
/// - Service UUID: Derived from last 128 bits (16 bytes) of public key
/// - No separate peer ID - use full 32-byte public key as identifier
/// - Display name: User's display name (also stored securely)
class IdentityService {
  static const String _privateKeyKey = 'grassroots_private_key';
  static const String _displayNameKey = 'grassroots_display_name';

  final FlutterSecureStorage _secureStorage;

  // Single key pair
  SimpleKeyPair? _keyPair;

  // Public key (cached) - this is our identity
  Uint8List? _publicKey;

  // Display name (cached)
  String _displayName = 'Grassroots User';

  IdentityService() : _secureStorage = const FlutterSecureStorage();

  /// Initialize or load identity
  Future<void> initialize() async {
    await _loadOrGenerateKeys();
    await _loadDisplayName();
  }

  /// Load display name from secure storage
  Future<void> _loadDisplayName() async {
    final storedName = await _secureStorage.read(key: _displayNameKey);
    if (storedName != null && storedName.isNotEmpty) {
      _displayName = storedName;
      print('Loaded display name: $_displayName');
    }
  }

  /// Load existing key or generate new one
  Future<void> _loadOrGenerateKeys() async {
    try {
      // Try to load existing key
      final privateKeyStr = await _secureStorage.read(key: _privateKeyKey);

      if (privateKeyStr != null) {
        // Load from storage
        print('Loading existing identity key...');

        final privateKeyBytes = base64Decode(privateKeyStr);
        _keyPair = await _loadEd25519KeyPair(privateKeyBytes);

        // Extract public key
        _publicKey = Uint8List.fromList(await _keyPair!.extractPublicKey().then((pk) => pk.bytes));

        print('Identity loaded: PK=${_bytesToHex(_publicKey!.sublist(0, 8))}...');
      } else {
        // Generate new key
        await generateNewIdentity();
      }
    } catch (e) {
      print('Error loading key, generating new identity: $e');
      await generateNewIdentity();
    }
  }

  /// Generate a new identity (new key pair)
  Future<void> generateNewIdentity() async {
    print('Generating new identity...');

    // Generate Ed25519 key pair
    final ed25519 = Ed25519();
    _keyPair = await ed25519.newKeyPair();

    // Extract public key
    _publicKey = Uint8List.fromList(await _keyPair!.extractPublicKey().then((pk) => pk.bytes));

    // Persist private key securely
    final privateKeyBytes = await _keyPair!.extractPrivateKeyBytes();

    await _secureStorage.write(
      key: _privateKeyKey,
      value: base64Encode(privateKeyBytes),
    );

    print('New identity generated and persisted');
    print('Public Key: ${_bytesToHex(_publicKey!)}');
  }

  /// Load Ed25519 key pair from private key bytes
  Future<SimpleKeyPair> _loadEd25519KeyPair(List<int> privateKeyBytes) async {
    final ed25519 = Ed25519();
    return SimpleKeyPairData(
      privateKeyBytes,
      publicKey: await ed25519.newKeyPairFromSeed(privateKeyBytes).then((kp) => kp.extractPublicKey()),
      type: KeyPairType.ed25519,
    );
  }

  // ==================== Getters ====================

  /// Get public key (Ed25519, 32 bytes) - this IS our identity
  Uint8List get publicKey {
    if (_publicKey == null) {
      throw StateError('Identity not initialized');
    }
    return _publicKey!;
  }

  /// Get key pair for signing operations
  SimpleKeyPair get keyPair {
    if (_keyPair == null) {
      throw StateError('Identity not initialized');
    }
    return _keyPair!;
  }

  /// Derive service UUID from public key (last 128 bits)
  String deriveServiceUUID() {
    // Last 128 bits (16 bytes) of the 32-byte public key
    final last16Bytes = publicKey.sublist(16, 32);

    // Format as UUID
    final hex = last16Bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}'.toUpperCase();
  }

  /// Check if identity is initialized
  bool get isInitialized {
    return _keyPair != null;
  }

  /// Get display name
  String get displayName => _displayName;

  /// Set display name and persist it
  Future<void> setDisplayName(String name) async {
    if (name.trim().isEmpty) return;

    _displayName = name.trim();
    await _secureStorage.write(key: _displayNameKey, value: _displayName);
    print('Display name updated: $_displayName');
  }

  // ==================== Helpers ====================

  String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
