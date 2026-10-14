import 'package:flutter_foreground_task/flutter_foreground_task.dart';

const _stopButtonId = 'btn_stop';

@pragma('vm:entry-point')
void startRecordingTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_RecordingTaskHandler());
}

/// Keeps the notification's elapsed-time text current and forwards the
/// notification's Stop button back to the main isolate, where the real
/// stop flow (save segments, navigate) runs. After Stop, the same service
/// stays up while the Whisper final pass runs, showing its progress instead.
class _RecordingTaskHandler extends TaskHandler {
  DateTime? _start;
  String? _overrideText;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _start = timestamp;
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    final start = _start;
    if (start == null || _overrideText != null) return;
    final elapsed = timestamp.difference(start);
    final hours = elapsed.inHours;
    final minutes = (elapsed.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    final clock = hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
    FlutterForegroundTask.updateService(notificationText: 'Recording • $clock');
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onNotificationButtonPressed(String id) {
    if (id == _stopButtonId) {
      FlutterForegroundTask.sendDataToMain({'action': 'stop'});
    }
  }

  @override
  void onReceiveData(Object data) {
    if (data is Map && data['text'] is String) {
      _overrideText = data['text'] as String;
      FlutterForegroundTask.updateService(
        notificationTitle: data['title'] as String?,
        notificationText: _overrideText,
        notificationButtons: const [],
      );
    }
  }
}

/// Wraps flutter_foreground_task: a persistent "Recording" notification with
/// a Stop action, plus the process-priority protection that keeps capture
/// and transcription running with the screen off (brief §3).
class RecordingForegroundService {
  const RecordingForegroundService._();

  static Future<void> start({required String meetingTitle}) async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'backseat_recording',
        channelName: 'Recording',
        channelDescription: 'Shown while Backseat is recording a meeting.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(1000),
        autoRunOnBoot: false,
        allowWakeLock: true,
      ),
    );

    if (await FlutterForegroundTask.checkNotificationPermission() !=
        NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    await FlutterForegroundTask.startService(
      serviceId: 1,
      serviceTypes: const [ForegroundServiceTypes.microphone],
      notificationTitle: meetingTitle,
      notificationText: 'Recording • 00:00',
      notificationButtons: const [
        NotificationButton(id: _stopButtonId, text: 'Stop'),
      ],
      callback: startRecordingTaskCallback,
    );
  }

  /// Replaces the timer text (used for final-pass progress after Stop).
  static Future<void> showStatus({
    required String title,
    required String text,
  }) async {
    if (!await FlutterForegroundTask.isRunningService) return;
    FlutterForegroundTask.sendDataToTask({'title': title, 'text': text});
  }

  static Future<bool> get isRunning => FlutterForegroundTask.isRunningService;

  static Future<void> stop() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }
}
