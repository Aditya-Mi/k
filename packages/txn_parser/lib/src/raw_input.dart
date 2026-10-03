import 'enums.dart';

/// A message as received, before any parsing.
class RawInput {
  const RawInput({
    required this.channel,
    required this.sender,
    required this.body,
    required this.receivedAt,
    this.subject,
  });

  final Channel channel;

  /// SMS header ("AX-AXISBK-S") or email From (`Axis Bank <alerts@axisbank.com>`).
  final String sender;
  final String body;
  final String? subject;
  final DateTime receivedAt;
}
