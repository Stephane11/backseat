import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/app_providers.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_color_tokens.dart';

class StartSheet extends ConsumerStatefulWidget {
  const StartSheet({super.key});

  @override
  ConsumerState<StartSheet> createState() => _StartSheetState();
}

class _StartSheetState extends ConsumerState<StartSheet> {
  final _titleController = TextEditingController();
  final _contextController = TextEditingController();
  final _termsController = TextEditingController();
  bool _starting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _contextController.dispose();
    _termsController.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_starting) return;
    setState(() => _starting = true);
    HapticFeedback.lightImpact();
    final context = this.context;
    final meeting = await ref
        .read(meetingsProvider.notifier)
        .startMeeting(
          title: _titleController.text,
          contextNote: _contextController.text.trim().isEmpty
              ? null
              : _contextController.text.trim(),
          extraTerms: _termsController.text
              .split(',')
              .map((t) => t.trim())
              .where((t) => t.isNotEmpty)
              .toList(),
        );
    ref.read(activeMeetingIdProvider.notifier).set(meeting.id);
    if (!context.mounted) return;
    Navigator.of(context).pop();
    context.push(AppRoutes.liveMeeting(meeting.id));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: tokens.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Start listening', style: textTheme.headlineSmall),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Meeting title (optional)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _contextController,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Context note (optional)',
                hintText:
                    'e.g. Churn model v2 review, stakeholders from marketing',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _termsController,
              decoration: const InputDecoration(
                labelText: 'Extra terms (optional)',
                hintText: 'Project names, acronyms: comma-separated',
              ),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 18, color: tokens.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Let the other participants know this meeting is being recorded.',
                    style: textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _starting ? null : _start,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text('Start'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
