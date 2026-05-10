import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/dashboard_screen.dart';
import 'screens/logs_screen.dart';
import 'screens/providers_screen.dart';
import 'screens/settings_screen.dart';
import 'services/app_state.dart';
import 'services/config_service.dart';
import 'services/provider_router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Determine a suitable storage directory.
  // On Linux/Android this uses the user's home directory or a temp fallback.
  final storageDir = Directory(
    Platform.environment['主页'] ??
        Platform.environment['TMPDIR'] ??
        '/tmp',
  );

  final configService = ConfigService(storageDir: storageDir);

  // Load the initial config so we can seed the router.
  final initialConfig = await configService.loadConfigWithKeys();
  final router = ProviderRouter(initialConfig.providers);

  runApp(
    MultiProvider(
      providers: [
        Provider<ConfigService>.value(value: configService),
        ChangeNotifierProvider<AppState>(
          create: (_) {
            final state = AppState(
              configService: configService,
              router: router,
            );
            // Kick off async initialization (loads config, starts event listener)
            state.init();
            return state;
          },
        ),
      ],
      child: const CapRelayApp(),
    ),
  );
}

/// Root widget for the CAP Relay application.
class CapRelayApp extends StatelessWidget {
  const CapRelayApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Use a deep vibrant seed color for Material You dynamic colors
    return MaterialApp(
      title: 'CAP 中转',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF7C4DFF), // vibrant purple
        scaffoldBackgroundColor: const Color(0xFF0D0D1A),
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
          scrolledUnderElevation: 1,
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        dialogTheme: DialogThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorSchemeSeed: const Color(0xFF7C4DFF),
      ),
      home: const MainShell(),
    );
  }
}

/// Main shell with bottom navigation bar hosting the 4 primary screens.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    DashboardScreen(),
    ProvidersScreen(),
    LogsScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) =>
            setState(() => _currentIndex = index),
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.primaryContainer,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_rounded),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: '仪表盘',
          ),
          NavigationDestination(
            icon: Icon(Icons.cloud_rounded),
            selectedIcon: Icon(Icons.cloud_rounded),
            label: '供应商',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_rounded),
            selectedIcon: Icon(Icons.history_rounded),
            label: '日志',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_rounded),
            selectedIcon: Icon(Icons.settings_rounded),
            label: '设置',
          ),
        ],
      ),
    );
  }
}
