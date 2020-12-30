import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:bencode_dart/bencode_dart.dart';
import 'package:dht/src/kademlia/id.dart';
import 'package:dht/src/kademlia/node.dart';
import 'package:dht/src/kademlia/peer_value.dart';

import 'krpc_message.dart';

enum EVENT { PING, GET_PEERS, FIND_NODE, ANNOUNCE_PEER }

const TIME_OUT_TIME = 15;

const Generic_Error = 201;
const Server_Error = 202;
const Protocal_Error = 203;
const UnknownMethod_Error = 204;

typedef KRPCResponseHandler = void Function(
    List<int> nodeId, InternetAddress address, int port, dynamic data);

typedef KRPCQueryHandler = void Function(List<int> nodeId, String transactionId,
    InternetAddress address, int port, dynamic data);

typedef KRPCErrorHandler = void Function(
    InternetAddress address, int port, int code, String msg);

abstract class KRPC {
  Future start();

  Future stop([dynamic reason]);

  ID get nodeId;

  bool get isStopped;

  int get port;

  /// Code	Description
  /// - `201`	Generic Error
  /// - `202`	Server Error
  /// - `203`	Protocol Error, such as a malformed packet, invalid arguments, or bad token
  /// - `204`	Method Unknown
  void error(String tid, InternetAddress address, int port,
      [int code = 201, String msg = 'Generic Error']);

  bool onError(KRPCErrorHandler handler);

  bool offError(KRPCErrorHandler handler);

  void ping(InternetAddress address, int port);

  bool onPong(KRPCResponseHandler handler);

  bool offPong(KRPCResponseHandler handler);

  void pong(String tid, InternetAddress address, int port);

  bool onPing(KRPCQueryHandler handler);

  bool offPing(KRPCQueryHandler handler);

  void findNode(String targetId, InternetAddress address, int port);

  bool onFindNodeResponse(KRPCResponseHandler handler);

  bool offFindNodeResponse(KRPCResponseHandler handler);

  void responseFindNode(
      String tid, List<Node> nodes, InternetAddress address, int port);

  bool onFindNodeRequest(KRPCQueryHandler handler);

  bool offFindNodeRequest(KRPCQueryHandler handler);

  void getPeers(String infoHash, InternetAddress address, int port);

  bool onGetPeersRequest(KRPCQueryHandler handler);

  bool offGetPeersRequest(KRPCQueryHandler handler);

  void responseGetPeers(String tid, String infoHash, InternetAddress address,
      int port, String token,
      {Iterable<Node> nodes, Iterable<PeerValue> peers});

  bool onGetPeersReponse(KRPCResponseHandler handler);

  bool offGetPeersResponse(KRPCResponseHandler handler);

  void announcePeer(String infoHash, int peerPort, String token,
      InternetAddress address, int port,
      [bool impliedPort = true]);

  bool onAnnouncePeerResponse(KRPCResponseHandler handler);

  bool offAnnouncePeerResponse(KRPCResponseHandler handler);

  void responseAnnouncePeer(String tid, InternetAddress address, int port);

  bool onAnnouncePeerRequest(KRPCQueryHandler handler);

  bool offAnnouncePeerRequest(KRPCQueryHandler handler);

  factory KRPC.newService(ID nodeId,
      {int timeout = TIME_OUT_TIME, int maxQuery = 24}) {
    var k = _KRPC(nodeId, timeout, maxQuery);
    return k;
  }
}

class _KRPC implements KRPC {
  int _globalTransactionId = 0;

  final _globalTransactionIdBuffer = Uint8List(2);

  bool _stopped = false;

  final ID _nodeId;

  final int _maxQuery;

  int _pendingQuery = 0;

  final int _timeOutTime;

  RawDatagramSocket _socket;

  final Map<String, EVENT> _transactionsMap = <String, EVENT>{};

  final Map<String, dynamic> _transactionsValues = <String, dynamic>{};

  final Map<String, Timer> _timeoutMap = <String, Timer>{};

  _KRPC(this._nodeId, this._timeOutTime, this._maxQuery);

  final Map<EVENT, Set<KRPCResponseHandler>> _responseHandlers =
      <EVENT, Set<KRPCResponseHandler>>{};

  final Map<EVENT, Set<KRPCQueryHandler>> _queryHandlers =
      <EVENT, Set<KRPCQueryHandler>>{};

  final Set<KRPCErrorHandler> _errorHandlers = <KRPCErrorHandler>{};

  StreamController _queryController;

  StreamSubscription _querySub;

  @override
  void error(String tid, InternetAddress address, int port,
      [int code = 201, String msg = 'Generic Error']) {
    if (isStopped || _socket == null) return;
    var message = errorMessage(tid, code, msg);
    _socket?.send(message, address, port);
  }

  @override
  bool offError(KRPCErrorHandler handler) {
    return _errorHandlers.remove(handler);
  }

  @override
  bool onError(KRPCErrorHandler handler) {
    return _errorHandlers.add(handler);
  }

  @override
  bool offFindNodeRequest(KRPCQueryHandler handler) {
    return _queryHandlers[EVENT.FIND_NODE]?.remove(handler);
  }

  @override
  bool onFindNodeRequest(KRPCQueryHandler handler) {
    _queryHandlers[EVENT.FIND_NODE] ??= <KRPCQueryHandler>{};
    return _queryHandlers[EVENT.FIND_NODE].add(handler);
  }

  @override
  bool offFindNodeResponse(KRPCResponseHandler handler) {
    return _responseHandlers[EVENT.FIND_NODE]?.remove(handler);
  }

  @override
  bool onFindNodeResponse(KRPCResponseHandler handler) {
    _responseHandlers[EVENT.FIND_NODE] ??= <KRPCResponseHandler>{};
    return _responseHandlers[EVENT.FIND_NODE].add(handler);
  }

  @override
  bool onPong(KRPCResponseHandler handler) {
    _responseHandlers[EVENT.PING] ??= <KRPCResponseHandler>{};
    return _responseHandlers[EVENT.PING].add(handler);
  }

  @override
  bool offPong(KRPCResponseHandler handler) {
    return _responseHandlers[EVENT.PING]?.remove(handler);
  }

  @override
  bool onPing(KRPCQueryHandler handler) {
    _queryHandlers[EVENT.PING] ??= <KRPCQueryHandler>{};
    return _queryHandlers[EVENT.PING].add(handler);
  }

  @override
  bool offPing(KRPCQueryHandler handler) {
    return _queryHandlers[EVENT.PING]?.remove(handler);
  }

  @override
  bool onGetPeersRequest(KRPCQueryHandler handler) {
    _queryHandlers[EVENT.GET_PEERS] ??= <KRPCQueryHandler>{};
    return _queryHandlers[EVENT.GET_PEERS].add(handler);
  }

  @override
  bool offGetPeersRequest(KRPCQueryHandler handler) {
    return _queryHandlers[EVENT.GET_PEERS]?.remove(handler);
  }

  @override
  bool offGetPeersResponse(KRPCResponseHandler handler) {
    return _responseHandlers[EVENT.GET_PEERS]?.remove(handler);
  }

  @override
  bool onGetPeersReponse(KRPCResponseHandler handler) {
    _responseHandlers[EVENT.GET_PEERS] ??= <KRPCResponseHandler>{};
    return _responseHandlers[EVENT.GET_PEERS].add(handler);
  }

  @override
  bool offAnnouncePeerRequest(KRPCQueryHandler handler) {
    return _queryHandlers[EVENT.ANNOUNCE_PEER]?.remove(handler);
  }

  @override
  bool offAnnouncePeerResponse(KRPCResponseHandler handler) {
    return _responseHandlers[EVENT.ANNOUNCE_PEER]?.remove(handler);
  }

  @override
  bool onAnnouncePeerRequest(KRPCQueryHandler handler) {
    _queryHandlers[EVENT.ANNOUNCE_PEER] ??= <KRPCQueryHandler>{};
    return _queryHandlers[EVENT.ANNOUNCE_PEER].add(handler);
  }

  @override
  bool onAnnouncePeerResponse(KRPCResponseHandler handler) {
    _responseHandlers[EVENT.ANNOUNCE_PEER] ??= <KRPCResponseHandler>{};
    return _responseHandlers[EVENT.ANNOUNCE_PEER].add(handler);
  }

  @override
  void responseAnnouncePeer(String tid, InternetAddress address, int port) {
    if (isStopped || _socket == null) return;
    var message = announcePeerResponse(tid, _nodeId.toString());
    _socket?.send(message, address, port);
  }

  @override
  void announcePeer(String infoHash, int peerPort, String token,
      InternetAddress address, int port,
      [bool impliedPort = true]) {
    if (isStopped || _socket == null) return;
    var tid = _recordTransaction(EVENT.ANNOUNCE_PEER);
    var message =
        announcePeerMessage(tid, _nodeId.toString(), infoHash, peerPort, token);
    _requestQuery(tid, message, address, port);
  }

  @override
  void pong(String tid, InternetAddress address, int port) {
    if (isStopped || _socket == null) return;
    var message = pongMessage(tid, _nodeId.toString());
    _socket?.send(message, address, port);
  }

  @override
  void responseFindNode(
      String tid, List<Node> nodes, InternetAddress address, int port) {
    if (isStopped || _socket == null) return;
    var message = findNodeResponse(tid, _nodeId.toString(), nodes);
    _socket?.send(message, address, port);
  }

  @override
  void responseGetPeers(String tid, String infoHash, InternetAddress address,
      int port, String token,
      {Iterable<Node> nodes, Iterable<PeerValue> peers}) {
    if (isStopped || _socket == null) return;
    var message = getPeersResponse(tid, _nodeId.toString(), token,
        nodes: nodes, peers: peers);
    _socket?.send(message, address, port);
  }

  @override
  void ping(InternetAddress address, int port) async {
    if (isStopped || _socket == null) return;
    var tid = _recordTransaction(EVENT.PING);
    var message = pingMessage(tid, _nodeId.toString());
    _requestQuery(tid, message, address, port);
  }

  @override
  void findNode(String targetId, InternetAddress address, int port) {
    if (isStopped || _socket == null) return;
    var tid = _recordTransaction(EVENT.FIND_NODE);
    var message = findNodeMessage(tid, _nodeId.toString(), targetId);
    _requestQuery(tid, message, address, port);
  }

  @override
  void getPeers(String infoHash, InternetAddress address, int port) {
    if (isStopped || _socket == null) return;
    var tid = _recordTransaction(EVENT.GET_PEERS);
    _transactionsValues[tid] = infoHash;
    var message = getPeersMessage(tid, _nodeId.toString(), infoHash);
    _requestQuery(tid, message, address, port);
  }

  void _requestQuery(String transacationId, List<int> message,
      InternetAddress address, int port) {
    _queryController ??= StreamController();
    _querySub ??= _queryController.stream.listen(_processQueryRequest);
    // _totalPending++;
    // print('目前共有 $_totalPending 个请求');
    _queryController?.add({
      'message': message,
      'address': address,
      'port': port,
      'transacationId': transacationId
    });
  }

  void _processQueryRequest(dynamic event) {
    _increasePendingQuery();
    var message = event['message'] as List<int>;
    var address = event['address'] as InternetAddress;
    var port = event['port'] as int;
    var tid = event['transacationId'] as String;
    // print('发送请求 $tid,目前pending请求数：$_pendingQuery');
    _timeoutMap[tid] =
        Timer(Duration(seconds: _timeOutTime), () => _fireTimeout(tid));
    _socket?.send(message, address, port);
  }

  String _recordTransaction(EVENT event) {
    var tid = createTransactionId();
    while (_transactionsMap[tid] != null) {
      tid = createTransactionId();
    }
    _transactionsMap[tid] = event;
    return tid;
  }

  void _fireTimeout(String id) {
    var event = _cleanTransaction(id);
    if (event != null) {
      _reducePendingQuery();
      // print('请求超时 $id,目前pending请求数：$_pendingQuery');
    }
  }

  EVENT _cleanTransaction(String id) {
    var event = _transactionsMap.remove(id);
    _timeoutMap[id]?.cancel();
    _timeoutMap.remove(id);
    _transactionsValues.remove(id);
    return event;
  }

  String createTransactionId() {
    ++_globalTransactionId;
    if (_globalTransactionId == 65535) {
      _globalTransactionId = 0;
    }
    ByteData.view(_globalTransactionIdBuffer.buffer)
        .setUint16(0, _globalTransactionId);
    return String.fromCharCodes(_globalTransactionIdBuffer);
  }

  @override
  Future start() async {
    _socket ??= await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _socket.listen((event) {
      if (event == RawSocketEvent.read) {
        var datagram = _socket.receive();
        Timer.run(() => _processReceiveData(
            datagram.address, datagram.port, datagram.data));
      }
    },
        onDone: () => stop('Remote/Local close the socket'),
        onError: (e) => stop(e));
    return _socket.port;
  }

  void _reducePendingQuery() {
    _pendingQuery -= 1;
    if (_pendingQuery < _maxQuery && _querySub != null && _querySub.isPaused) {
      _querySub?.resume();
    }
  }

  void _increasePendingQuery() {
    _pendingQuery += 1;
    if (_pendingQuery >= _maxQuery &&
        _querySub != null &&
        !_querySub.isPaused) {
      _querySub?.pause();
    }
  }

  void _processReceiveData(
      InternetAddress address, int port, List<int> bufferData) {
    _reducePendingQuery();

    // _totalPending--;
    // print('目前共有 $_totalPending 个请求');
    var data;
    try {
      data = decode(bufferData);
    } catch (e) {
      _fireError(Protocal_Error, null, 'Can\'t Decode Message', address, port);
      return;
    }
    if (data[TRANSACTION_KEY] == null || data[METHOD_KEY] == null) {
      _fireError(
          Protocal_Error, null, 'Data Don\'t Contains y or t', address, port);
      return;
    }
    var tid =
        String.fromCharCodes(data[TRANSACTION_KEY], 0, 2); //不就知道为什么有些Tid是4个字节的
    // print('请求响应 $tid ,目前pending请求数：$_pendingQuery');
    if (tid.length != 2) {
      _fireError(
          Protocal_Error, null, 'Incorret Transaction ID', address, port);
      return;
    }
    var additionalValues = _transactionsValues[tid];
    var event = _cleanTransaction(tid);
    var method = String.fromCharCodes(data[METHOD_KEY], 0, 1);
    if (method == RESPONSE_KEY) {
      var idBytes = data[RESPONSE_KEY][ID_KEY];
      if (idBytes == null) {
        _fireError(Protocal_Error, tid, 'Incorrect Node ID', address, port);
        return;
      }
      var r = data[RESPONSE_KEY];
      if (additionalValues != null && r != null) {
        r['__additional'] = additionalValues;
      }
      // 处理远程发送的response
      _fireResponse(event, idBytes, address, port, r);
      return;
    }
    if (method == QUERY_KEY) {
      var queryKey = String.fromCharCodes(data[QUERY_KEY]);
      if (!QUERY_KEYS.contains(queryKey)) {
        _fireError(
            Server_Error, tid, 'Unknown Query: $queryKey', address, port);
        return;
      }
      var idBytes = data[ARGUMENTS_KEY][ID_KEY];
      if (idBytes == null || idBytes.length != 20) {
        _fireError(Protocal_Error, tid, 'Incorrect Node ID', address, port);
        return;
      }
      EVENT event;
      if (queryKey == PING) {
        event = EVENT.PING;
      }
      if (queryKey == FIND_NODE) {
        event = EVENT.FIND_NODE;
      }
      if (queryKey == GET_PEERS) {
        event = EVENT.GET_PEERS;
      }
      if (queryKey == ANNOUNCE_PEER) {
        event = EVENT.ANNOUNCE_PEER;
      }
      log('收到一个Query请求: $event  ， 来自 $address : $port');
      var arguments = data[ARGUMENTS_KEY];
      _fireQuery(event, idBytes, tid, address, port, arguments);
      return;
    }
    if (method == ERROR_KEY) {
      var error = data[ERROR_KEY];
      if (error != null) {
        var code = error[0];
        var msg = String.fromCharCodes(error[1]);
        _getError(tid, address, port, code, msg);
      }
      return;
    }
    _fireError(
        UnknownMethod_Error, tid, 'Unknown Method: $method', address, port);
  }

  void _getError(
      String tid, InternetAddress address, int port, int code, String msg) {
    log('从 ${address.address}:$port 得到一个错误消息:',
        error: '[$code]$msg', name: runtimeType.toString());
    _errorHandlers.forEach((element) {
      Timer.run(() => element(address, port, code, msg));
    });
  }

  /// Code	Description
  /// - `201`	Generic Error
  /// - `202`	Server Error
  /// - `203`	Protocol Error, such as a malformed packet, invalid arguments, or bad token
  /// - `204`	Method Unknown
  void _fireError(
      int code, String tid, String msg, InternetAddress address, int port) {
    if (tid != null) {
      var event = _transactionsMap.remove(tid);
      _timeoutMap[tid]?.cancel();
      _timeoutMap.remove(tid);
      error(tid, address, port, code, msg);
    } else {
      log('UnSend Error:', error: '[$code]$msg');
    }
  }

  void _fireResponse(EVENT event, List<int> nodeIdBytes,
      InternetAddress address, int port, dynamic response) {
    var handlers = _responseHandlers[event];
    handlers?.forEach((handle) {
      Timer.run(() => handle(nodeIdBytes, address, port, response));
    });
  }

  void _fireQuery(EVENT event, List<int> nodeIdBytes, String transactionId,
      InternetAddress address, int port, dynamic arguments) {
    var handlers = _queryHandlers[event];
    handlers?.forEach((handle) {
      Timer.run(
          () => handle(nodeIdBytes, transactionId, address, port, arguments));
    });
  }

  @override
  Future stop([dynamic reason]) async {
    if (_stopped) return;
    _stopped = true;
    log('KRPC stopped , reason:', error: reason, name: runtimeType.toString());

    _socket?.close();
    _socket = null;
    _responseHandlers.clear();
    _queryHandlers.clear();
    _errorHandlers.clear();
    _globalTransactionId = 0;
    _globalTransactionIdBuffer[0] = 0;
    _globalTransactionIdBuffer[1] = 0;
    _pendingQuery = 0;
    _transactionsMap.clear();
    _transactionsValues.clear();
    _timeoutMap.forEach((key, timer) {
      timer?.cancel();
    });
    _timeoutMap.clear();
    await _queryController?.close();
    _queryController = null;

    await _querySub?.cancel();
    _querySub = null;
  }

  @override
  bool get isStopped => _stopped;

  @override
  ID get nodeId => _nodeId;

  @override
  int get port => _socket?.port;
}
