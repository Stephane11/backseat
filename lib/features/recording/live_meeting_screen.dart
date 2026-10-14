import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/models/meeting.dart';
import '../../core/models/settings_state.dart';
import '../../core/providers/app_providers.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_color_tokens.dart';
import '../../core/theme/app_radius.dart';
import '../../shared/formatting.dart';
import '../../shared/transcript_view.dart';
import '../analysis/analysis_flow.dart';
import '../transcript/final_pass.dart';
import 'device_status.dart';
import 'fake_transcription_engine.dart';
import 'permissions.dart';
import 'recording_foreground_service.dart';
import 'transcription_engine.dart';
import 'transcription_engine_provider.dart';

/// Below this peak level for [_lowAudioAfter], show a placement hint.
const _lowAudioLevel = 0.02;
const _lowAudioAfter = Duration(seconds: 10);

class LiveMeetingScreen extends ConsumerStatefulWidget {
  const LiveMeetingScreen({super.key, required this.meetingId});

  final String meetingId;

  @override
  ConsumerState<LiveMeetingScreen> createState() => _LiveMeetingScreenState();
}

class _LiveMeetingScreenState extends ConsumerState<LiveMeetingScreen> {
  final _jumpController = TranscriptJumpController();
  final _scrollController = ScrollController();

  TranscriptionEngine? _engine;
  StreamSubscription<double>? _levelSub;
  StreamSubscription? _segmentSub;
  Timer? _clock;
  Timer? _deviceTimer;

  double _level = 0;
  DateTime _lastLoud = DateTime.now();
  DeviceStatus? _device;
  bool _atBottom = true;
  bool _isReal = false;
  bool _stopping = false;
  late bool _checkDocs = ref.read(settingsProvider).checkDocsDefault;
  TranscriptionStartException? _startError;

  @override
  void initState() {
    super.initState();
    unawaited(_initEngine());
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _scrollController.addListener(() {
      final atBottom =
          _scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 24;
      if (atBottom != _atBottom) setState(() => _atBottom = atBottom);
    });
  }

  Future<void> _initEngine() async {
    setState(() => _startError = null);
    final meeting = ref.read(meetingsProvider.notifier).byId(widget.meetingId);
    if (meeting == null) return;

    TranscriptionEngine? engine;
    try {
      engine = await ref.read(transcriptionEngineBuilderProvider)(meeting);
      _isReal = engine is! FakeTranscriptionEngine;

      if (_isReal) {
        // A microphone foreground service may only start once the
        // permission is granted (Android 14+).
        if (!await RecordingPermissions.isMicrophoneGranted() &&
            await RecordingPermissions.requestMicrophone() !=
                PermissionOutcome.granted) {
          throw const TranscriptionStartException(
            'Microphone access is off. Allow it in system settings to record.',
          );
        }
        FlutterForegroundTask.addTaskDataCallback(_onForegroundTaskData);
        await RecordingForegroundService.start(meetingTitle: meeting.title);
        unawaited(WakelockPlus.enable());
      }

      _segmentSub = engine.segments.listen((segment) {
        // Engine ids restart at 0 per recording; scope them to the meeting
        // so they never collide in the database.
        unawaited(
          ref
              .read(meetingsProvider.notifier)
              .upsertSegment(
                widget.meetingId,
                segment.copyWith(id: '${widget.meetingId}_${segment.id}'),
              ),
        );
        if (_atBottom) _scrollToBottom();
      });
      _levelSub = engine.audioLevel.listen((level) {
        if (level > _lowAudioLevel) _lastLoud = DateTime.now();
        if (mounted) setState(() => _level = level);
      });

      await engine.start();
      final audioPath = engine.audioPath;
      if (audioPath != null) {
        await ref
            .read(meetingsProvider.notifier)
            .setAudioPath(widget.meetingId, audioPath);
      }
      _lastLoud = DateTime.now();
      if (_isReal) {
        unawaited(_pollDevice());
        _deviceTimer = Timer.periodic(
          const Duration(seconds: 60),
          (_) => _pollDevice(),
        );
      }
      if (!mounted) return;
      setState(() => _engine = engine);
    } on TranscriptionStartException catch (e) {
      await _teardownAfterFailedStart(engine);
      if (mounted) setState(() => _startError = e);
    } catch (e) {
      await _teardownAfterFailedStart(engine);
      if (mounted) {
        setState(
          () => _startError = TranscriptionStartException(
            "Couldn't start recording: $e",
          ),
        );
      }
    }
  }

  Future<void> _teardownAfterFailedStart(TranscriptionEngine? engine) async {
    await _segmentSub?.cancel();
    await _levelSub?.cancel();
    _segmentSub = null;
    _levelSub = null;
    if (engine != null) await engine.dispose();
    if (_isReal) {
      FlutterForegroundTask.removeTaskDataCallback(_onForegroundTaskData);
      await RecordingForegroundService.stop();
      await WakelockPlus.disable();
    }
  }

  Future<void> _pollDevice() async {
    final status = await DeviceStatus.read();
    if (mounted) setState(() => _device = status);
  }

  void _onForegroundTaskData(Object data) {
    if (data is Map && data['action'] == 'stop') {
      unawaited(_onStop());
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _levelSub?.cancel();
    _segmentSub?.cancel();
    _clock?.cancel();
    _deviceTimer?.cancel();
    final engine = _engine;
    if (engine != null) {
      unawaited(engine.stop().whenComplete(engine.dispose));
    }
    if (_isReal) {
      FlutterForegroundTask.removeTaskDataCallback(_onForegroundTaskData);
      if (!_stopping) unawaited(RecordingForegroundService.stop());
      unawaited(WakelockPlus.disable());
    }
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _onStop() async {
    if (_stopping) return;
    _stopping = true;
    HapticFeedback.lightImpact();
    setState(() {});

    final engine = _engine;
    _engine = null;
    _deviceTimer?.cancel();
    if (engine != null) {
      // Flush the last utterance before stamping the meeting as ended.
      await engine.stop();
      await _segmentSub?.cancel();
      await _levelSub?.cancel();
      unawaited(engine.dispose());
    }
    final meetings = ref.read(meetingsProvider.notifier);
    await meetings.stopMeeting(widget.meetingId);
    ref.read(activeMeetingIdProvider.notifier).set(null);
    if (_isReal) unawaited(WakelockPlus.disable());

    final meeting = meetings.byId(widget.meetingId);
    final finalPass = ref.read(finalPassProvider.notifier);
    if (meeting != null && await finalPass.canRun(meeting)) {
      // Keeps the foreground service alive (now showing progress) until the
      // final pass finishes, then stops it.
      unawaited(finalPass.run(widget.meetingId));
    } else {
      if (_isReal) unawaited(RecordingForegroundService.stop());
      if (meeting?.audioPath != null &&
          ref.read(settingsProvider).finalPassModel == FinalPassModel.off &&
          ref.read(settingsProvider).audioRetention ==
              AudioRetention.deleteImmediately) {
        // The live transcript is the final one: nothing needs the audio.
        await meetings.deleteAudio(widget.meetingId);
      }
    }
    if (!mounted) return;
    context.go(AppRoutes.meetingDetail(widget.meetingId));
  }

  Future<void> _onBack() async {
    final stop = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stop recording?'),
        content: const Text(
          'Leaving this screen stops the recording and saves the meeting.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep recording'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Stop & save'),
          ),
        ],
      ),
    );
    if (stop == true) await _onStop();
  }

  Future<void> _leaveAfterError() async {
    final meetings = ref.read(meetingsProvider.notifier);
    final meeting = meetings.byId(widget.meetingId);
    ref.read(activeMeetingIdProvider.notifier).set(null);
    if (meeting != null && meeting.segments.isEmpty) {
      await meetings.delete(widget.meetingId);
    } else {
      await meetings.stopMeeting(widget.meetingId);
    }
    if (mounted) context.go(AppRoutes.home);
  }

  void _onAnalyse(Meeting meeting) {
    startAnalysis(
      context,
      ref,
      meetingId: meeting.id,
      checkDocs: _checkDocs,
      onTimestampTap: (ts) => _jumpController.jumpToNearest(
        ref.read(meetingsProvider.notifier).byId(meeting.id)?.segments ??
            meeting.segments,
        ts,
        scrollController: _scrollController,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final meeting = ref.watch(
      meetingsProvider.select(
        (async) =>
            async.value?.where((m) => m.id == widget.meetingId).firstOrNull,
      ),
    );

    final startError = _startError;
    if (startError != null) {
      return _StartErrorView(
        error: startError,
        onRetry: _initEngine,
        onLeave: _leaveAfterError,
      );
    }

    if (meeting == null || (_engine == null && !_stopping)) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Preparing microphone…',
                style: textTheme.bodyMedium?.copyWith(
                  color: tokens.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final sinceAnalysis = meeting.analyses.isEmpty
        ? meeting.duration
        : meeting.duration - meeting.analyses.last.transcriptUpTo;
    final newMinutes = sinceAnalysis.inMinutes;
    final lowAudio =
        !_stopping && DateTime.now().difference(_lastLoud) > _lowAudioAfter;
    final device = _device;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_onBack());
      },
      child: Scaffold(
        appBar: AppBar(title: Text(meeting.title)),
        body: Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Row(
                    children: [
                      _PulsingDot(color: tokens.severityHigh),
                      const SizedBox(width: 8),
                      Text(
                        _stopping ? 'Saving…' : 'Recording',
                        style: textTheme.labelMedium,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        formatTimer(meeting.duration),
                        style: textTheme.labelMedium,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: _level.clamp(0.03, 1.0)),
                      duration: const Duration(milliseconds: 120),
                      builder: (context, value, _) => LinearProgressIndicator(
                        value: value,
                        minHeight: 4,
                        backgroundColor: tokens.surfaceRaised,
                        valueColor: AlwaysStoppedAnimation(tokens.accent),
                      ),
                    ),
                  ),
                ),
                if (lowAudio)
                  const _Banner(
                    icon: Icons.volume_down_outlined,
                    text:
                        'Low audio. Move the phone closer to the laptop '
                        'speakers or turn the volume up.',
                  ),
                if (device != null && device.lowBattery)
                  _Banner(
                    icon: Icons.battery_alert_outlined,
                    text:
                        'Battery at ${device.batteryPercent}%. Plug in to '
                        'keep recording reliably.',
                  ),
                if (device != null && device.hot)
                  const _Banner(
                    icon: Icons.thermostat_outlined,
                    text:
                        'Your phone is getting hot. Take it out of a case or '
                        'away from the laptop vents.',
                  ),
                const SizedBox(height: 8),
                Expanded(
                  child: TranscriptView(
                    segments: meeting.segments,
                    jumpController: _jumpController,
                    scrollController: _scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
                    emptyText:
                        'Listening… the transcript appears here as people '
                        'speak.',
                  ),
                ),
              ],
            ),
            if (!_atBottom)
              Positioned(
                bottom: 96,
                right: 20,
                child: ActionChip(
                  avatar: const Icon(Icons.arrow_downward, size: 16),
                  label: const Text('Jump to latest'),
                  onPressed: _scrollToBottom,
                ),
              ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: tokens.surfaceRaised,
              borderRadius: BorderRadius.circular(AppRadius.pillBar),
              border: Border.all(color: tokens.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _stopping ? null : _onStop,
                    child: const Text('Stop'),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: _checkDocs
                      ? 'Check against docs: on'
                      : 'Check against docs: off',
                  isSelected: _checkDocs,
                  icon: const Icon(Icons.menu_book_outlined),
                  selectedIcon: Icon(Icons.menu_book, color: tokens.accent),
                  onPressed: () => setState(() => _checkDocs = !_checkDocs),
                ),
                const SizedBox(width: 4),
                Expanded(
                  flex: 2,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _stopping
                              ? null
                              : () => _onAnalyse(meeting),
                          child: const Text('Analyse'),
                        ),
                      ),
                      if (newMinutes > 0)
                        Positioned(
                          top: -6,
                          right: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: tokens.severityMedium,
                              borderRadius: BorderRadius.circular(
                                AppRadius.chip,
                              ),
                            ),
                            child: Text(
                              '+${newMinutes}m',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = context.colors;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: tokens.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: tokens.severityMedium),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

/// The red "recording" dot, gently pulsing (static with reduce-motion on).
class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color});

  final Color color;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
    lowerBound: 0.35,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _controller.value = 1;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}

class _StartErrorView extends StatelessWidget {
  const _StartErrorView({
    required this.error,
    required this.onRetry,
    required this.onLeave,
  });

  final TranscriptionStartException error;
  final VoidCallback onRetry;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final tokens = context.colors;
    final textTheme = Theme.of(context).textTheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onLeave();
      },
      child: Scaffold(
        appBar: AppBar(),
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.mic_off_outlined, size: 48, color: tokens.accent),
                const SizedBox(height: 16),
                Text(
                  "Can't start listening",
                  style: textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  error.message,
                  style: textTheme.bodyMedium?.copyWith(
                    color: tokens.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    OutlinedButton(
                      onPressed: onLeave,
                      child: const Text('Back'),
                    ),
                    if (error.needsModel)
                      OutlinedButton(
                        onPressed: () => context.push(AppRoutes.settings),
                        child: const Text('Open Settings'),
                      )
                    else
                      OutlinedButton(
                        onPressed: RecordingPermissions.openSettings,
                        child: const Text('System settings'),
                      ),
                    FilledButton(
                      onPressed: onRetry,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
