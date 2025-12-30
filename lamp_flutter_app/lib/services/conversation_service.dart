import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../models/conversation.dart';
import '../models/message.dart';

class ConversationService {
  // Get session token
  Future<Map<String, String>> _getHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('session_cookie'); // Still using same key
    print('DEBUG: Session token: $token');
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // Get all conversations for logged-in user
  Future<List<Conversation>> getConversations() async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse(ApiConfig.conversationsUrl),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final List conversationsList = data['conversations'] ?? [];
        return conversationsList.map((json) => Conversation.fromJson(json)).toList();
      } else if (response.statusCode == 401) {
        throw Exception('Please login first');
      } else {
        throw Exception('Failed to load conversations: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error: $e');
    }
  }

  // Get messages from a specific conversation
  Future<List<Message>> getConversationMessages(String conversationId) async {
    if (conversationId.isEmpty) return []; // Prevent empty ID requests
    
    try {
      final headers = await _getHeaders();
      // Use /api/history matching Web App logic
      final response = await http.get(
        Uri.parse('${ApiConfig.chatHistoryUrl}?conversation_id=$conversationId'),
        headers: headers,
      );

      print('DEBUG: Fetch history response: ${response.statusCode} - ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List messagesJson = data['history'] ?? []; // Web uses 'history'
        return messagesJson.map((json) => Message.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load messages');
      }
    } catch (e) {
      throw Exception('Error: $e');
    }
  }

  // Delete a conversation
  Future<bool> deleteConversation(String conversationId) async {
    if (conversationId.isEmpty) return false;
    
    try {
      final headers = await _getHeaders();
      final response = await http.delete(
        Uri.parse('${ApiConfig.conversationsUrl}/$conversationId'),
        headers: headers,
      );

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Create new conversation
  Future<String?> createConversation(String title) async {
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse(ApiConfig.conversationsUrl),
        headers: headers,
        body: jsonEncode({'title': title}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return data['conversation_id'];
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
