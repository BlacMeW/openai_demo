part of 'chat_bloc.dart';

abstract class ChatEvent {
  const ChatEvent();
}

class SendMessage extends ChatEvent {
  final String message;

  const SendMessage(this.message);
}

class ReceiveMessage extends ChatEvent {
  final String message;

  const ReceiveMessage(this.message);
}

class ErrorOccurred extends ChatEvent {
  final String error;

  const ErrorOccurred(this.error);
}