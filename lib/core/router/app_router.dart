import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/app_providers.dart';
import '../../features/history/meeting_detail_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/recording/live_meeting_screen.dart';
import '../../features/settings/settings_screen.dart';

class AppRoutes {
  const AppRoutes._();

  static const onboarding = '/onboarding';
  static const home = '/home';
  static const settings = '/settings';

  static String liveMeeting(String id) => '/meeting/live/$id';
  static String meetingDetail(String id) => '/meeting/$id';
}

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        redirect: (context, state) {
          final onboardingDone = ref.read(onboardingCompleteProvider);
          return onboardingDone ? AppRoutes.home : AppRoutes.onboarding;
        },
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/meeting/live/:id',
        builder: (context, state) =>
            LiveMeetingScreen(meetingId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/meeting/:id',
        builder: (context, state) =>
            MeetingDetailScreen(meetingId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
});
