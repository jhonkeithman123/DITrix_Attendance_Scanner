import 'package:flutter/material.dart';

class AppNotifier {
  AppNotifier._();

  /// Show a transient SnackBar. Replaces direct use of ScaffoldMessenger.
  static void showSnack(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 4),
    SnackBarAction? action,
  }) {
    final sb =
        SnackBar(content: Text(message), duration: duration, action: action);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(sb);
  }

  /// Show a simple information dialog. Returns true when user presses the positive action.
  static Future<bool?> showConfirm(
    BuildContext context, {
    String title = 'Notice',
    required String content,
    String confirmLabel = 'OK',
    String cancelLabel = 'Cancel',
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(cancelLabel)),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(confirmLabel)),
        ],
      ),
    );
  }

  /// Show a simple alert dialog (OK).
  static Future<void> showAlert(
    BuildContext context, {
    String title = 'Notice',
    required String content,
    String okLabel = 'OK',
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(), child: Text(okLabel)),
        ],
      ),
    );
  }
}
