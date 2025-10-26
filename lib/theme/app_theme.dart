import 'package:flutter/material.dart';

class AppColors {
  static final Color seedDark = Colors.green.shade800;
  static final Color seedLight = Colors.greenAccent.shade200;
}

class AppGradients {
  static LinearGradient dark = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Colors.green.shade900,
      Colors.green.shade600,
      Colors.greenAccent.shade200,
    ],
  );

  static LinearGradient light = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Colors.greenAccent.shade200,
      Colors.green.shade600,
      Colors.green.shade900,
    ],
  );

  static LinearGradient of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}
