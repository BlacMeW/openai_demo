part of 'chat_bloc.dart';

abstract class ChatState {
  final List<Message> messages;

  const ChatState({this.messages = const []});
}

class ChatInitial extends ChatState {
  const ChatInitial({super.messages = const []});
}

class ChatLoading extends ChatState {
  const ChatLoading({super.messages});
}

class ChatSuccess extends ChatState {
  const ChatSuccess({super.messages});
}

class ChatStreaming extends ChatState {
  const ChatStreaming({super.messages});
}

class ChatError extends ChatState {
  final String error;

  const ChatError({
    required this.error,
    super.messages,
  });
}