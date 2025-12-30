class Conversation {
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;

  Conversation({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic dateVal) {
      if (dateVal == null) return DateTime.now();
      if (dateVal is! String) return DateTime.now();
      try {
        return DateTime.parse(dateVal);
      } catch (e) {
        // Fallback for HTTP Date format or other formats
        try {
          // Attempt to parse RFC 1123 format if needed, or just return now() to prevent crash
          // Simply returning now() is safer for UI stability
          print('Date parse error for $dateVal: $e');
          return DateTime.now();
        } catch (_) {
          return DateTime.now();
        }
      }
    }

    return Conversation(
      id: json['id'] ?? json['_id'] ?? '',
      title: json['title'] ?? 'New Chat',
      createdAt: parseDate(json['created_at']),
      updatedAt: parseDate(json['updated_at']),
    );
  }
}
