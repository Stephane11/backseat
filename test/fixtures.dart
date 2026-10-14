import 'package:backseat/core/models/analysis.dart';
import 'package:backseat/core/models/meeting.dart';
import 'package:backseat/core/models/segment.dart';

/// Hand-written fixture data so every screen can be built and widget-tested
/// before real recording/storage/Claude integration exist (phases 2-3).
List<Meeting> buildFixtureMeetings() {
  final now = DateTime.now();

  final churnSegments = <Segment>[
    for (final (i, line) in _churnLines.indexed)
      Segment(
        id: 'churn-seg-$i',
        start: Duration(seconds: i * 9),
        end: Duration(seconds: i * 9 + 8),
        text: line,
        isFinal: true,
      ),
  ];

  final churnAnalysis = Analysis(
    id: 'churn-analysis-1',
    createdAt: now.subtract(const Duration(days: 1, hours: 2)),
    model: 'claude-sonnet-5-5',
    transcriptUpTo: churnSegments.last.end,
    summary: _churnSummary,
    items: _churnAnalysisItems,
  );

  final churn = Meeting(
    id: 'meeting-churn',
    title: 'Churn model v2 review',
    contextNote: 'Churn model v2 review, stakeholders from marketing',
    startedAt: now.subtract(const Duration(days: 1, hours: 2, minutes: 15)),
    endedAt: now.subtract(const Duration(days: 1, hours: 1, minutes: 45)),
    transcriptSource: TranscriptSource.finalPass,
    segments: churnSegments,
    analyses: [churnAnalysis],
  );

  final syncSegments = <Segment>[
    for (final (i, line) in _syncLines.indexed)
      Segment(
        id: 'sync-seg-$i',
        start: Duration(seconds: i * 7),
        end: Duration(seconds: i * 7 + 6),
        text: line,
        isFinal: true,
      ),
  ];

  final sync = Meeting(
    id: 'meeting-sync',
    title: 'Weekly data platform sync',
    startedAt: now.subtract(const Duration(days: 3, hours: 5)),
    endedAt: now.subtract(const Duration(days: 3, hours: 4, minutes: 40)),
    transcriptSource: TranscriptSource.finalPass,
    segments: syncSegments,
    analyses: [
      Analysis(
        id: 'sync-analysis-1',
        createdAt: now.subtract(const Duration(days: 3, hours: 4, minutes: 39)),
        model: 'claude-sonnet-5-5',
        transcriptUpTo: syncSegments.last.end,
        summary:
            'Quick sync on Auto Loader ingestion costs and the upcoming Unity Catalog '
            'permissions cleanup.',
        items: const [
          AnalysisItem(
            type: ItemType.idea,
            category: ItemCategory.dataEngineering,
            severity: Severity.low,
            title: 'Batch Auto Loader triggers to cut small-file overhead',
            detail:
                'Switching from continuous to a scheduled trigger interval would reduce the '
                'small-file problem mentioned, at the cost of slightly higher latency.',
            evidence: 'we are getting a lot of small files from the streaming ingestion',
            timestamp: Duration(seconds: 51),
          ),
        ],
      ),
    ],
  );

  final kickoff = Meeting(
    id: 'meeting-kickoff',
    title: 'RAG eval kickoff',
    startedAt: now.subtract(const Duration(hours: 6)),
    endedAt: now.subtract(const Duration(hours: 5, minutes: 50)),
    transcriptSource: TranscriptSource.finalPass,
    segments: const [
      Segment(
        id: 'kickoff-seg-0',
        start: Duration.zero,
        end: Duration(seconds: 8),
        text: "Let's figure out how we evaluate the new RAG pipeline before it goes to review.",
        isFinal: true,
      ),
    ],
    analyses: const [],
  );

  return [kickoff, churn, sync];
}

const _churnLines = [
  "Okay so let's get started, thanks everyone for joining the churn model review.",
  'So the current approach is a gradient boosted tree trained on the last ninety days of usage data.',
  "We're using accuracy as the main metric right now, it's around eighty nine percent on the holdout set.",
  'Right, but the holdout set is a random split, not a time based split, so there might be some leakage from future behaviour into the training window.',
  "That's a fair point, we haven't checked for that specifically.",
  'The other thing is churn is pretty rare in this population, so accuracy might not be the most informative metric, we should probably look at something like precision recall or lift.',
  'Marketing wants a single number they can put on a dashboard though.',
  'We can still give them a single number, just a more appropriate one, like area under the precision recall curve, and then translate that into expected revenue saved for the dashboard.',
  "Good idea, let's note that down.",
  'For features we are using account age, number of logins last thirty days, support tickets opened, and plan tier.',
  'Are we pulling any of that from the new Delta Live Tables pipeline or still the old batch job?',
  'Still the old batch job for now, the DLT migration is planned for next quarter.',
  'Okay, worth flagging that the two pipelines might disagree on definitions, so if the handoff happens mid quarter the feature distributions could shift under the model without anyone noticing.',
  'Also are we monitoring for drift at all right now?',
  'No, nothing automated yet, we just look at the numbers manually every couple of weeks.',
  'We should probably set up a simple drift check on the input feature distributions and on the prediction distribution before this goes to more stakeholders.',
  'On the deployment side, how is this actually going to be served, is it batch scored or an online endpoint?',
  "Batch scored nightly into a table that the marketing team's tool reads from.",
  "That simplifies a lot of things actually, means we don't need to worry about latency, just freshness and making sure the nightly job has alerting if it fails silently.",
  'Should we also think about a simpler baseline, like a rules based heuristic on login recency, just to sanity check the model is actually adding value over something trivial?',
  "Yeah that's worth doing before we present results, otherwise it's hard to know if eighty nine percent accuracy is actually impressive or just reflects the class imbalance.",
  "Let's also make sure we've got an owner for this once it ships, and a rough timeline for the DLT migration so we know when the features might change under us.",
  "Good, I'll write that up, anything else before we wrap?",
  "Just one thing, let's double check PII handling on the support ticket text field, since we might be pulling in free text that hasn't been scrubbed.",
  "Noted, I'll follow up with the data engineering team on that separately.",
];

const _syncLines = [
  "Quick one today, let's cover Auto Loader costs and the Unity Catalog cleanup.",
  'We are getting a lot of small files from the streaming ingestion, driving up list costs.',
  'We could batch the trigger interval instead of running it continuously.',
  'Good, and on Unity Catalog, we still have a few legacy grants to clean up before the audit.',
  "I'll put together a list and we can review next week.",
];

const _churnSummary =
    'Review of the churn model v2 approach: a gradient boosted tree on 90 days of '
    'usage data, evaluated on accuracy, batch-scored nightly for the marketing dashboard.';

const _churnAnalysisItems = [
  AnalysisItem(
    type: ItemType.issue,
    category: ItemCategory.statistics,
    severity: Severity.high,
    title: 'Random split may leak future behaviour',
    detail:
        'The holdout is a random split rather than time-based, so features from after '
        'the prediction point could leak into training. Worth confirming the split is '
        'strictly time-ordered before trusting the accuracy number.',
    evidence: 'the holdout set is a random split, not a time based split',
    timestamp: Duration(seconds: 27),
  ),
  AnalysisItem(
    type: ItemType.suggestion,
    category: ItemCategory.statistics,
    severity: Severity.medium,
    title: 'Accuracy is misleading under class imbalance',
    detail:
        'Churn is rare, so accuracy will look high almost regardless of model quality. '
        'PR-AUC (already raised in the meeting) plus a translation into expected revenue '
        'saved is a better pair of numbers for both the team and the dashboard.',
    evidence: 'accuracy might not be the most informative metric',
    timestamp: Duration(seconds: 45),
  ),
  AnalysisItem(
    type: ItemType.issue,
    category: ItemCategory.dataEngineering,
    severity: Severity.medium,
    title: 'Feature drift risk at the DLT migration handoff',
    detail:
        'Two pipelines (old batch job, new DLT) may define features differently. If the '
        'cutover lands mid-quarter, input distributions could shift under the model with '
        'no alerting in place, since there is no monitoring today.',
    evidence: 'the two pipelines might disagree on definitions',
    timestamp: Duration(seconds: 108),
  ),
  AnalysisItem(
    type: ItemType.question,
    category: ItemCategory.delivery,
    severity: Severity.low,
    title: 'Who owns the model after it ships?',
    detail:
        'Worth nailing down an owner and a rough DLT migration timeline before launch, so '
        'it is clear who reacts if the nightly job fails or the features change.',
    evidence: "let's also make sure we've got an owner for this once it ships",
    timestamp: Duration(seconds: 207),
  ),
  AnalysisItem(
    type: ItemType.idea,
    category: ItemCategory.ml,
    severity: Severity.medium,
    title: 'Add a login-recency baseline before presenting',
    detail:
        'A trivial rules-based heuristic on login recency would make it possible to tell '
        'whether 89% accuracy is genuinely adding value or just reflecting the class '
        'imbalance. Cheap to build, strengthens the readout either way.',
    evidence:
        'a simpler baseline, like a rules based heuristic on login recency',
    timestamp: Duration(seconds: 189),
  ),
  AnalysisItem(
    type: ItemType.issue,
    category: ItemCategory.delivery,
    severity: Severity.medium,
    title: 'Support-ticket free text may contain unscrubbed PII',
    detail:
        'The feature set pulls from a free-text support ticket field; worth checking with '
        'data engineering whether that text is scrubbed before it reaches this pipeline.',
    evidence:
        "let's double check PII handling on the support ticket text field",
    timestamp: Duration(seconds: 243),
  ),
];

/// Stand-in for the real Claude call (phase 3): surfaces whichever canned
/// churn-review items whose evidence has actually appeared in the transcript
/// so far, so repeated taps of Analyse on the live fake transcript feel like
/// they are reacting to what's been "said".
Analysis buildMockAnalysis({
  required List<Segment> finalSegments,
  required String model,
}) {
  final transcriptSoFar = finalSegments
      .map((s) => s.text)
      .join(' ')
      .toLowerCase();
  final matched = _churnAnalysisItems
      .where((item) => transcriptSoFar.contains(item.evidence.toLowerCase()))
      .toList();

  return Analysis(
    id: 'analysis-${DateTime.now().microsecondsSinceEpoch}',
    createdAt: DateTime.now(),
    model: model,
    transcriptUpTo: finalSegments.isEmpty
        ? Duration.zero
        : finalSegments.last.end,
    summary: matched.isEmpty
        ? 'Not enough signal yet — keep the meeting going and analyse again shortly.'
        : _churnSummary,
    items: matched,
  );
}
