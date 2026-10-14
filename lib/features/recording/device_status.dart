import 'package:flutter/services.dart';

class DeviceStatus {
  const DeviceStatus({
    required this.batteryPercent,
    required this.charging,
    required this.thermalStatus,
  });

  final int batteryPercent;
  final bool charging;

  /// Android `PowerManager.THERMAL_STATUS_*`: 0 none … 3 severe … 6 shutdown.
  final int thermalStatus;

  bool get lowBattery =>
      !charging && batteryPercent >= 0 && batteryPercent < 15;
  bool get hot => thermalStatus >= 3;

  static const _channel = MethodChannel('backseat/device');

  /// Null when unavailable (tests, other platforms).
  static Future<DeviceStatus?> read() async {
    try {
      final map = await _channel.invokeMapMethod<String, Object?>('status');
      if (map == null) return null;
      return DeviceStatus(
        batteryPercent: map['battery'] as int? ?? -1,
        charging: map['charging'] as bool? ?? false,
        thermalStatus: map['thermal'] as int? ?? 0,
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
