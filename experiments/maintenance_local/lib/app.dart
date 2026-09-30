import 'package:flutter/material.dart';
import 'lab_store.dart';
import 'ui/workspace_page.dart';

class LabApp extends StatefulWidget {
  const LabApp({
    super.key,
    required this.store,
    this.textScale,
    this.officePort = 47841,
  });
  final LabStore store;
  final double? textScale;
  final int officePort;
  @override
  State<LabApp> createState() => _LabAppState();
}

class _LabAppState extends State<LabApp> {
  late LabStore store = widget.store;
  @override
  void didUpdateWidget(LabApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.store != oldWidget.store) store = widget.store;
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Vortice Local Maintenance',
    debugShowCheckedModeBanner: false,
    builder: widget.textScale == null
        ? null
        : (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(widget.textScale!)),
            child: child!,
          ),
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xfff7f4ed),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff103d3c),
        primary: const Color(0xff103d3c),
        surface: const Color(0xfff7f4ed),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xfff7f4ed),
        foregroundColor: Color(0xff103d3c),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
      ),
      cardTheme: const CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.symmetric(vertical: 8),
      ),
    ),
    home: WorkspacePage(
      key: ObjectKey(store),
      store: store,
      officePort: widget.officePort,
      onRestored: (next) => setState(() => store = next),
    ),
  );
}
