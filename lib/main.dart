import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';

import 'src/app_state.dart';
import 'src/notifications/notification_service.dart';
import 'src/settings/app_config.dart';
import 'src/ui/home_screen.dart';
import 'src/ui/onboarding_screen.dart';
import 'src/ui/unlock_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final supportDir = await getApplicationSupportDirectory();
  final state = AppState(
    configStore: AppConfigStore(),
    baseDir: supportDir.path,
    notifications: NotificationService(),
  );
  await state.initialize();
  runApp(EncryptedTodoApp(state: state));
}

class EncryptedTodoApp extends StatelessWidget {
  const EncryptedTodoApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Verschlüsselte ToDos',
      locale: const Locale('de'),
      supportedLocales: const [Locale('de')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.teal, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          if (!state.initialized) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          if (!state.isConfigured) return OnboardingScreen(state: state);
          if (state.needsUnlock) return UnlockScreen(state: state);
          return HomeScreen(state: state);
        },
      ),
    );
  }
}
