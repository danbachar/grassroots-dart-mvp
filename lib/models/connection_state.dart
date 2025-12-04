/// Connection state machine states
enum ConnectionState {
  idle,          // No connection; scanning or advertising
  connecting,    // BLE GATT connection in progress
  handshaking,   // Noise XX handshake in progress (future)
  established,   // Secure session active; can exchange messages
  disconnected,  // Connection lost; may retry
}

/// Connection information for a peer
class PeerConnection {
  final String peripheralId;      // BLE peripheral UUID (OS-assigned)
  final ConnectionState state;
  final DateTime? connectedAt;
  final DateTime? lastActivity;
  final int handshakeAttempts;

  PeerConnection({
    required this.peripheralId,
    this.state = ConnectionState.idle,
    this.connectedAt,
    this.lastActivity,
    this.handshakeAttempts = 0,
  });

  /// Copy with updated fields
  PeerConnection copyWith({
    String? peripheralId,
    ConnectionState? state,
    DateTime? connectedAt,
    DateTime? lastActivity,
    int? handshakeAttempts,
  }) {
    return PeerConnection(
      peripheralId: peripheralId ?? this.peripheralId,
      state: state ?? this.state,
      connectedAt: connectedAt ?? this.connectedAt,
      lastActivity: lastActivity ?? this.lastActivity,
      handshakeAttempts: handshakeAttempts ?? this.handshakeAttempts,
    );
  }

  /// Transition to a new state with updated timestamp
  PeerConnection transitionTo(ConnectionState newState) {
    return copyWith(
      state: newState,
      lastActivity: DateTime.now(),
      connectedAt: newState == ConnectionState.established ? DateTime.now() : connectedAt,
    );
  }

  /// Check if connection is established
  bool get isEstablished => state == ConnectionState.established;

  /// Check if connection is idle
  bool get isIdle => state == ConnectionState.idle || state == ConnectionState.disconnected;

  /// Check if handshake timed out
  bool get hasHandshakeTimeout {
    if (state != ConnectionState.handshaking || lastActivity == null) {
      return false;
    }
    final elapsed = DateTime.now().difference(lastActivity!);
    return elapsed.inMilliseconds > 10000; // 10 second timeout
  }

  /// Check if connection is idle for too long
  bool get isIdleTooLong {
    if (!isEstablished || lastActivity == null) {
      return false;
    }
    final elapsed = DateTime.now().difference(lastActivity!);
    return elapsed.inMilliseconds > 60000; // 60 second idle timeout
  }

  @override
  String toString() {
    return 'PeerConnection(id: $peripheralId, state: $state, attempts: $handshakeAttempts)';
  }
}
