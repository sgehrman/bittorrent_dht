import 'dart:io';

abstract class KRPCEvent {}

class KRPCResponseEvent implements KRPCEvent {
  final List<int> nodeId;
  final InternetAddress address;
  final int port;
  final dynamic data;
  KRPCResponseEvent({
    required this.nodeId,
    required this.address,
    required this.port,
    required this.data,
  });
}

class PingResponse extends KRPCResponseEvent {
  PingResponse(
      {required List<int> nodeId,
      required InternetAddress address,
      required int port,
      required data})
      : super(nodeId: nodeId, address: address, port: port, data: data);
}

class GetPeersResponse extends KRPCResponseEvent {
  GetPeersResponse(
      {required List<int> nodeId,
      required InternetAddress address,
      required int port,
      required data})
      : super(nodeId: nodeId, address: address, port: port, data: data);
}

class FindNodeResponse extends KRPCResponseEvent {
  FindNodeResponse(
      {required List<int> nodeId,
      required InternetAddress address,
      required int port,
      required data})
      : super(nodeId: nodeId, address: address, port: port, data: data);
}

class AnnouncePeerResponse extends KRPCResponseEvent {
  AnnouncePeerResponse(
      {required List<int> nodeId,
      required InternetAddress address,
      required int port,
      required data})
      : super(nodeId: nodeId, address: address, port: port, data: data);
}

class ErrorEvent implements KRPCEvent {
  InternetAddress address;
  int port;
  int code;
  String msg;
  ErrorEvent({
    required this.address,
    required this.port,
    required this.code,
    required this.msg,
  });
}

class KRPCQueryEvent implements KRPCEvent {
  List<int> nodeId;
  String transactionId;
  InternetAddress address;
  int port;
  dynamic data;
  KRPCQueryEvent({
    required this.nodeId,
    required this.transactionId,
    required this.address,
    required this.port,
    required this.data,
  });
}

class PingQuery extends KRPCQueryEvent {
  PingQuery(
      {required List<int> nodeId,
      required String transactionId,
      required InternetAddress address,
      required int port,
      required data})
      : super(
            nodeId: nodeId,
            transactionId: transactionId,
            address: address,
            port: port,
            data: data);
}

class GetPeersQuery extends KRPCQueryEvent {
  GetPeersQuery(
      {required List<int> nodeId,
      required String transactionId,
      required InternetAddress address,
      required int port,
      required data})
      : super(
            nodeId: nodeId,
            transactionId: transactionId,
            address: address,
            port: port,
            data: data);
}

class FindNodeQuery extends KRPCQueryEvent {
  FindNodeQuery(
      {required List<int> nodeId,
      required String transactionId,
      required InternetAddress address,
      required int port,
      required data})
      : super(
            nodeId: nodeId,
            transactionId: transactionId,
            address: address,
            port: port,
            data: data);
}

class AnnouncePeersQuery extends KRPCQueryEvent {
  AnnouncePeersQuery(
      {required List<int> nodeId,
      required String transactionId,
      required InternetAddress address,
      required int port,
      required data})
      : super(
            nodeId: nodeId,
            transactionId: transactionId,
            address: address,
            port: port,
            data: data);
}
