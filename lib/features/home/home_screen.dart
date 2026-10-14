import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/meeting.dart';
import '../../core/providers/app_providers.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_color_tokens.dart';
import '../../core/theme/app_radius.dart';
import '../../shared/formatting.dart';
import 'start_sheet.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _searching = false;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final tokens = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final meetings = ref.watch(meetingsProvider).value ?? const [];
    final visible =
        meetings
            .where((m) => m.title.toLowerCase().contains(_query.toLowerCase()))
            .toList()
          ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(_searching ? Icons.close : Icons.menu),
          onPressed: () => setState(() {
            _searching = !_searching;
            if (!_searching) _query = '';
          }),
        ),
        title: _searching
            ? TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search meetings',
                  border: InputBorder.none,
                ),
                onChanged: (value) => setState(() => _query = value),
              )
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push(AppRoutes.settings),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!_searching)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(greetingForNow(), style: textTheme.headlineMedium),
              ),
            ),
          Expanded(
            child: visible.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            meetings.isEmpty
                                ? Icons.graphic_eq
                                : Icons.search_off_outlined,
                            size: 40,
                            color: tokens.textSecondary,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            meetings.isEmpty
                                ? 'No meetings yet. Put the phone near the '
                                      'laptop speakers and tap Start listening.'
                                : 'No meetings match your search.',
                            textAlign: TextAlign.center,
                            style: textTheme.bodyMedium?.copyWith(
                              color: tokens.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 140),
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => Divider(color: tokens.border),
                    itemBuilder: (context, index) =>
                        _MeetingRow(meeting: visible[index]),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: _StartBar(
        onStart: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (_) => const StartSheet(),
        ),
      ),
    );
  }
}

class _MeetingRow extends StatelessWidget {
  const _MeetingRow({required this.meeting});

  final Meeting meeting;

  @override
  Widget build(BuildContext context) {
    final tokens = context.colors;
    final textTheme = Theme.of(context).textTheme;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(meeting.title, style: textTheme.titleMedium),
      subtitle: Text(
        '${formatRelativeDate(meeting.startedAt)} · ${formatTimer(meeting.duration)}',
        style: textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
      ),
      trailing: meeting.isLive
          ? Icon(
              Icons.fiber_manual_record,
              size: 14,
              color: tokens.severityHigh,
            )
          : meeting.analyses.isNotEmpty
          ? Icon(Icons.auto_awesome, size: 18, color: tokens.accent)
          : null,
      onTap: () => context.push(
        meeting.isLive
            ? AppRoutes.liveMeeting(meeting.id)
            : AppRoutes.meetingDetail(meeting.id),
      ),
    );
  }
}

class _StartBar extends StatelessWidget {
  const _StartBar({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final tokens = context.colors;
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        decoration: BoxDecoration(
          color: tokens.surfaceRaised,
          borderRadius: BorderRadius.circular(AppRadius.pillBar),
          border: Border.all(color: tokens.border),
        ),
        child: Material(
          color: tokens.accent,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onStart,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.mic, color: Colors.white),
                  SizedBox(width: 10),
                  Text(
                    'Start listening',
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
