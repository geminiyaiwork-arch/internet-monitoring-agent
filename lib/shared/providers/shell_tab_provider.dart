import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bottom navigation index for tray shortcuts (0–3).
final shellTabProvider = StateProvider<int>((ref) => 0);
