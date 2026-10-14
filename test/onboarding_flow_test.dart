import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';

import 'package:backseat/core/providers/app_providers.dart';
import 'package:backseat/main.dart';

import 'test_utils.dart';

/// Starts every permission as not-yet-granted (like a fresh install) so the
/// onboarding flow's disabled -> tap Allow -> granted sequence is exercised;
/// requests always succeed, matching a user who taps "Allow" when prompted.
class _FakePermissions extends PermissionHandlerPlatform {
  @override
  Future<PermissionStatus> checkPermissionStatus(Permission permission) async =>
      PermissionStatus.denied;

  @override
  Future<Map<Permission, PermissionStatus>> requestPermissions(
    List<Permission> permissions,
  ) async => {for (final p in permissions) p: PermissionStatus.granted};

  @override
  Future<ServiceStatus> checkServiceStatus(Permission permission) async =>
      ServiceStatus.enabled;

  @override
  Future<bool> shouldShowRequestPermissionRationale(
    Permission permission,
  ) async => false;

  @override
  Future<bool> openAppSettings() async => true;
}

/// Pumps in small steps rather than one big jump: PageView's page-change
/// animation and the chained setState calls it triggers don't always
/// converge correctly from a single large `pump(duration)`.
Future<void> _settleInSteps(WidgetTester tester, {int steps = 10}) async {
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('onboarding walks through to Home', (tester) async {
    PermissionHandlerPlatform.instance = _FakePermissions();
    disableAnimations(tester);
    final db = await createSeededTestDatabase();
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: baseTestOverrides(
          db,
          prefs: const StoredPrefs(),
          downloads: FakeModelDownloadService(ready: false),
        ),
        child: const BackseatApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Backseat'), findsOneWidget);

    // Page 1 -> 2 -> 3: plain info pages, Continue is always enabled.
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Continue'));
      await _settleInSteps(tester);
    }

    // Mic permission page: Continue disabled until granted.
    expect(find.widgetWithText(ElevatedButton, 'Continue'), findsOneWidget);
    final continueButton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Continue'),
    );
    expect(continueButton.onPressed, isNull);

    await tester.tap(find.text('Allow access'));
    await _settleInSteps(tester);
    await tester.tap(find.text('Continue'));
    await _settleInSteps(tester);

    // Notification permission + real (stubbed) model download page.
    expect(find.text('Speech model ready'), findsOneWidget);
    await tester.tap(find.text('Allow access'));
    await _settleInSteps(tester);

    await tester.tap(find.text('Get started'));
    await _settleInSteps(tester);

    expect(find.text('Start listening'), findsOneWidget);
    // Completion is persisted, so the next launch skips onboarding.
    expect(await db.getSetting(PrefKeys.onboardingComplete), 'true');
  });
}
