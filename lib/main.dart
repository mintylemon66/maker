import 'package:flutter/material.dart';

import 'splash_page.dart';
import 'services/fall_notification_service.dart';
import 'theme_settings.dart';

import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

const Color _brandSeed = Color(0xFF97DE62);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await FallNotificationService.initialize();
  await loadSavedThemeMode();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final lightTheme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: _brandSeed,
        brightness: Brightness.light,
      ),
      useMaterial3: true,
    );
    final darkTheme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: _brandSeed,
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    );

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: appThemeModeNotifier,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'Placeholder',
          debugShowCheckedModeBanner: false,
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: mode,
          home: SplashPage(),
        );
      },
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;

  void _incrementCounter() {
    setState(() {
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('You have pushed the button this many times:'),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}
