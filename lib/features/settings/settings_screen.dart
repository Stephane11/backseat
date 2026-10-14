import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/models/settings_state.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/app_color_tokens.dart';
import '../recording/model_download_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _apiKeyController = TextEditingController();
  final _vocabController = TextEditingController();
  final _domainController = TextEditingController();
  late final TextEditingController _workspaceController;
  late final TextEditingController _contextController;
  bool _savingKey = false;

  @override
  void initState() {
    super.initState();
    _contextController = TextEditingController(
      text: ref.read(settingsProvider).globalContextNote,
    );
    _workspaceController = TextEditingController(
      text: ref.read(settingsProvider).workspaceId,
    );
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _vocabController.dispose();
    _domainController.dispose();
    _workspaceController.dispose();
    _contextController.dispose();
    super.dispose();
  }

  void _snack(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  Future<void> _saveKey() async {
    final key = _apiKeyController.text.trim();
    if (key.isEmpty) return;
    if (!key.startsWith('sk-ant-')) {
      _snack(
        'That doesn\'t look like a Claude API key (they start with "sk-ant-").',
      );
      return;
    }
    setState(() => _savingKey = true);
    try {
      await ref.read(settingsProvider.notifier).saveApiKey(key);
      _apiKeyController.clear();
      if (mounted) _snack('API key saved securely on this device');
    } catch (_) {
      if (mounted) _snack("Couldn't save the key to secure storage");
    } finally {
      if (mounted) setState(() => _savingKey = false);
    }
  }

  Future<void> _removeKey() async {
    await ref.read(settingsProvider.notifier).clearApiKey();
    if (mounted) _snack('API key removed');
  }

  void _addTerm() {
    ref
        .read(settingsProvider.notifier)
        .addVocabularyTerm(_vocabController.text);
    _vocabController.clear();
  }

  void _addDomain() {
    final before = ref.read(settingsProvider).docDomains.length;
    ref.read(settingsProvider.notifier).addDocDomain(_domainController.text);
    if (ref.read(settingsProvider).docDomains.length == before &&
        _domainController.text.trim().isNotEmpty) {
      _snack('Enter a domain like docs.getdbt.com');
      return;
    }
    _domainController.clear();
  }

  Future<void> _importVocabulary() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt'],
    );
    if (files.isEmpty) return;
    final text = utf8.decode(
      await files.first.readAsBytes(),
      allowMalformed: true,
    );
    final notifier = ref.read(settingsProvider.notifier);
    final before = ref.read(settingsProvider).customVocabulary.length;
    for (final line in const LineSplitter().convert(text)) {
      notifier.addVocabularyTerm(line);
    }
    final added = ref.read(settingsProvider).customVocabulary.length - before;
    if (mounted) _snack('Imported $added new term${added == 1 ? '' : 's'}');
  }

  Future<void> _exportVocabulary() async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'backseat-vocabulary.txt'));
    await file.writeAsString(
      '${ref.read(settingsProvider).customVocabulary.join('\n')}\n',
    );
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path, mimeType: 'text/plain')]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final themeMode = ref.watch(themeModeProvider);
    final hint = textTheme.bodySmall?.copyWith(color: tokens.textSecondary);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          const _SectionHeader('Claude API'),
          if (settings.hasApiKey)
            Row(
              children: [
                Icon(Icons.check_circle, size: 18, color: tokens.severityLow),
                const SizedBox(width: 8),
                const Expanded(child: Text('API key saved on this device')),
                TextButton(onPressed: _removeKey, child: const Text('Remove')),
              ],
            ),
          TextField(
            controller: _apiKeyController,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: settings.hasApiKey ? 'Replace API key' : 'API key',
              hintText: 'sk-ant-...',
              suffixIcon: _savingKey
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      icon: const Icon(Icons.check),
                      tooltip: 'Save',
                      onPressed: _saveKey,
                    ),
            ),
            onSubmitted: (_) => _saveKey(),
          ),
          const SizedBox(height: 4),
          Text(
            'Stored encrypted with the Android Keystore. Get a key at '
            'console.anthropic.com.',
            style: hint,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _workspaceController,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'Workspace ID (optional)',
              hintText: 'wrkspc_...',
            ),
            onChanged: notifier.setWorkspaceId,
          ),
          const SizedBox(height: 4),
          Text(
            "Only needed if your key isn't tied to one workspace (the API "
            'then asks for a workspace ID). Find it in the Claude Console '
            'under Settings → Workspaces.',
            style: hint,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: settings.analysisModel,
            decoration: const InputDecoration(labelText: 'Analysis model'),
            items: const [
              DropdownMenuItem(
                value: 'claude-sonnet-5-5',
                child: Text('claude-sonnet-5-5 (faster)'),
              ),
              DropdownMenuItem(
                value: 'claude-opus-5-5',
                child: Text('claude-opus-5-5 (deeper)'),
              ),
            ],
            onChanged: (value) =>
                value == null ? null : notifier.setAnalysisModel(value),
          ),
          const SizedBox(height: 24),
          const _SectionHeader('Documentation lookups'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Check against docs by default'),
            subtitle: Text(
              'Claude searches the approved sites below during analysis. '
              'Slower (30–60 s) and adds a per-search fee.',
              style: hint,
            ),
            value: settings.checkDocsDefault,
            onChanged: notifier.setCheckDocsDefault,
          ),
          Text(
            'Max lookups per analysis: ${settings.maxDocLookups}',
            style: hint,
          ),
          Slider(
            value: settings.maxDocLookups.toDouble(),
            min: 1,
            max: 10,
            divisions: 9,
            label: '${settings.maxDocLookups}',
            onChanged: (v) => notifier.setMaxDocLookups(v.round()),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final domain in settings.docDomains)
                InputChip(
                  label: Text(domain),
                  onDeleted: settings.docDomains.length > 1
                      ? () => notifier.removeDocDomain(domain)
                      : null,
                ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _domainController,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Add approved domain',
                  ),
                  onSubmitted: (_) => _addDomain(),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: _addDomain,
              ),
            ],
          ),
          const SizedBox(height: 24),
          const _SectionHeader('Transcription'),
          const _ModelTile(
            id: AsrModelId.streamingZipformerEn,
            role: 'Live transcription (required)',
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<FinalPassModel>(
            initialValue: settings.finalPassModel,
            decoration: const InputDecoration(
              labelText: 'Accurate final pass after Stop',
            ),
            items: [
              DropdownMenuItem(
                value: FinalPassModel.whisperSmallEn,
                child: Text(
                  'Whisper small.en · most accurate · '
                  '${kAsrModels[AsrModelId.whisperSmallEn]!.sizeLabel}',
                ),
              ),
              DropdownMenuItem(
                value: FinalPassModel.whisperBaseEn,
                child: Text(
                  'Whisper base.en · faster · '
                  '${kAsrModels[AsrModelId.whisperBaseEn]!.sizeLabel}',
                ),
              ),
              const DropdownMenuItem(
                value: FinalPassModel.off,
                child: Text('Off (keep the live transcript)'),
              ),
            ],
            onChanged: (value) =>
                value == null ? null : notifier.setFinalPassModel(value),
          ),
          if (finalPassModelId(settings.finalPassModel) case final id?) ...[
            const SizedBox(height: 8),
            _ModelTile(id: id, role: 'Final pass'),
          ],
          const SizedBox(height: 24),
          const _SectionHeader('Context'),
          TextField(
            controller: _contextController,
            maxLines: 4,
            minLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'About me / my projects',
              hintText:
                  'Sent with every analysis, alongside any per-meeting note.',
            ),
            onChanged: notifier.setGlobalContextNote,
          ),
          const SizedBox(height: 24),
          const _SectionHeader('Custom vocabulary'),
          Text(
            settings.boostStrength == 0
                ? 'Recognition boost: off (terms still sent to Claude)'
                : 'Recognition boost: ${settings.boostStrength.toStringAsFixed(1)}',
            style: hint,
          ),
          Slider(
            value: settings.boostStrength,
            min: 0,
            max: 3,
            divisions: 12,
            label: settings.boostStrength.toStringAsFixed(1),
            onChanged: notifier.setBoostStrength,
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _vocabController,
                  decoration: const InputDecoration(labelText: 'Add term'),
                  onSubmitted: (_) => _addTerm(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: _addTerm,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final term in settings.customVocabulary)
                InputChip(
                  label: Text(term),
                  onDeleted: () => notifier.removeVocabularyTerm(term),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            children: [
              TextButton.icon(
                onPressed: _importVocabulary,
                icon: const Icon(Icons.file_download_outlined),
                label: const Text('Import .txt'),
              ),
              TextButton.icon(
                onPressed: _exportVocabulary,
                icon: const Icon(Icons.file_upload_outlined),
                label: const Text('Export'),
              ),
              TextButton.icon(
                onPressed: () => notifier.replaceVocabulary(kStarterVocabulary),
                icon: const Icon(Icons.restart_alt),
                label: const Text('Reset to starter list'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const _SectionHeader('Privacy'),
          DropdownButtonFormField<AudioRetention>(
            initialValue: settings.audioRetention,
            decoration: const InputDecoration(labelText: 'Keep recorded audio'),
            items: const [
              DropdownMenuItem(
                value: AudioRetention.deleteImmediately,
                child: Text('Delete immediately after final transcript'),
              ),
              DropdownMenuItem(
                value: AudioRetention.keep7Days,
                child: Text('Keep 7 days'),
              ),
              DropdownMenuItem(
                value: AudioRetention.keepIndefinitely,
                child: Text('Keep indefinitely'),
              ),
            ],
            onChanged: (value) =>
                value == null ? null : notifier.setAudioRetention(value),
          ),
          const SizedBox(height: 6),
          Text(
            'Audio never leaves the phone. Only transcript text is sent to '
            "Anthropic's API, and only when you tap Analyse.",
            style: hint,
          ),
          const SizedBox(height: 24),
          const _SectionHeader('Appearance'),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
              ButtonSegment(value: ThemeMode.light, label: Text('Light')),
              ButtonSegment(value: ThemeMode.system, label: Text('System')),
            ],
            selected: {themeMode},
            onSelectionChanged: (value) =>
                ref.read(themeModeProvider.notifier).setMode(value.first),
          ),
        ],
      ),
    );
  }
}

/// Download state and action for one on-device model.
class _ModelTile extends ConsumerWidget {
  const _ModelTile({required this.id, required this.role});

  final AsrModelId id;
  final String role;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final spec = kAsrModels[id]!;
    final state =
        ref.watch(modelDownloadsProvider)[id] ??
        const ModelDownloadState(ModelStatus.unknown);
    final downloads = ref.read(modelDownloadsProvider.notifier);

    final (String status, Widget? action) = switch (state.status) {
      ModelStatus.unknown => ('Checking…', null),
      ModelStatus.missing => (
        'Not downloaded · ${spec.sizeLabel}',
        TextButton(
          onPressed: () => downloads.download(id),
          child: const Text('Download'),
        ),
      ),
      ModelStatus.downloading => (
        'Downloading… ${(state.progress * 100).round()}%',
        null,
      ),
      ModelStatus.ready => (
        'Ready',
        Icon(Icons.check_circle, size: 18, color: tokens.severityLow),
      ),
      ModelStatus.error => (
        state.error ?? 'Download failed',
        TextButton(
          onPressed: () => downloads.download(id),
          child: const Text('Retry'),
        ),
      ),
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(spec.displayName, style: textTheme.titleSmall),
                    Text(
                      '$role · $status',
                      style: textTheme.bodySmall?.copyWith(
                        color: state.status == ModelStatus.error
                            ? tokens.severityHigh
                            : tokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              ?action,
            ],
          ),
          if (state.status == ModelStatus.downloading) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: state.progress, minHeight: 4),
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}
