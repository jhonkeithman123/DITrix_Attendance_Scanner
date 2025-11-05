class Session {
  final String id;
  final DateTime createdAt;
  String subject;
  String startTime; // "HH:mm"
  String endTime; // "HH:mm"
  List<Map<String, dynamic>> roster; // [{id, name, present, time, status}]

  Session({
    required this.id,
    required this.createdAt,
    this.subject = '',
    this.startTime = '00:00',
    this.endTime = '00:00',
    List<Map<String, dynamic>>? roster,
  }) : roster = roster ?? <Map<String, dynamic>>[];

  // date string (YYYY-MM-DD) derived from createdAt — used by UI and server payloads
  String get date => createdAt.toIso8601String().split('T').first;

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'date': date,
        'subject': subject,
        'startTime': startTime,
        'endTime': endTime,
        'roster': roster,
      };

  static Session fromJson(Map<String, dynamic> j) => Session(
        id: j['id'] as String,
        createdAt: DateTime.tryParse(j['createdAt'] ?? '') ?? DateTime.now(),
        subject: (j['subject'] ?? '').toString(),
        startTime: (j['startTime'] ?? '00:00').toString(),
        endTime: (j['endTime'] ?? '00:00').toString(),
        roster: (j['roster'] as List?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            <Map<String, dynamic>>[],
      );
}
