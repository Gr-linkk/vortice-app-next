import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Injected before runApp so a saved preference is applied on the first frame.
final appearancePreferencesProvider = Provider<SharedPreferences?>(
  (ref) => null,
);

final themeModeProvider = StateNotifierProvider<ThemeModeController, ThemeMode>(
  (ref) => ThemeModeController(ref.watch(appearancePreferencesProvider)),
);

class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController(this._preferences)
    : super(parse(_preferences?.getString(preferenceKey)));

  static const preferenceKey = 'vortice_next_appearance';
  final SharedPreferences? _preferences;
  Future<void> _pending = Future<void>.value();

  static ThemeMode parse(String? value) => switch (value) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  /// Serialize writes so rapid changes cannot restore an older disk value.
  Future<void> select(ThemeMode value) {
    final request = _pending.then((_) async {
      final prefs = _preferences;
      if (prefs == null || !await prefs.setString(preferenceKey, value.name)) {
        throw StateError('Appearance preference could not be saved.');
      }
      if (mounted) state = value;
    });
    _pending = request.catchError((Object _) {});
    return request;
  }
}

class AppearanceSettingsScreen extends ConsumerStatefulWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  ConsumerState<AppearanceSettingsScreen> createState() =>
      _AppearanceSettingsScreenState();
}

class _AppearanceSettingsScreenState
    extends ConsumerState<AppearanceSettingsScreen> {
  bool _saving = false;

  Future<void> _select(ThemeMode value) async {
    setState(() => _saving = true);
    try {
      await ref.read(themeModeProvider.notifier).select(value);
    } catch (_) {
      if (!mounted) return;
      final es = Localizations.localeOf(context).languageCode == 'es';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            es
                ? 'No se pudo guardar la apariencia. Inténtalo de nuevo.'
                : 'Could not save appearance. Please try again.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(themeModeProvider);
    final es = Localizations.localeOf(context).languageCode == 'es';
    return Scaffold(
      appBar: AppBar(title: Text(es ? 'Configuración' : 'Settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            es ? 'Apariencia' : 'Appearance',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            es
                ? 'Elige una apariencia. Sistema sigue el modo claro u oscuro de tu dispositivo.'
                : 'Choose an appearance. System follows your device’s light or dark mode.',
          ),
          const SizedBox(height: 20),
          for (final mode in ThemeMode.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Semantics(
                selected: selected == mode,
                child: ListTile(
                  enabled: !_saving,
                  selected: selected == mode,
                  selectedTileColor: Theme.of(
                    context,
                  ).colorScheme.secondaryContainer,
                  shape: RoundedRectangleBorder(
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  leading: Icon(switch (mode) {
                    ThemeMode.system => Icons.brightness_auto_outlined,
                    ThemeMode.light => Icons.light_mode_outlined,
                    ThemeMode.dark => Icons.dark_mode_outlined,
                  }),
                  title: Text(switch (mode) {
                    ThemeMode.system => es ? 'Sistema' : 'System',
                    ThemeMode.light => es ? 'Claro' : 'Light',
                    ThemeMode.dark => es ? 'Oscuro' : 'Dark',
                  }),
                  trailing: selected == mode ? const Icon(Icons.check) : null,
                  onTap: _saving ? null : () => _select(mode),
                ),
              ),
            ),
          if (_saving) const LinearProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            es
                ? 'Tu elección se guarda en este dispositivo.'
                : 'Your choice is saved on this device.',
          ),
        ],
      ),
    );
  }
}
