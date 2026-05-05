class EngineKindOption {
  final String value;
  final String label;
  final String suggestedLabel;

  const EngineKindOption({
    required this.value,
    required this.label,
    required this.suggestedLabel,
  });
}

const List<EngineKindOption> kEngineKindOptions = [
  EngineKindOption(
    value: 'main',
    label: 'Main',
    suggestedLabel: 'Main Engine',
  ),
  EngineKindOption(
    value: 'port',
    label: 'Port',
    suggestedLabel: 'Port Engine',
  ),
  EngineKindOption(
    value: 'starboard',
    label: 'Starboard',
    suggestedLabel: 'Starboard Engine',
  ),
  EngineKindOption(
    value: 'wing',
    label: 'Wing',
    suggestedLabel: 'Wing Engine',
  ),
  EngineKindOption(
    value: 'generator',
    label: 'Generator',
    suggestedLabel: 'Generator',
  ),
  EngineKindOption(
    value: 'auxiliary',
    label: 'Auxiliary',
    suggestedLabel: 'Auxiliary Engine',
  ),
];

String normalizeEngineKind(String? kind) {
  switch (kind?.trim().toLowerCase()) {
    case 'engine':
    case 'main_engine':
    case 'main engine':
      return 'main';
    case 'gen':
    case 'generator':
      return 'generator';
    case 'aux':
    case 'aux_engine':
    case 'aux engine':
      return 'auxiliary';
    case 'port':
      return 'port';
    case 'starboard':
      return 'starboard';
    case 'wing':
      return 'wing';
    case 'auxiliary':
      return 'auxiliary';
    case 'main':
      return 'main';
    default:
      return 'main';
  }
}

EngineKindOption engineKindOptionFor(String? kind) {
  final normalized = normalizeEngineKind(kind);
  return kEngineKindOptions.firstWhere(
    (option) => option.value == normalized,
    orElse: () => const EngineKindOption(
      value: 'main',
      label: 'Main',
      suggestedLabel: 'Main Engine',
    ),
  );
}

String engineKindLabel(String? kind) => engineKindOptionFor(kind).label;

String suggestedEngineLabel(String? kind) =>
    engineKindOptionFor(kind).suggestedLabel;
