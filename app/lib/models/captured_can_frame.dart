/// Represents a single recorded CAN frame during the learning session.
class CapturedCanFrame {
  final int timestampMs;
  final int canId;
  final List<int> data;

  const CapturedCanFrame({
    required this.timestampMs,
    required this.canId,
    required this.data,
  });

  String get hexId => '0x${canId.toRadixString(16).toUpperCase().padLeft(3, '0')}';
  String get hexData => data.map((b) => b.toRadixString(16).toUpperCase().padLeft(2, '0')).join(' ');
}
