import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/db/app_database.dart';
import 'core/providers/app_providers.dart';
import 'core/router/app_router.dart';
import 'core/storage/api_key_store.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();

  // Load what the first frame depends on (onboarding redirect, theme,
  // settings, whether an API key exists) before showing anything.
  final db = AppDatabase();
  final keyStore = SecureApiKeyStore();
  final prefs = await StoredPrefs.load(db, keyStore);

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        apiKeyStoreProvider.overrideWithValue(keyStore),
        initialPrefsProvider.overrideWithValue(prefs),
      ],
      child: const BackseatApp(),
    ),
  );
}

class BackseatApp extends ConsumerWidget {
  const BackseatApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'Backseat',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
