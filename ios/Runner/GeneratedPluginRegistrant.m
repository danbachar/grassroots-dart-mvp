//
//  Generated file. Do not edit.
//

// clang-format off

#import "GeneratedPluginRegistrant.h"

#if __has_include(<ble_peripheral/BlePeripheralPlugin.h>)
#import <ble_peripheral/BlePeripheralPlugin.h>
#else
@import ble_peripheral;
#endif

#if __has_include(<bluetooth_low_energy_darwin/BluetoothLowEnergyDarwinPlugin.h>)
#import <bluetooth_low_energy_darwin/BluetoothLowEnergyDarwinPlugin.h>
#else
@import bluetooth_low_energy_darwin;
#endif

#if __has_include(<permission_handler_apple/PermissionHandlerPlugin.h>)
#import <permission_handler_apple/PermissionHandlerPlugin.h>
#else
@import permission_handler_apple;
#endif

@implementation GeneratedPluginRegistrant

+ (void)registerWithRegistry:(NSObject<FlutterPluginRegistry>*)registry {
  [BlePeripheralPlugin registerWithRegistrar:[registry registrarForPlugin:@"BlePeripheralPlugin"]];
  [BluetoothLowEnergyDarwinPlugin registerWithRegistrar:[registry registrarForPlugin:@"BluetoothLowEnergyDarwinPlugin"]];
  [PermissionHandlerPlugin registerWithRegistrar:[registry registrarForPlugin:@"PermissionHandlerPlugin"]];
}

@end
