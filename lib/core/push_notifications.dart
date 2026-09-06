import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/core/user_feedback.dart';

class NextFirebaseConfig {
  static const project = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const app = String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
  static const sender = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const key = String.fromEnvironment('FIREBASE_API_KEY');
  static bool get configured =>
      project == 'vortice-next' &&
      app == '1:256876964373:android:ba58553beed6145f033c1c' &&
      sender == '256876964373' &&
      key.isNotEmpty;
  static const options = FirebaseOptions(
    apiKey: key,
    appId: app,
    messagingSenderId: sender,
    projectId: project,
  );
}

@pragma('vm:entry-point')
Future<void> nextBackgroundMessage(RemoteMessage message) async {
  if (NextFirebaseConfig.configured) {
    await Firebase.initializeApp(options: NextFirebaseConfig.options);
  }
}

final pushNotificationsProvider = ChangeNotifierProvider<PushNotifications>(
  (_) => PushNotifications.instance,
);

class PushNotifications extends ChangeNotifier {
  PushNotifications._();
  static final instance = PushNotifications._();
  bool initialized = false,
      registered = false,
      busy = false,
      unavailable = false;
  String locale = 'en';
  String? openedForAccount;
  int inboxRevision = 0;
  Future<void> _serial = Future.value();
  Future<void> initialize() async {
    if (initialized ||
        !NextFirebaseConfig.configured ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      await Firebase.initializeApp(options: NextFirebaseConfig.options);
      FirebaseMessaging.onBackgroundMessage(nextBackgroundMessage);
      initialized = true;
      FirebaseMessaging.instance.onTokenRefresh.listen(
        (_) => unawaited(synchronize()),
      );
      FirebaseMessaging.onMessage.listen((_) {
        inboxRevision++;
        notifyListeners();
      });
      FirebaseMessaging.onMessageOpenedApp.listen(_opened);
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _opened(initial);
    } catch (_) {
      unavailable = true;
    }
  }

  void _opened(RemoteMessage message) {
    openedForAccount = message.data['recipient_id'] as String?;
    inboxRevision++;
    notifyListeners();
  }

  Future<String> _device() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('next_push_device');
    if (id == null) {
      id = const Uuid().v4();
      await prefs.setString('next_push_device', id);
    }
    return id;
  }

  Future<void> synchronize({bool askPermission = false}) {
    _serial = _serial.catchError((_) {}).then((_) async {
      if (!initialized) return;
      busy = true;
      notifyListeners();
      try {
        final account = supabase.auth.currentUser?.id;
        if (account == null) {
          registered = false;
          return;
        }
        final settings = askPermission
            ? await FirebaseMessaging.instance.requestPermission(
                alert: true,
                badge: true,
                sound: true,
              )
            : await FirebaseMessaging.instance.getNotificationSettings();
        final device = await _device();
        if (supabase.auth.currentUser?.id != account) return;
        if (settings.authorizationStatus != AuthorizationStatus.authorized &&
            settings.authorizationStatus != AuthorizationStatus.provisional) {
          await supabase.rpc(
            'unregister_push_device',
            params: {'p_device': device},
          );
          registered = false;
          return;
        }
        final token = await FirebaseMessaging.instance.getToken();
        if (token == null || supabase.auth.currentUser?.id != account) return;
        await supabase
            .rpc(
              'register_push_device',
              params: {
                'p_device': device,
                'p_token': token,
                'p_locale': locale,
              },
            )
            .timeout(const Duration(seconds: 10));
        if (supabase.auth.currentUser?.id != account) return;
        registered = true;
        unavailable = false;
      } catch (_) {
        registered = false;
        unavailable = true;
      } finally {
        busy = false;
        notifyListeners();
      }
    });
    return _serial;
  }

  Future<void> detach() async {
    if (!initialized) return;
    await _serial;
    try {
      await supabase
          .rpc('unregister_push_device', params: {'p_device': await _device()})
          .timeout(const Duration(seconds: 5));
    } catch (_) {}
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
    registered = false;
    openedForAccount = null;
    notifyListeners();
  }
}

class PushNotificationSettings extends ConsumerWidget {
  const PushNotificationSettings({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final push = ref.watch(pushNotificationsProvider), es = isSpanish(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              es ? 'Avisos en este dispositivo' : 'Alerts on this device',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              !push.initialized
                  ? (es
                        ? 'Los avisos del teléfono todavía no están configurados en esta versión. Las novedades siguen en esta bandeja.'
                        : 'Phone alerts are not configured in this build yet. Updates remain available in this inbox.')
                  : push.registered
                  ? (es
                        ? 'Dispositivo registrado para avisos de asignaciones, fallas urgentes, informes devueltos e inspecciones.'
                        : 'Device registered for assignment, urgent fault, returned report and inspection alerts.')
                  : push.unavailable
                  ? (es
                        ? 'No se pudo registrar el dispositivo. Reintenta con conexión.'
                        : 'Device registration failed. Retry with a connection.')
                  : (es
                        ? 'Activa los avisos para recibir novedades con la app cerrada.'
                        : 'Enable alerts to receive updates when the app is closed.'),
            ),
            if (push.initialized)
              TextButton.icon(
                onPressed: push.busy
                    ? null
                    : () => push.synchronize(askPermission: true),
                icon: const Icon(Icons.notifications_active_outlined),
                label: Text(
                  es ? 'Activar o comprobar avisos' : 'Enable or check alerts',
                ),
              ),
          ],
        ),
      ),
    );
  }
}
