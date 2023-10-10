import 'package:dtorrent_common/dtorrent_common.dart';

abstract class DHTEvent {}

class DHTError implements DHTEvent {
  final int code;
  final String message;
  DHTError({
    required this.code,
    required this.message,
  });
}

class NewPeerEvent implements DHTEvent {
  final CompactAddress address;
  final String infoHash;
  NewPeerEvent({
    required this.address,
    required this.infoHash,
  });
}
