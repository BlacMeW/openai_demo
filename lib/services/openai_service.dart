import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:openai_demo/models/message_model.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class OpenAIService {
  static const String _baseUrl = 'https://api.openai.com/v1';
  final String _apiKey;
  final http.Client _client;

  OpenAIService({http.Client? client})
    : _apiKey = dotenv.get('OPENAI_API_KEY'),
      _client = client ?? http.Client();

  Stream<String> sendChatStream(List<Message> messages) async* {
    final uri = Uri.parse('$_baseUrl/chat/completions');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $_apiKey',
    };

    final body = {
      'model': 'gpt-3.5-turbo',
      'messages': messages.map((m) => {
        'role': m.isUser ? 'user' : 'assistant',
        'content': m.content
      }).toList(),
      'stream': true,
    };

    final request = http.Request('POST', uri)
      ..headers.addAll(headers)
      ..body = jsonEncode(body);

    final response = await _client.send(request);

    if (response.statusCode != 200) {
      throw Exception('Failed to load response: ${response.statusCode}');
    }

    await for (final chunk in response.stream.transform(utf8.decoder)) {
      final lines = chunk.split('\n');
      for (final line in lines) {
        if (line.startsWith('data:')) {
          if (line.contains('[DONE]')) {
            yield '[DONE]';
            return;
          }

          try {
            final json = jsonDecode(line.substring(5));
            final content = json['choices'][0]['delta']['content'] ?? '';
            if (content.isNotEmpty) {
              yield content;
            }
          } catch (e) {
            // Skip invalid JSON chunks
          }
        }
      }
    }
  }

  void dispose() {
    _client.close();
  }
}
