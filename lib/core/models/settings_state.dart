enum AudioRetention { deleteImmediately, keep7Days, keepIndefinitely }

/// Model used for the accurate re-transcription after Stop (brief §3,
/// phase 4). Flagship target, so small.en is the default.
enum FinalPassModel { whisperSmallEn, whisperBaseEn, off }

const kAnalysisModels = ['claude-sonnet-5-5', 'claude-opus-5-5'];

const kDefaultDocDomains = ['learn.microsoft.com', 'docs.databricks.com'];

const kStarterVocabulary = [
  'Databricks',
  'Unity Catalog',
  'Delta Lake',
  'Delta Live Tables',
  'Lakeflow',
  'Auto Loader',
  'MLflow',
  'Spark',
  'PySpark',
  'dbt',
  'Azure Data Factory',
  'Synapse',
  'Fabric',
  'ADLS',
  'Key Vault',
  'AKS',
  'XGBoost',
  'LightGBM',
  'scikit-learn',
  'PyTorch',
  'LLM',
  'RAG',
  'embeddings',
  'feature store',
  'CI/CD',
];

class SettingsState {
  const SettingsState({
    this.hasApiKey = false,
    this.analysisModel = 'claude-sonnet-5-5',
    this.finalPassModel = FinalPassModel.whisperSmallEn,
    this.globalContextNote = '',
    this.audioRetention = AudioRetention.deleteImmediately,
    this.boostStrength = 1.5,
    this.customVocabulary = kStarterVocabulary,
    this.checkDocsDefault = true,
    this.docDomains = kDefaultDocDomains,
    this.maxDocLookups = 5,
    this.workspaceId = '',
  });

  /// Mirrors whether a key exists in secure storage; never persisted here.
  final bool hasApiKey;
  final String analysisModel;
  final FinalPassModel finalPassModel;
  final String globalContextNote;
  final AudioRetention audioRetention;

  /// Hotword boost for the live recogniser; 0 disables contextual biasing.
  final double boostStrength;
  final List<String> customVocabulary;
  final bool checkDocsDefault;
  final List<String> docDomains;
  final int maxDocLookups;

  /// Sent as `anthropic-workspace-id`. Required for API keys that aren't
  /// bound to a single workspace; empty for workspace-scoped keys.
  final String workspaceId;

  SettingsState copyWith({
    bool? hasApiKey,
    String? analysisModel,
    FinalPassModel? finalPassModel,
    String? globalContextNote,
    AudioRetention? audioRetention,
    double? boostStrength,
    List<String>? customVocabulary,
    bool? checkDocsDefault,
    List<String>? docDomains,
    int? maxDocLookups,
    String? workspaceId,
  }) {
    return SettingsState(
      hasApiKey: hasApiKey ?? this.hasApiKey,
      analysisModel: analysisModel ?? this.analysisModel,
      finalPassModel: finalPassModel ?? this.finalPassModel,
      globalContextNote: globalContextNote ?? this.globalContextNote,
      audioRetention: audioRetention ?? this.audioRetention,
      boostStrength: boostStrength ?? this.boostStrength,
      customVocabulary: customVocabulary ?? this.customVocabulary,
      checkDocsDefault: checkDocsDefault ?? this.checkDocsDefault,
      docDomains: docDomains ?? this.docDomains,
      maxDocLookups: maxDocLookups ?? this.maxDocLookups,
      workspaceId: workspaceId ?? this.workspaceId,
    );
  }

  Map<String, dynamic> toJson() => {
    'analysisModel': analysisModel,
    'finalPassModel': finalPassModel.name,
    'globalContextNote': globalContextNote,
    'audioRetention': audioRetention.name,
    'boostStrength': boostStrength,
    'customVocabulary': customVocabulary,
    'checkDocsDefault': checkDocsDefault,
    'docDomains': docDomains,
    'maxDocLookups': maxDocLookups,
    'workspaceId': workspaceId,
  };

  /// Tolerant of missing/unknown keys so older saved settings still load.
  factory SettingsState.fromJson(Map<String, dynamic> json) {
    const defaults = SettingsState();
    T byName<T extends Enum>(List<T> values, Object? name, T fallback) {
      for (final v in values) {
        if (v.name == name) return v;
      }
      return fallback;
    }

    final model = json['analysisModel'];
    return SettingsState(
      analysisModel: model is String && kAnalysisModels.contains(model)
          ? model
          : defaults.analysisModel,
      finalPassModel: byName(
        FinalPassModel.values,
        json['finalPassModel'],
        defaults.finalPassModel,
      ),
      globalContextNote:
          json['globalContextNote'] as String? ?? defaults.globalContextNote,
      audioRetention: byName(
        AudioRetention.values,
        json['audioRetention'],
        defaults.audioRetention,
      ),
      boostStrength:
          (json['boostStrength'] as num?)?.toDouble() ?? defaults.boostStrength,
      customVocabulary:
          (json['customVocabulary'] as List<dynamic>?)?.cast<String>() ??
          defaults.customVocabulary,
      checkDocsDefault:
          json['checkDocsDefault'] as bool? ?? defaults.checkDocsDefault,
      docDomains:
          (json['docDomains'] as List<dynamic>?)?.cast<String>() ??
          defaults.docDomains,
      maxDocLookups:
          (json['maxDocLookups'] as num?)?.toInt() ?? defaults.maxDocLookups,
      workspaceId: json['workspaceId'] as String? ?? defaults.workspaceId,
    );
  }
}
