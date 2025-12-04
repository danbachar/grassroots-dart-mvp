# Grassroots Protocol Overview

## Architecture

**"Always Advertising + Connect-to-Send"**
- All devices continuously advertise their unique service UUID (derived from their Noise public key)
- To send any data, the sender connects to the target, writes to the appropriate characteristic, then disconnects
- Scanning runs in duty cycles: 10s scan → 5s pause → repeat
- Device cache with 10-minute TTL for discovered peers

## BLE Characteristics

Each device advertises a GATT service with three write-only characteristics:

| Characteristic | UUID | Purpose |
|---------------|------|---------|
| Friend Request | `A1B2C3D4-E5F6-4A5B-8C9D-0E1F2A3B4C6D` | Send friend requests |
| Friend Response | `A1B2C3D4-E5F6-4A5B-8C9D-0E1F2A3B4C7D` | Send accept/reject responses |
| Message | `A1B2C3D4-E5F6-4A5B-8C9D-0E1F2A3B4C8D` | Send chat messages, delivery acks, read receipts |

## Transport Layer Chunking

BLE has limited MTU. The transport layer chunks large messages:

### Chunk Header (3 bytes)
```
┌──────────┬─────────────────┐
│ Type (1) │ Message ID (2)  │
└──────────┴─────────────────┘
```

### Chunk Types
| Type | Value | Description |
|------|-------|-------------|
| SINGLE | `0x01` | Complete message in one chunk |
| FIRST | `0x02` | First chunk of multi-chunk message |
| MIDDLE | `0x03` | Middle chunk |
| LAST | `0x04` | Final chunk |

- Max chunk size: 18 bytes (3 header + 15 data)
- Messages ≤15 bytes use SINGLE chunk
- Larger messages are split across FIRST → MIDDLE(s) → LAST

---

## Packet Structure

All protocol messages use a common packet format:

### Header (14 bytes)
```
┌─────────┬──────┬─────┬───────┬───────────────┬────────────────┐
│ Version │ Type │ TTL │ Flags │ Timestamp (8) │ PayloadLen (2) │
│   (1)   │ (1)  │ (1) │  (1)  │               │                │
└─────────┴──────┴─────┴───────┴───────────────┴────────────────┘
```

### Variable Fields (after header)
```
┌────────────┬───────────────────┬─────────────────┬─────────────────┐
│ Sender ID  │ Recipient ID      │ Payload         │ Signature       │
│ (8 bytes)  │ (8, if flag set)  │ (variable)      │ (64, if flag)   │
└────────────┴───────────────────┴─────────────────┴─────────────────┘
```

### Flags
| Bit | Name | Description |
|-----|------|-------------|
| 0 | `hasRecipient` | Recipient ID field present |
| 1 | `hasSignature` | Ed25519 signature present |
| 2 | `isCompressed` | Payload is compressed |
| 3 | `hasRoute` | Routing information present |

---

## Message Types

### Chat Messages

| Type | Code | Description |
|------|------|-------------|
| Message | `0x01` | Chat message |
| Delivery Ack | `0x02` | Delivery acknowledgment |
| Read Receipt | `0x03` | Read receipt |

### Friendship

| Type | Code | Description |
|------|------|-------------|
| Friend Request | `0x20` | Request to become friends |
| Friend Accept | `0x21` | Accept friend request |
| Friend Reject | `0x22` | Reject friend request |

### Fragmentation (for large payloads)

| Type | Code | Description |
|------|------|-------------|
| Fragment Start | `0xF0` | First fragment |
| Fragment Continue | `0xF1` | Middle fragment |
| Fragment End | `0xF2` | Last fragment |

---

## Payload Formats

### Chat Message (`0x01`)
```
┌────────────────┬────────────────┬─────────────────┐
│ Message ID (16)│ Content Len (2)│ Content (UTF-8) │
└────────────────┴────────────────┴─────────────────┘
```

### Delivery Ack (`0x02`) / Read Receipt (`0x03`)
```
┌────────────────┐
│ Message ID (16)│
└────────────────┘
```

### Friend Request (`0x20`) / Friend Accept (`0x21`)
```
┌────────────────┬────────────────┬──────────┬──────────────┬────────────────┐
│ Noise PK (32)  │ Sign PK (32)   │ Name Len │ Display Name │ Signature (64) │
│                │                │   (1)    │  (variable)  │   (optional)   │
└────────────────┴────────────────┴──────────┴──────────────┴────────────────┘
```

### Friend Reject (`0x22`)
```
(empty payload)
```

---

## Message Status Flow

```
┌─────────┐     Write ACK      ┌──────┐    Delivery Ack    ┌───────────┐    Read Receipt    ┌──────┐
│ PENDING │ ─────────────────► │ SENT │ ─────────────────► │ DELIVERED │ ─────────────────► │ READ │
└─────────┘                    └──────┘                    └───────────┘                    └──────┘
   (grey)                      (green ✓)                   (green ✓✓)                      (blue ✓✓)
```

1. **Pending**: Message created, waiting to send
2. **Sent**: BLE write-with-response succeeded (remote acknowledged write)
3. **Delivered**: Remote device processed message and sent DeliveryAck
4. **Read**: Recipient opened chat, sent ReadReceipt

---

## Friend Request Flow

```
    Device A                                    Device B
       │                                           │
       │  1. Connect to B                          │
       ├──────────────────────────────────────────►│
       │                                           │
       │  2. Write FriendRequest to FRIEND_REQUEST │
       ├──────────────────────────────────────────►│
       │                                           │
       │  3. Disconnect                            │ 4. Show dialog
       │◄──────────────────────────────────────────┤    to user
       │                                           │
       │                                           │ 5. User accepts
       │                                           │
       │  6. Connect to A                          │
       │◄──────────────────────────────────────────┤
       │                                           │
       │  7. Write FriendAccept to FRIEND_RESPONSE │
       │◄──────────────────────────────────────────┤
       │                                           │
       │  8. Disconnect                            │
       │──────────────────────────────────────────►│
       │                                           │
       │         ✓ Both now have each other as friends
```

---

## Privacy Levels

| Level | Name | Advertising | Scanning |
|-------|------|-------------|----------|
| 1 | Silent | None | Friends only |
| 2 | Visible | UUID only | Friends only |
| 3 | Open | UUID + Name | All devices |
| 4 | Social | UUID + Name | All devices |

---

## Identity

Each peer has:
- **Peer ID**: 8 bytes (truncated fingerprint)
- **Noise PK**: 32 bytes (Curve25519 for encryption)
- **Sign PK**: 32 bytes (Ed25519 for signatures)
- **Service UUID**: Derived from last 128 bits of Noise PK

---

## Timeouts & Limits

| Parameter | Value |
|-----------|-------|
| Connection timeout | 10s |
| Friend request cooldown | 5 min |
| Message expiry | 24 hours |
| Device cache TTL | 10 min |
| Max message size | 65535 bytes |
| Max display name | 63 bytes |
| Max friends | 1000 |
| Default TTL (hops) | 7 |
| Max retries | 4 |
| Retry backoff | 2s, 4s, 8s, 16s |
