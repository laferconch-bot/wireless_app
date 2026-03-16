import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/dashboard_screen.dart';
import 'providers/csv_data_provider.dart';
import 'providers/app_settings.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CSVDataProvider()),
        ChangeNotifierProvider(create: (_) => AppSettings()..load()),
      ],
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  static final ValueNotifier<ThemeMode> themeNotifier =
      ValueNotifier(ThemeMode.system);

  @override
  Widget build(BuildContext context) {
    return Consumer<AppSettings>(
      builder: (context, settings, _) {
        themeNotifier.value = settings.themeMode;
        final Color seed = settings.seedColor;
        final ThemeData light = ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light),
          useMaterial3: true,
          snackBarTheme: SnackBarThemeData(
            behavior: SnackBarBehavior.floating,
            backgroundColor: seed.withOpacity(0.12),
            contentTextStyle: const TextStyle(fontWeight: FontWeight.w600),
          ),
        );
        final ThemeData dark = ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
          useMaterial3: true,
          snackBarTheme: SnackBarThemeData(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.black87,
            contentTextStyle: TextStyle(color: seed, fontWeight: FontWeight.w600),
          ),
          scaffoldBackgroundColor: Colors.black,
          appBarTheme: const AppBarTheme(backgroundColor: Colors.black, foregroundColor: Colors.white),
        );
        return MaterialApp(
          title: 'Soil Dashboard',
          theme: light,
          darkTheme: dark,
          themeMode: settings.themeMode,
          home: DashboardScreen(), // removed const
        );
      },
    );
  }
}
