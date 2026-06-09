import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../main.dart';

final themeModeProvider = StateProvider<ThemeMode>((ref) {
  final saved = globalPrefs.getString('selectedTheme') ?? 'system';
  switch (saved) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
});
