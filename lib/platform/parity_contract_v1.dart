/// Shared observability feature-parity contract with
/// `ores-otel/ores-otel-desktop-app.rs`. Native notification, filesystem,
/// lifecycle, and secure-storage behavior belongs only in [AppPlatformAdapter].
const int crossPlatformParityContractVersion = 1;
const String rustDesktopCounterpart = 'ores-otel/ores-otel-desktop-app.rs';
enum AppSurface { mobile, flutterDesktop, rustDesktop }
enum AppCapability {
  authentication, traces, metrics, logs, liveTail, dashboards, filters,
  savedViews, alertInbox, notifications, fileExport, offlineCache,
  backgroundSync, redactionControls, telemetry, accessibility,
  applicationUpdates,
}
const Set<AppCapability> requiredParityCapabilities = <AppCapability>{
  AppCapability.authentication, AppCapability.traces, AppCapability.metrics,
  AppCapability.logs, AppCapability.liveTail, AppCapability.dashboards,
  AppCapability.filters, AppCapability.savedViews, AppCapability.alertInbox,
  AppCapability.notifications, AppCapability.fileExport,
  AppCapability.offlineCache, AppCapability.backgroundSync,
  AppCapability.redactionControls, AppCapability.telemetry,
  AppCapability.accessibility, AppCapability.applicationUpdates,
};
abstract class AppPlatformAdapter {
  const AppPlatformAdapter();
  AppSurface get surface;
  bool supports(AppCapability capability);
}
void verifyRequiredParityCapabilities(AppPlatformAdapter adapter) {
  final missing = requiredParityCapabilities
      .where((capability) => !adapter.supports(capability)).toList();
  if (missing.isNotEmpty) {
    throw StateError('Observability parity gate failed for ${adapter.surface}: $missing');
  }
}
