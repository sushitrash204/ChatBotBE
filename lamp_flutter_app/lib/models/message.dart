class Message {
  final String role; // 'user' or 'model'
  final String text;
  final DateTime timestamp;

  Message({
    required this.role,
    required this.text,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  // Convert to JSON for API
  Map<String, dynamic> toJson() {
    return {
      'role': role,
      'parts': [{'text': text}],
    };
  }

  // Create from JSON
  factory Message.fromJson(Map<String, dynamic> json) {
    String text = '';
    if (json['parts'] != null && json['parts'].isNotEmpty) {
      text = json['parts'][0]['text'] ?? '';
    } else if (json['text'] != null) {
      text = json['text'];
    } else if (json['content'] != null) {
      text = json['content'];
    }
    return Message(
      role: json['role'] ?? 'model',
      text: text,
    );
  }
}
