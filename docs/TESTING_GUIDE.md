# Testing Guide - Two Physical Devices

## Prerequisites

### What You Need
- ✅ 2 Android or iOS devices with BLE support
- ✅ USB cables to connect to computer
- ✅ Developer mode enabled on both devices
- ✅ Same WiFi network (for deployment)

## Build & Deploy

### Option 1: Build and Install Both Devices

```bash
# Connect Device A
flutter devices  # Note device ID
flutter run -d <device-a-id>

# Wait for install...
# Once running, disconnect Device A

# Connect Device B
flutter devices  # Note device ID
flutter run -d <device-b-id>
```

### Option 2: Build APKs (Android only)

```bash
# Build release APK
flutter build apk --release

# APK location:
# build/app/outputs/flutter-apk/app-release.apk

# Install on both devices via adb
adb -s <device-a-id> install build/app/outputs/flutter-apk/app-release.apk
adb -s <device-b-id> install build/app/outputs/flutter-apk/app-release.apk
```

## Testing Scenarios

### Scenario 1: Basic Discovery

**Goal**: Verify devices can discover each other

**Steps:**

**Device A (Alice)**
1. Open app → Go to Bluetooth tab
2. Tap "Advertise"
3. Check: "Stop Advertise" button shows (advertising active)
4. Note: Privacy chip shows "Visible"

**Device B (Bob)**
1. Open app → Go to Bluetooth tab
2. Tap "Scan"
3. Wait 2-5 seconds
4. **Expected**: See "User" device appear in discovered list
5. **Expected**: Shows Device A's peripheral UUID and RSSI

**Verify:**
- ✅ Device B discovers Device A
- ✅ RSSI value displayed (-30 to -90 dBm)
- ✅ Scan auto-stops after 10 seconds

### Scenario 2: Pairing

**Goal**: Establish BLE connection between devices

**Steps:**

**Device B (Bob)**
1. See Device A in discovered devices list
2. Tap "Pair" button
3. **Expected**: Button changes to ✓ checkmark (green)
4. **Expected**: Connection state log in console

**Device A (Alice)**
1. Should receive connection event
2. Check console logs for "Connection state changed"

**Verify:**
- ✅ Pair button changes to checkmark
- ✅ No errors in console
- ✅ Connection established

**Troubleshooting:**
- If pairing fails: Restart both apps
- If no checkmark: Check BLE permissions
- Check console logs for errors

### Scenario 3: Friend Request (Current Limitation)

**Note**: Friend request flow requires packet exchange over BLE characteristic writes. Current implementation may have issues with:
- Finding the correct characteristic UUID
- Writing to peripheral characteristics
- Receiving characteristic notifications

**If it works:**

**Device B → Device A**
1. After pairing, Device B should auto-send friend request
2. Device A should show friend request dialog
3. Device A taps "Accept"
4. Both should see each other in "Friends" section

**If it doesn't work (expected):**
- This is normal - crypto and proper characteristic handling not implemented yet
- Focus on verifying BLE connection works
- We'll implement proper packet exchange in next phase

### Scenario 4: Advertising with Privacy Levels

**Goal**: Test different privacy levels

**Device A (Alice)**
1. Tap privacy chip or settings icon
2. Select "Open" level
3. Tap back
4. Tap "Advertise"

**Device B (Bob)**
1. Tap "Scan"
2. **Expected**: See "User" device with name visible

**Change to Silent:**
1. Device A: Settings → Select "Silent"
2. Try to advertise
3. **Expected**: Should not advertise (privacy level prevents it)

**Verify:**
- ✅ Open level shows name in advertisement
- ✅ Silent level prevents advertising
- ✅ Privacy chip updates correctly

### Scenario 5: Scan Filtering (Friends-only vs All)

**Goal**: Test privacy-aware scanning

**Device A (Alice)**
1. Settings → Select "Visible" (Level 2)
2. Should scan only for known friends

**Device A (Alice)**
1. Settings → Select "Open" (Level 3)
2. Should scan for all devices

**Verify:**
- ✅ Level 2 scans with service UUID filter
- ✅ Level 3 scans without filter (finds more devices)

## Expected Behavior Matrix

| Privacy Level | Can Advertise? | Scan Mode | Visible Name? |
|---------------|----------------|-----------|---------------|
| Silent (1)    | ❌ No          | Friends only | N/A |
| Visible (2)   | ✅ Yes         | Friends only | ❌ No (UUID only) |
| Open (3)      | ✅ Yes         | All devices  | ✅ Yes |
| Social (4)    | ✅ Yes         | All devices  | ✅ Yes |

## What WILL Work

✅ BLE permissions request
✅ Advertising (with generated Service UUID)
✅ Scanning (with/without service UUID filter)
✅ Device discovery (see other device in list)
✅ RSSI display
✅ Connection attempt (BLE GATT connect)
✅ Privacy level changes
✅ UI navigation
✅ Settings page

## What WON'T Work Yet

❌ Friend request exchange (no crypto keys)
❌ Chat messages (no proper characteristic write/notify)
❌ Message delivery acks
❌ Packet serialization over BLE (not fully integrated)
❌ Persistence (everything lost on restart)

## Debugging

### Enable Verbose Logging

Check console output for:
```
Requesting Central authorization...
Central authorized: true
Peripheral authorized: true
Starting advertising as User with service <uuid>
Started advertising
Discovered device: User (<uuid>), RSSI: -45
```

### Common Issues

**Issue**: "Central authorized: false"
- **Fix**: Grant Bluetooth permissions in phone settings

**Issue**: "Device not discovered"
- **Fix**: Ensure both devices have Bluetooth ON
- **Fix**: Move devices closer (< 5 meters)
- **Fix**: Restart scan on Device B

**Issue**: "Pairing fails immediately"
- **Fix**: Clear Bluetooth cache in Android settings
- **Fix**: Forget device in Bluetooth settings
- **Fix**: Restart both apps

**Issue**: App crashes on connect
- **Fix**: Check logs for error
- **Fix**: This might happen - characteristic discovery might fail
- **Fix**: We'll fix in next phase with proper protocol integration

### Console Commands

While testing, you can monitor with:

```bash
# Watch Device A logs
adb -s <device-a-id> logcat | grep flutter

# Watch Device B logs
adb -s <device-b-id> logcat | grep flutter
```

## Success Criteria for This Test

### Minimum Viable Test (MVP)
- [ ] Both devices install successfully
- [ ] BLE permissions granted
- [ ] Device A can advertise
- [ ] Device B can discover Device A
- [ ] RSSI values displayed correctly
- [ ] Privacy level changes work

### Stretch Goals
- [ ] BLE connection succeeds
- [ ] Friend request dialog appears
- [ ] Can accept friend request
- [ ] Both devices show each other in friends list

### Don't Expect Yet
- Chat messages working
- Packet exchange working
- Persistence working

## Next Steps After Testing

Based on test results, we'll know:

1. **If BLE connection works**:
   - Implement proper characteristic discovery
   - Add characteristic write/notify
   - Integrate packet serialization

2. **If friend requests work**:
   - Add crypto key generation
   - Implement Noise Protocol handshake
   - Add signature verification

3. **If everything fails**:
   - Debug BLE library issues
   - Check characteristic UUIDs
   - Verify permissions

## Recording Results

Please note:
- ✅ What worked
- ❌ What failed
- 📋 Error messages from console
- 📸 Screenshots if possible

This will help debug and improve the next iteration!

## Build Commands Quick Reference

```bash
# Check connected devices
flutter devices

# Run on specific device
flutter run -d <device-id>

# Build APK (Android)
flutter build apk --release

# Build iOS (requires macOS + Xcode)
flutter build ios --release

# Install APK via ADB
adb install build/app/outputs/flutter-apk/app-release.apk

# View logs
adb logcat | grep flutter
```

Good luck with testing! 🚀
