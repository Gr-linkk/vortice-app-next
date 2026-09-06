import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/core/router.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'dart:async';
import 'package:vortice_app/core/push_notifications.dart';
import 'package:vortice_app/features/notifications/notification_provider.dart';

class VorticeApp extends ConsumerWidget {
  const VorticeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.read(routerProvider);
    final locale = ref.watch(localeProvider);
    final push = ref.read(pushNotificationsProvider);
    push.locale = locale.languageCode;
    ref.listen(authStatusProvider, (previous, next) {
      if (previous?.profile?.id != next.profile?.id) {
        unawaited(push.synchronize());
      }
      if (next.profile?.id != null &&
          push.openedForAccount == next.profile!.id) {
        push.openedForAccount = null;
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => router.go('/notifications'),
        );
      }
    });
    ref.listen(pushNotificationsProvider, (_, next) {
      ref.invalidate(notificationsProvider);
      if (next.openedForAccount == ref.read(authStatusProvider).profile?.id &&
          next.openedForAccount != null) {
        next.openedForAccount = null;
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => router.go('/notifications'),
        );
      }
    });

    return MaterialApp.router(
      title: 'Vórtice Mechanical',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkNavyTheme,
      routerConfig: router,
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('es')],
    );
  }
}
