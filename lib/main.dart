import 'dart:io';

import 'package:flutter/material.dart';

import 'services/native_control.dart';

void main() {
  runApp(const LocalBlueyApp());
}

class LocalBlueyApp extends StatelessWidget {
  const LocalBlueyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Local Bluey',
      theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool? _trusted;

  @override
  void initState() {
    super.initState();
    _refreshTrust();
  }

  Future<void> _refreshTrust() async {
    if (!Platform.isMacOS) return;
    final trusted = await NativeControl.isTrusted();
    if (mounted) setState(() => _trusted = trusted);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Local Bluey')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              Platform.isMacOS
                  ? 'Accessibility: ${_trusted == null ? 'checking…' : (_trusted! ? 'granted' : 'not granted')}'
                  : 'iOS build - pair with your Mac to begin',
            ),
            if (Platform.isMacOS && _trusted == false)
              TextButton(
                onPressed: () async {
                  await NativeControl.askPermission();
                  await _refreshTrust();
                },
                child: const Text('Grant Accessibility permission'),
              ),
          ],
        ),
      ),
    );
  }
}
