# Batch 4 — Telemetry Dashboard + Alerts + Owner View + Tier Gate Wiring

## Context
Flutter app at `/home/garrett/.openclaw/workspace/vortice-app`. Uses Supabase, Riverpod, Freezed, GoRouter, l10n (EN + ES).

**CRITICAL:** Dart/Flutter is NOT installed on this machine. Do NOT run `dart run build_runner` or `flutter build`. Just write correct code.

Read existing code before changing anything. Follow existing patterns exactly.

## Task List

### 1. Create TelemetryReading model

Check if `lib/models/telemetry_reading.dart` exists. If not, create a Freezed model:
```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'telemetry_reading.freezed.dart';
part 'telemetry_reading.g.dart';

@freezed
class TelemetryReading with _$TelemetryReading {
  const factory TelemetryReading({
    required String id,
    @JsonKey(name: 'engine_id') required String engineId,
    @JsonKey(name: 'ts') required DateTime timestamp,
    double? rpm,
    @JsonKey(name: 'coolant_temp') double? coolantTemp,
    @JsonKey(name: 'oil_pressure') double? oilPressure,
    @JsonKey(name: 'battery_v') double? batteryV,
    @JsonKey(name: 'boost_psi') double? boostPsi,
    @JsonKey(name: 'throttle_pct') double? throttlePct,
    @JsonKey(name: 'fuel_rate') double? fuelRate,
    @JsonKey(name: 'torque_pct') double? torquePct,
  }) = _TelemetryReading;

  factory TelemetryReading.fromJson(Map<String, dynamic> json) =>
      _$TelemetryReadingFromJson(json);
}
```

### 2. Create TelemetryAlert model

Check if `lib/models/telemetry_alert.dart` exists. If not, create a Freezed model:
```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'telemetry_alert.freezed.dart';
part 'telemetry_alert.g.dart';

@freezed
class TelemetryAlert with _$TelemetryAlert {
  const factory TelemetryAlert({
    required String id,
    @JsonKey(name: 'engine_id') required String engineId,
    @JsonKey(name: 'alert_type') required String alertType,
    int? spn,
    int? fmi,
    double? value,
    double? threshold,
    @JsonKey(name: 'alert_source') @Default('system') String alertSource, // 'system' or 'predictive'
    String? severity, // 'warning', 'critical'
    String? message, // Human-readable alert text
    @JsonKey(defaultValue: false) bool acknowledged,
    @JsonKey(name: 'acknowledged_at') DateTime? acknowledgedAt,
    @JsonKey(name: 'acknowledged_by') String? acknowledgedBy,
    @JsonKey(name: 'created_at') DateTime? createdAt,
  }) = _TelemetryAlert;

  factory TelemetryAlert.fromJson(Map<String, dynamic> json) =>
      _$TelemetryAlertFromJson(json);
}
```

### 3. Create Telemetry providers

Create `lib/features/telemetry/telemetry_provider.dart`:

- `latestReadingProvider(String engineId)` — FutureProvider.family that fetches the most recent reading from `telemetry_readings` for a given engine, ordered by `ts` desc, limit 1
- `readingsHistoryProvider({engineId, hours})` — fetches readings for the last N hours for an engine
- `activeAlertsProvider` — FutureProvider that fetches all unacknowledged alerts from `telemetry_alerts` where `acknowledged = false`, joined with engine → asset → client info
- `alertsForAssetProvider(String assetId)` — FutureProvider.family fetching alerts for all engines on an asset
- `fleetHealthProvider(String? orgId)` — fetches summary data: vessel count, active alert count, upcoming service count. If orgId is null (owner), fetch across all. If orgId provided, scope to org.
- `TelemetryController` — StateNotifier with:
  - `acknowledgeAlert(String alertId)` — sets acknowledged = true, acknowledged_at = now, acknowledged_by = current user
  - `refreshReading(String engineId)` — re-fetches latest reading (invalidates provider)

### 4. Create Telemetry Client Dashboard

Create `lib/features/dashboard/client_dashboard_telemetry.dart`:

This is what Telemetry tier (T3) clients see. It's their primary dashboard.

**Layout (scrollable column):**

1. **Fleet Health Bar** (top):
   - Single row card with large text:
   - "[X] vessels · [Y] active alerts · [Z] services upcoming"
   - Use `fleetHealthProvider` with the client's org_id
   - Color-coded: green if 0 alerts, yellow if warnings, red if critical alerts

2. **Active Alerts Card:**
   - Header: "Active Alerts"
   - List of unacknowledged alerts:
     - Vessel name (from engine → asset join)
     - Alert type (e.g., "High Coolant Temp", "Low Oil Pressure")
     - Severity indicator (red/yellow dot)
     - Value + threshold (e.g., "98°C / threshold: 95°C")
     - Timestamp
   - Tap → navigates to vessel telemetry detail
   - Empty state: green card with checkmark — "All vessels nominal"

3. **Fleet Grid:**
   - Header: "Fleet"
   - Grid of cards (2 columns), one per vessel:
     - Asset name
     - Asset type icon (reuse existing icon mapping)
     - Status dot: green (no alerts), yellow (warnings), red (critical)
     - Last reading timestamp
   - Tap → vessel telemetry detail screen

4. **Upcoming Maintenance:**
   - Header: "Upcoming Maintenance"
   - Simple list: asset name, interval description, hours remaining
   - Uses service_reminders or asset_service_intervals data
   - Empty state: "No upcoming maintenance"

5. **Open Invoices:**
   - Same as other dashboards — invoice list with status

### 5. Create Vessel Telemetry Detail Screen

Create `lib/features/telemetry/vessel_telemetry_screen.dart`:

Shows live telemetry data for a single vessel/asset.

**AppBar:** Asset name as title, with a refresh button

**Takes parameter:** `assetId`

**Layout:**

1. **Engine selector** (if multi-engine):
   - Fetch engines for this asset from `asset_engines`
   - If multiple engines, show a horizontal chip selector
   - Default to first engine

2. **Live Gauges section:**
   - Header: "Live Data" with "Last updated: [timestamp]" subtitle
   - Grid of gauge cards (2 columns):
     - RPM: value + label
     - Coolant Temp: value + "°C" + color (green < 85, yellow 85-95, red > 95)
     - Oil Pressure: value + "PSI" + color
     - Fuel Rate: value + "L/hr"
     - Battery: value + "V" + color (green > 12.4, yellow 12-12.4, red < 12)
     - Boost PSI: value
   - Each gauge card: large number, label, unit, colored indicator
   - If no readings: "Waiting for data..."

3. **Fault Codes** (if any alerts):
   - Header: "Fault Codes"
   - List of active alerts for this engine
   - SPN/FMI codes if available
   - "Acknowledge" button on each

4. **Engine Info:**
   - Engine hours
   - Make / Model / Serial
   - Data from `asset_engines` table

5. **Maintenance Schedule:**
   - Next due services for this asset
   - From `asset_service_intervals` / `service_reminders`

6. **Service History:**
   - Recent completed WOs for this asset

**Polling:** Use a `Timer.periodic` (30 seconds) to invalidate `latestReadingProvider` and refresh the gauge display. Dispose the timer in the widget's dispose method.

### 6. Update dashboard routing for Telemetry tier

In the `ClientDashboardRouter` (in `lib/features/dashboard/client_dashboard_free.dart`):

- `UserRole.client` with tier >= 3 (telemetry) → `ClientDashboardTelemetry`
- Keep existing: tier 0 → Free, tier 1-2 → Managed

### 7. Owner telemetry view

In `lib/features/dashboard/owner_dashboard.dart`:

Add a telemetry section (use the Alerts placeholder from Batch 3):

- Replace "No active alerts" placeholder with actual data from `activeAlertsProvider`
- Show: alert count badge, list of recent alerts across all clients
- Each alert: client name, vessel name, alert type, severity, time
- Tap → navigates to vessel telemetry detail
- If no alerts: keep "No active alerts" green indicator

### 8. Wire TierGateBanner to all gated screens

Read `lib/features/subscription/tier_gate.dart` and `lib/features/subscription/upgrade_prompt.dart`.

Find ALL screens that should be tier-gated and aren't yet. For each:
- Wrap the screen body with a tier check
- If the user's tier is below required, show `UpgradePrompt` instead of the screen content

**Gate map:**
| Screen | Required Tier |
|--------|--------------|
| Maintenance calendar / service intervals | Planning (2) |
| Checklist templates (client view) | Planning (2) |
| Telemetry dashboard | Telemetry (3) |
| Vessel telemetry detail | Telemetry (3) |
| Live engine data | Telemetry (3) |

Owner and employee roles bypass ALL gates (already implemented in `effectiveTier()`).

For screens that are tier-gated: check the user's tier at the top of the build method. If below required tier, return `UpgradePrompt(requiredTier: SubscriptionTier.planning)` (or telemetry).

### 9. Add telemetry routes

In `lib/core/router.dart`, add:
- `/telemetry/vessel/:assetId` → `VesselTelemetryScreen(assetId: assetId)`
- `/telemetry/dashboard` → `ClientDashboardTelemetry` (for direct navigation)

### 10. Add table name constants

In `lib/core/constants.dart`, add if not already present:
```dart
static const String tTelemetryReadings = 'telemetry_readings';
static const String tTelemetryAlerts = 'telemetry_alerts';
static const String tAssetEngines = 'asset_engines';
static const String tAssetServiceIntervals = 'asset_service_intervals';
```

Check existing constants first — some may already be there.

### 11. Telemetry SQL additions

Write to `supabase-migrations/batch4.sql`:

```sql
-- Add alert_source and severity to telemetry_alerts if not present
ALTER TABLE telemetry_alerts ADD COLUMN IF NOT EXISTS alert_source TEXT DEFAULT 'system';
ALTER TABLE telemetry_alerts ADD COLUMN IF NOT EXISTS severity TEXT DEFAULT 'warning';
ALTER TABLE telemetry_alerts ADD COLUMN IF NOT EXISTS message TEXT;
ALTER TABLE telemetry_alerts ADD COLUMN IF NOT EXISTS acknowledged_at TIMESTAMPTZ;
ALTER TABLE telemetry_alerts ADD COLUMN IF NOT EXISTS acknowledged_by UUID REFERENCES profiles(id);

-- RLS for telemetry_alerts (if not already set)
ALTER TABLE telemetry_alerts ENABLE ROW LEVEL SECURITY;

CREATE POLICY IF NOT EXISTS "Owner sees all alerts" ON telemetry_alerts
  FOR ALL USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'owner')
  );

CREATE POLICY IF NOT EXISTS "Employee sees all alerts" ON telemetry_alerts
  FOR ALL USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'employee')
  );

-- Clients see alerts for engines on their assets
CREATE POLICY IF NOT EXISTS "Client sees own alerts" ON telemetry_alerts
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM asset_engines ae
      JOIN assets a ON ae.asset_id = a.id
      WHERE ae.id = telemetry_alerts.engine_id
      AND a.client_id = auth.uid()
    )
  );

-- RLS for telemetry_readings
ALTER TABLE telemetry_readings ENABLE ROW LEVEL SECURITY;

CREATE POLICY IF NOT EXISTS "Owner sees all readings" ON telemetry_readings
  FOR ALL USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'owner')
  );

CREATE POLICY IF NOT EXISTS "Employee sees all readings" ON telemetry_readings
  FOR ALL USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'employee')
  );

CREATE POLICY IF NOT EXISTS "Client sees own readings" ON telemetry_readings
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM asset_engines ae
      JOIN assets a ON ae.asset_id = a.id
      WHERE ae.id = telemetry_readings.engine_id
      AND a.client_id = auth.uid()
    )
  );
```

Note: The `CREATE POLICY IF NOT EXISTS` syntax may not work on all Postgres versions. If the table already has policies, use `DROP POLICY IF EXISTS ... ; CREATE POLICY ...` pattern instead. Check what pattern the existing migration files use and follow that.

## Important Notes
- Do NOT run `dart run build_runner` or `flutter build`
- Do NOT add dependencies to pubspec.yaml
- Follow existing code patterns exactly
- Use `AppColors` and existing theme
- The telemetry data pipeline (Pi → Supabase) doesn't exist yet — these screens will show empty states until hardware is connected
- Polling uses `Timer.periodic` — always dispose in widget's dispose method
- Check for existing implementations before writing new code
