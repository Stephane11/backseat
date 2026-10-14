import 'package:permission_handler/permission_handler.dart';

enum PermissionOutcome { granted, denied, permanentlyDenied }

class RecordingPermissions {
  const RecordingPermissions._();

  static Future<PermissionOutcome> requestMicrophone() =>
      _request(Permission.microphone);

  static Future<PermissionOutcome> requestNotifications() =>
      _request(Permission.notification);

  static Future<bool> isMicrophoneGranted() async =>
      (await Permission.microphone.status).isGranted;

  static Future<bool> isNotificationsGranted() async =>
      (await Permission.notification.status).isGranted;

  static Future<void> openSettings() => openAppSettings();

  static Future<PermissionOutcome> _request(Permission permission) async {
    final status = await permission.request();
    if (status.isGranted) return PermissionOutcome.granted;
    if (status.isPermanentlyDenied) return PermissionOutcome.permanentlyDenied;
    return PermissionOutcome.denied;
  }
}
