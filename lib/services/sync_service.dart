import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;

/// Simple queue-based sync service: enqueue and automatically
/// attempt to push them when connectivity is available.
class SyncService {
  final _queue = <Map<String, dynamic>>[];
  final http.Client _client;
  final String baseUrl;
  StreamSubscription<ConnectivityResult>? _connSub;
  bool _syncing = false;

  SyncService({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  void start() {
    _connSub = Connectivity().onConnectivityChanged.listen((r) {
      if (r != ConnectivityResult.none) _trySync();
    }) as StreamSubscription<ConnectivityResult>?;
    // try initial sync
    _trySync();
  }

  void stop() {
    _connSub?.cancel();
  }

  void enqueue(Map<String, dynamic> item) {
    _queue.add(item);
    _trySync();
  }

  Future<void> _trySync() async {
    if (_syncing) return;
    if (_queue.isEmpty) return;

    final conn = await Connectivity().checkConnectivity();
    if (conn == ConnectivityResult.none) return;
    _syncing = true;

    try {
      while (_queue.isNotEmpty) {
        final item = _queue.first;
        final res = await _client
            .post(
              Uri.parse('$baseUrl/sync'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(item),
            )
            .timeout(const Duration(seconds: 8));

        if (res.statusCode == 200) {
          _queue.removeAt(0);
        } else {
          // server reject - stop and retry later
          break;
        }
      }
    } catch (_) {
      // network error - will retry on next connectivity change
    } finally {
      _syncing = false;
    }
  }
}
