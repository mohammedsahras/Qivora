/// Qivora app-wide constants.
///
/// Kept here so the version shown in Settings/About stays in sync with
/// pubspec.yaml.
class QivoraConstants {
  QivoraConstants._();

  static const appName = 'Qivora';
  static const appVersion = '1.0.0';
  static const tagline = 'Connect Beyond Messages';

  /// Local-only note shown for controls whose effect is limited to this
  /// device until a real messaging backend is connected.
  static const localOnlyNote =
      'Stored locally on this device. Cross-device enforcement requires a '
      'messaging backend (signaling server) which is not configured in this build.';
}
