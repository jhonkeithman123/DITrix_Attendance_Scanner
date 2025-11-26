import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/session.dart';

class SessionStore {
  Future<Directory> _baseDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'sessions'));

    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    return dir;
  }

  Future<File> _fileForId(String id) async {
    final dir = await _baseDir();
    return File(p.join(dir.path, '$id.json'));
  }

  Future<Session> createNew() async {
    final now = DateTime.now();
    final stamp =
        '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    final rnd = (now.microsecondsSinceEpoch % 10000).toString().padLeft(4, '0');
    final id = '${stamp}_$rnd';
    final s = Session(id: id, createdAt: now);
    await save(s);
    return s;
  }

  Future<void> save(Session s) async {
    final f = await _fileForId(s.id);
    final jsonStr = const JsonEncoder.withIndent('  ').convert(s.toJson());
    await f.writeAsString(jsonStr);
  }

  Future<Session?> load(String id) async {
    final f = await _fileForId(id);
    if (!await f.exists()) return null;
    final txt = await f.readAsString();
    return Session.fromJson(jsonDecode(txt) as Map<String, dynamic>);
  }

  Future<List<Session>> list() async {
    final dir = await _baseDir();
    final files = await dir
        .list()
        .where((e) => e is File && e.path.endsWith('.json'))
        .cast<File>()
        .toList();
    final sessions = <Session>[];

    for (final f in files) {
      try {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        sessions.add(Session.fromJson(j));
      } catch (_) {}
    }
    sessions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sessions;
  }

  Future<void> delete(String id) async {
    final f = await _fileForId(id);
    if (await f.exists()) await f.delete();
  }
}
