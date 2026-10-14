import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/app_providers.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_color_tokens.dart';
import '../recording/model_download_service.dart';
import '../recording/permissions.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  int _page = 0;
  bool _micGranted = false;
  bool _notificationsGranted = false;

  static const _pageCount = 5;

  @override
  void initState() {
    super.initState();
    _refreshPermissionStatus();
  }

  Future<void> _refreshPermissionStatus() async {
    final mic = await RecordingPermissions.isMicrophoneGranted();
    final notif = await RecordingPermissions.isNotificationsGranted();
    if (!mounted) return;
    setState(() {
      _micGranted = mic;
      _notificationsGranted = notif;
    });
  }

  Future<void> _requestMicrophone() async {
    final outcome = await RecordingPermissions.requestMicrophone();
    if (!mounted) return;
    if (outcome == PermissionOutcome.granted) {
      setState(() => _micGranted = true);
    } else if (outcome == PermissionOutcome.permanentlyDenied) {
      _showOpenSettingsPrompt(
        'Microphone access was denied. Enable it in system settings to continue.',
      );
    }
  }

  Future<void> _requestNotifications() async {
    final outcome = await RecordingPermissions.requestNotifications();
    if (!mounted) return;
    if (outcome == PermissionOutcome.granted) {
      setState(() => _notificationsGranted = true);
    } else if (outcome == PermissionOutcome.permanentlyDenied) {
      _showOpenSettingsPrompt(
        'Notification access was denied. Enable it in system settings so recording can run reliably in the background.',
      );
    }
  }

  void _showOpenSettingsPrompt(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: 'Settings',
          onPressed: RecordingPermissions.openSettings,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _startDownloadIfNeeded() {
    final state = ref.read(modelDownloadsProvider)[_liveModel];
    if (state?.status == ModelStatus.ready ||
        state?.status == ModelStatus.downloading) {
      return;
    }
    unawaited(ref.read(modelDownloadsProvider.notifier).download(_liveModel));
  }

  static const _liveModel = AsrModelId.streamingZipformerEn;

  bool get _modelReady =>
      ref.read(modelDownloadsProvider)[_liveModel]?.status == ModelStatus.ready;

  void _next() {
    if (_page == _pageCount - 1) {
      ref.read(onboardingCompleteProvider.notifier).complete();
      context.go(AppRoutes.home);
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  bool get _canContinue {
    return switch (_page) {
      3 => _micGranted,
      4 => _notificationsGranted && _modelReady,
      _ => true,
    };
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.colors;
    // Rebuild when the download finishes so Continue enables.
    ref.watch(modelDownloadsProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (page) {
                  setState(() => _page = page);
                  if (page == 4) _startDownloadIfNeeded();
                },
                children: [
                  const _InfoPage(
                    icon: Icons.record_voice_over_outlined,
                    image: 'assets/branding/logo_mark.png',
                    title: 'Backseat',
                    body:
                        'A quiet second opinion for your meetings — listens alongside '
                        'you and gives sharp, specific feedback when you ask for it.',
                  ),
                  const _InfoPage(
                    icon: Icons.graphic_eq,
                    title: 'How it works',
                    body:
                        'Start listening, and the transcript streams in live, fully '
                        'on-device. Tap Analyse any time to get issues, risks and ideas.',
                  ),
                  const _InfoPage(
                    icon: Icons.lock_outline,
                    title: 'Your data stays yours',
                    body:
                        'Audio never leaves your phone. Only the transcript text is '
                        'sent to Claude, and only when you tap Analyse.',
                  ),
                  _PermissionPage(
                    icon: Icons.mic_none_outlined,
                    title: 'Microphone access',
                    body:
                        'Backseat needs the microphone to transcribe the room while '
                        'a meeting is running.',
                    granted: _micGranted,
                    onGrant: _requestMicrophone,
                  ),
                  _PermissionPage(
                    icon: Icons.notifications_none_outlined,
                    title: 'Notification access',
                    body:
                        'A persistent notification keeps recording running reliably '
                        'in the background, with a Stop action.',
                    granted: _notificationsGranted,
                    onGrant: _requestNotifications,
                    extra: const Padding(
                      padding: EdgeInsets.only(top: 20),
                      child: _ModelDownloadProgress(),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < _pageCount; i++)
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i == _page ? tokens.accent : tokens.border,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _canContinue ? _next : null,
                      child: Text(
                        _page == _pageCount - 1 ? 'Get started' : 'Continue',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoPage extends StatelessWidget {
  const _InfoPage({
    required this.icon,
    required this.title,
    required this.body,
    this.image,
  });

  final IconData icon;
  final String title;
  final String body;

  /// Asset shown instead of [icon] (the app logo on the welcome page).
  final String? image;

  @override
  Widget build(BuildContext context) {
    final tokens = context.colors;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (image != null)
            Image.asset(
              image!,
              height: 120,
              semanticLabel: 'Backseat logo',
              errorBuilder: (_, _, _) =>
                  Icon(icon, size: 64, color: tokens.accent),
            )
          else
            Icon(icon, size: 64, color: tokens.accent),
          const SizedBox(height: 24),
          Text(
            title,
            style: textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            body,
            style: textTheme.bodyLarge?.copyWith(color: tokens.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _PermissionPage extends StatelessWidget {
  const _PermissionPage({
    required this.icon,
    required this.title,
    required this.body,
    required this.granted,
    required this.onGrant,
    this.extra,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool granted;
  final VoidCallback onGrant;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final tokens = context.colors;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: tokens.accent),
          const SizedBox(height: 24),
          Text(
            title,
            style: textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            body,
            style: textTheme.bodyLarge?.copyWith(color: tokens.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          if (granted)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle, color: tokens.severityLow, size: 18),
                const SizedBox(width: 6),
                const Text('Allowed'),
              ],
            )
          else
            OutlinedButton(
              onPressed: onGrant,
              child: const Text('Allow access'),
            ),
          ?extra,
        ],
      ),
    );
  }
}

/// Live model download status on the last onboarding page, with an optional
/// head start on the (larger) final-pass model.
class _ModelDownloadProgress extends ConsumerWidget {
  const _ModelDownloadProgress();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final downloads = ref.watch(modelDownloadsProvider);
    final notifier = ref.read(modelDownloadsProvider.notifier);
    final live = downloads[AsrModelId.streamingZipformerEn]!;
    final finalId = finalPassModelId(
      ref.watch(settingsProvider).finalPassModel,
    );
    final finalState = finalId == null ? null : downloads[finalId];
    final liveSpec = kAsrModels[AsrModelId.streamingZipformerEn]!;

    final label = switch (live.status) {
      ModelStatus.ready => 'Speech model ready',
      ModelStatus.error => live.error ?? 'Download failed',
      ModelStatus.downloading =>
        'Downloading on-device speech model (${liveSpec.sizeLabel})… '
            '${(live.progress * 100).round()}%',
      _ => 'Preparing speech model download…',
    };

    return Column(
      children: [
        Text(
          label,
          style: textTheme.bodySmall?.copyWith(
            color: live.status == ModelStatus.error
                ? tokens.severityHigh
                : tokens.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: live.status == ModelStatus.ready ? 1 : live.progress,
            minHeight: 6,
          ),
        ),
        if (live.status == ModelStatus.error)
          TextButton(
            onPressed: () => notifier.download(AsrModelId.streamingZipformerEn),
            child: const Text('Retry'),
          ),
        if (finalId != null && finalState != null) ...[
          const SizedBox(height: 12),
          if (finalState.status == ModelStatus.missing)
            TextButton(
              onPressed: () => notifier.download(finalId),
              child: Text(
                'Also download the accurate final-pass model '
                '(${kAsrModels[finalId]!.sizeLabel})',
                textAlign: TextAlign.center,
              ),
            )
          else if (finalState.status == ModelStatus.downloading)
            Text(
              'Final-pass model: ${(finalState.progress * 100).round()}% '
              '(continues in the background)',
              style: textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
              textAlign: TextAlign.center,
            ),
        ],
      ],
    );
  }
}
