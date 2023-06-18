// ignore_for_file: avoid_print

library simple_peer;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class SignalingInfo {
  bool get isOffer {
    return type == 'offer';
  }

  bool get isAnswer {
    return type == 'answer';
  }

  bool get isIceCandidate {
    return ['iceCandidate', 'senderIceCandidate', 'receiverIceCandidate']
        .contains(type);
  }

  final String type;
  final dynamic payload;

  SignalingInfo(this.type, this.payload);

  String encode() {
    var json = jsonEncode({
      'type': type,
      'payload': payload,
    });
    return json;
  }
}

class Peer {
  final bool _initiator;
  final bool _verbose;
  final RTCDataChannelInit? _dataChannelConfig;

  /// Peer connection from flutter_webrtc used for transfers.
  /// For advanced use cases some of the methods and properties of this object
  /// is useful. It is only available after connect() has been called.
  RTCPeerConnection connection;

  RTCDataChannel? _dataChannel;

  final List<RTCIceCandidate> _pendingIceCandidates = [];

  /// Called when the peer wants to send signaling data to the remote peer.
  ///
  /// It is the responsibility of the application developer (that's you!) to
  /// get this data to the other peer. This usually entails using a WebSocket
  /// signaling server. Then, simply call peer.signal(data) on the remote peer.
  /// Be sure to set this before calling connect to avoid missing any events.
  Function(SignalingInfo)? onSignal;

  /// Called when text channel message was received from the remote peer
  Function(String)? onTextData;

  /// Called when binary channel message was received from the remote peer
  Function(Uint8List)? onBinaryData;

  static final _loopbackConstraints = <String, dynamic>{
    'mandatory': {},
    'optional': [
      {'DtlsSrtpKeyAgreement': true},
    ],
  };

  static final _googleStunConfig = <String, dynamic>{
    'iceServers': [
      {'url': 'stun:stun.l.google.com:19302'},
    ],
  };

  Peer._init(this.connection, this._initiator, this._verbose,
      this._dataChannelConfig) {
    _print('Peer created');
  }

  /// Creates a new Peer
  ///
  /// Use [initiator] to specify if this is the peer that should initiate
  /// the connection. For the webrtc [config] the default is to use publicly
  /// available stun server config is used. Although this works during
  /// development it could get taken down at any moment and does not support
  /// the turn protocol. If transfer is not working you can turn on logging
  /// with the [verbose] option.
  static Future<Peer> create(
      {bool initiator = false,
      bool verbose = false,
      Map<String, dynamic>? config,
      RTCDataChannelInit? dataChannelConfig}) async {
    var conf = config ?? _googleStunConfig;
    var connection = await createPeerConnection(conf, _loopbackConstraints);
    return Peer._init(connection, initiator, verbose, dataChannelConfig);
  }

  postIceCandidates() async {
    var pending = [..._pendingIceCandidates];
    _pendingIceCandidates.clear();

    var local = await connection.getLocalDescription();
    var remote = await connection.getRemoteDescription();

    // Don't send ice candidates until both offer and answer is set
    // This is mainly to simplify for clients so they don't have to handle the
    // case of ice candidates getting received before offer on non initiator.
    if (local != null && remote != null) {
      for (var candidate in pending) {
        var type = _initiator ? 'senderIceCandidate' : 'receiverIceCandidate';
        await _signaling(type, candidate.toMap());
      }
    } else {
      _pendingIceCandidates.addAll(pending);
    }
  }

  _notifyDataMessages(RTCDataChannelMessage message) async {
    if (message.isBinary) {
      _print('Binary message received');
      await onBinaryData?.call(message.binary);
    } else {
      _print('Text message received');
      await onTextData?.call(message.text);
    }
  }

  /// Call to start connection to remote peer.
  connect() async {
    var completer = Completer();

    connection.onIceCandidate = (candidate) async {
      _pendingIceCandidates.add(candidate);
      await postIceCandidates();
    };

    var dcInit = _dataChannelConfig ?? RTCDataChannelInit();
    if (_initiator) {
      _dataChannel =
          await connection.createDataChannel('simple_peer_dc', dcInit);
      _dataChannel!.onDataChannelState = (state) async {
        if (state == RTCDataChannelState.RTCDataChannelOpen) {
          completer.complete();
        }
      };
      _dataChannel!.onMessage = (message) {
        _notifyDataMessages(message);
      };

      var offer = await connection.createOffer();
      await connection.setLocalDescription(offer);
      _signaling('offer', offer.toMap());
    } else {
      if (dcInit.negotiated) {
        _dataChannel =
            await connection.createDataChannel('simple_peer_dc', dcInit);
        _dataChannel!.onDataChannelState = (state) async {
          if (state == RTCDataChannelState.RTCDataChannelOpen) {
            completer.complete();
          }
        };
        _dataChannel!.onMessage = (message) {
          _notifyDataMessages(message);
        };
      } else {
        connection.onDataChannel = (channel) {
          _dataChannel = channel;
          completer.complete();
          channel.onMessage = (message) {
            _notifyDataMessages(message);
          };
        };
      }
    }

    await completer.future;

    // If signaling is really quick the data channel is sometimes reported as
    // ready before the remote peer data channel is ready. This could lead to
    // the initial messages to be dropped.
    await Future.delayed(const Duration(milliseconds: 20));

    _print('Peer was connected');
  }

  /// Send text to remote peer. Call peer.connect() first to ensure
  /// data channel is ready.
  sendText(String text) {
    var message = RTCDataChannelMessage(text);
    _dataChannel!.send(message);
    _print('Sent text message of length ${text.length}');
  }

  /// Send binary data to remote peer. Call peer.connect() first to ensure
  /// data channel is ready.
  sendBinary(Uint8List bytes) async {
    var message = RTCDataChannelMessage.fromBinary(bytes);
    await _dataChannel!.send(message);
    _print('Sent binary message of size ${bytes.length}');
  }

  /// Call this method whenever signaling data is received from remote peer
  ///
  // The data will encapsulate a webrtc offer, answer, or ice candidate. These
  // messages help the peers to eventually establish a direct connection to
  // each other. The contents of these strings are an implementation detail
  // that can be ignored by the user of this module; simply pass the data
  // from 'signal' events to the remote peer and call peer.signal(data) to
  // get connected.
  signal(SignalingInfo info) async {
    var payload = info.payload;

    if (info.isOffer || info.isAnswer) {
      var sdp = payload['sdp'] as String?;
      var type = payload['type'] as String?;
      var description = RTCSessionDescription(sdp, type);
      connection.setRemoteDescription(description);
      _print('Remote description set');
      if (info.isOffer) {
        var answer = await connection.createAnswer();
        await connection.setLocalDescription(answer);
        await _signaling('answer', answer.toMap());
      }
      await postIceCandidates();
    } else if (info.isIceCandidate) {
      var candidate = payload['candidate'] as String?;
      var sdpMid = payload['sdpMid'] as String?;
      var sdpMLineIndex = payload['sdpMLineIndex'] as int?;
      var iceCandidate = RTCIceCandidate(candidate, sdpMid, sdpMLineIndex);
      await connection.addCandidate(iceCandidate);
      var type = candidate?.split(' ')[7];
      _print('Ice candidate $type added');
    }
  }

  _signaling(String type, dynamic data) {
    var info = SignalingInfo(type, data);
    onSignal!.call(info);
  }

  _print(String log) {
    if (kDebugMode && _verbose) {
      var now = DateTime.now().millisecondsSinceEpoch;
      print('simple_peer $now $log (i: $_initiator)');
    }
  }
}
