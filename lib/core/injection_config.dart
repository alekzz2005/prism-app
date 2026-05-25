/// Stores the target angle and tolerance for each injection type.
/// This is in-memory only — never persisted to Firestore.
class InjectionConfig {
  final String type; // "IM"
  final double targetAngle;
  final double tolerance;

  const InjectionConfig({
    required this.type,
    required this.targetAngle,
    required this.tolerance,
  });
}

/// Returns the [InjectionConfig] for a given injection type string.
class InjectionConfigService {
  static const _configs = {
    'IM': InjectionConfig(type: 'IM', targetAngle: 90.0, tolerance: 5.0),
  };

  /// Returns the config for [type], or throws if unknown.
  static InjectionConfig getConfig(String type) {
    final config = _configs[type];
    if (config == null) throw ArgumentError('Unknown injection type: $type');
    return config;
  }

  /// All supported injection types.
  static List<String> get allTypes => _configs.keys.toList();
}
