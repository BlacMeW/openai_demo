import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:openai_demo/models/message_model.dart';
import 'package:openai_demo/services/openai_service.dart';

part 'chat_event.dart';
part 'chat_state.dart';

class ChatBloc extends Bloc<ChatEvent, ChatState> {
  final OpenAIService openAIService;

  ChatBloc({required this.openAIService}) : super(ChatInitial(messages: const [])) {
    on<SendMessage>(_onSendMessage);
    on<ReceiveMessage>(_onReceiveMessage);
    on<ErrorOccurred>(_onErrorOccurred);
  }

  Future<void> _onSendMessage(
    SendMessage event,
    Emitter<ChatState> emit,
  ) async {
    try {
      // Clear any previous error state
      final messages = state is ChatError
          ? (state as ChatError).messages
          : state.messages;

      // Add user message to chat
      final userMessage = Message(
        content: event.message,
        isUser: true,
        timestamp: DateTime.now(),
      );
      final newMessages = [...messages, userMessage];

      emit(ChatLoading(messages: newMessages));

      // Start streaming response
      final stream = openAIService.sendChatStream(newMessages);

      // For testing error handling - uncomment to simulate API failure
      // throw Exception('Simulated API failure');

      // Add empty assistant message and switch to streaming state
      final assistantMessage = Message(
        content: '',
        isUser: false,
        timestamp: DateTime.now(),
      );
      emit(ChatStreaming(messages: [...newMessages, assistantMessage]));

      await for (final content in stream) {
        add(ReceiveMessage(content));
      }
    } catch (e) {
      final errorMessage = Message(
        content: 'Error: ${e.toString()}',
        isUser: false,
        timestamp: DateTime.now(),
      );
      emit(ChatError(
        messages: [...state.messages, errorMessage],
        error: e.toString(),
      ));
    }
  }

  Future<void> _onReceiveMessage(
    ReceiveMessage event,
    Emitter<ChatState> emit,
  ) async {
    if (state is! ChatStreaming) return;

    final messages = state.messages;
    if (messages.isEmpty) return;

    final lastMessage = messages.last;
    if (lastMessage.isUser) return;

    // Skip empty updates
    if (event.message.isEmpty) return;

    final updatedMessage = Message(
      content: lastMessage.content + event.message,
      isUser: false,
      timestamp: DateTime.now(),
    );

    emit(ChatStreaming(messages: [...messages.sublist(0, messages.length - 1), updatedMessage]));

    // If we receive a special completion marker, transition to success
    if (event.message.endsWith('[DONE]')) {
      emit(ChatSuccess(messages: messages));
    }
  }

  Future<void> _onErrorOccurred(
    ErrorOccurred event,
    Emitter<ChatState> emit,
  ) async {
    // Don't add duplicate error messages
    if (state is ChatError && (state as ChatError).error == event.error) return;

    final errorMessage = Message(
      content: 'Error: ${event.error}',
      isUser: false,
      timestamp: DateTime.now(),
    );

    emit(ChatError(
      messages: [...state.messages, errorMessage],
      error: event.error,
    ));
  }
}