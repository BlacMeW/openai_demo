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

  /// Sends a chat message to OpenAI with retry logic for rate limiting
  ///
  /// [messages] - List of conversation messages
  /// [maxRetries] - Maximum number of retry attempts (default: 3)
  /// [onRateLimit] - Callback for rate limit notifications
  ///
  /// Returns a stream of response chunks
  Stream<String> sendChatStream(
    List<Message> messages, {
    int maxRetries = 3,
    Function(String)? onRateLimit,
  }) async* {
    int retryCount = 0;

    while (retryCount <= maxRetries) {
      try {
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

        // Handle rate limiting (HTTP 429)
        if (response.statusCode == 429) {
          if (retryCount >= maxRetries) {
            throw Exception('Rate limit exceeded after $maxRetries retries');
          }

          // Get retry delay from Retry-After header or use default
          final retryAfterHeader = response.headers['retry-after'];
          final retryDelay = _getRetryDelay(retryAfterHeader);

          // Notify user about rate limiting
          if (onRateLimit != null) {
            onRateLimit('You\'re sending requests too fast. Please wait.');
          }

          // Wait before retrying
          await Future.delayed(Duration(seconds: retryDelay));
          retryCount++;
          continue;
        }

        // Handle other HTTP errors
        if (response.statusCode != 200) {
          throw Exception('Failed to load response: ${response.statusCode}');
        }

        // Process successful response
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
        return; // Success, exit the retry loop

      } catch (e) {
        // Handle network or other errors
        if (retryCount >= maxRetries) {
          throw Exception('Failed to send message after $maxRetries retries: $e');
        }

        // Exponential backoff for non-rate-limit errors
        final backoffDelay = 2 * (retryCount + 1);
        await Future.delayed(Duration(seconds: backoffDelay));
        retryCount++;
      }
    }
  }

  /// Calculates retry delay based on Retry-After header
  ///
  /// [retryAfterHeader] - The Retry-After header value (can be seconds or HTTP-date)
  /// Returns delay in seconds (default: 5 seconds)
  int _getRetryDelay(String? retryAfterHeader) {
    if (retryAfterHeader == null) {
      return 5; // Default delay
    }

    try {
      // Try parsing as integer (seconds)
      final seconds = int.tryParse(retryAfterHeader);
      if (seconds != null) {
        return seconds.clamp(1, 60); // Limit between 1-60 seconds
      }

      // Try parsing as HTTP-date (RFC 7231 format)
      final date = DateTime.tryParse(retryAfterHeader);
      if (date != null) {
        final delay = date.difference(DateTime.now()).inSeconds;
        return delay.clamp(1, 60); // Limit between 1-60 seconds
      }
    } catch (e) {
      // Fallback to default if parsing fails
    }

    return 5; // Default delay
  }

  /// Sends a single chat message with retry logic
  ///
  /// [message] - The message to send
  /// [contextMessages] - Previous conversation context
  /// [onRateLimit] - Callback for rate limit notifications
  ///
  /// Returns the complete response as a string
  Future<String> sendMessage(
    String message, {
    List<Message> contextMessages = const [],
    Function(String)? onRateLimit,
  }) async {
    final messages = [
      ...contextMessages,
      Message(content: message, isUser: true),
    ];

    final responseBuffer = StringBuffer();

    await for (final chunk in sendChatStream(
      messages,
      onRateLimit: onRateLimit,
    )) {
      if (chunk != '[DONE]') {
        responseBuffer.write(chunk);
      }
    }

    return responseBuffer.toString();
  }

  void dispose() {
    _client.close();
  }
}

/// Custom exception for rate limiting
class RateLimitException implements Exception {
  final String message;
  final int? retryAfter;

  RateLimitException(this.message, {this.retryAfter});

  @override
  String toString() => message;
}
