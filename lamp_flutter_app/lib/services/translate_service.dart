import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/http.dart' as http_multipart;
import 'package:image_picker/image_picker.dart'; // For XFile
import 'package:flutter/foundation.dart' show kIsWeb; // For Web check
import '../config/api_config.dart';

class TranslateService {
  // Translate text
  Future<String> translateText(
    String text, {
    String sourceLang = 'auto',
    String targetLang = 'vi',
  }) async {
    try {
      final response = await http.post(
        Uri.parse(ApiConfig.translateUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'text': text,
          'source': sourceLang,
          'target': targetLang,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['text'] ?? '';
      } else {
        throw Exception('Translation failed: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error: $e');
    }
  }

  // OCR from image
  Future<String> extractTextFromImage(XFile imageFile) async {
    try {
      var request = http_multipart.MultipartRequest(
        'POST',
        Uri.parse(ApiConfig.ocrUrl),
      );
      
      if (kIsWeb) {
        // Web: Use bytes
        request.files.add(http_multipart.MultipartFile.fromBytes(
          'image',
          await imageFile.readAsBytes(),
          filename: imageFile.name,
        ));
      } else {
        // Mobile: Use path
        request.files.add(await http_multipart.MultipartFile.fromPath(
          'image',
          imageFile.path,
        ));
      }

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['text'] ?? 'No text detected';
      } else {
        throw Exception('OCR failed: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error: $e');
    }
  }
}
