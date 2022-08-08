// ignore_for_file: avoid_print

library simple_peer;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

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
      {initiator = false,
      verbose = false,
      Map<String, dynamic>? config,
      RTCDataChannelInit? dataChannelConfig}) async {
    var conf = config ?? _googleStunConfig;
    var connection = await createPeerConnection(conf, _loopbackConstraints);
    return Peer._init(connection, initiator, verbose, dataChannelConfig);
  }

  /// Call to start connection to remote peer.
  Future connect() async {
    var completer = Completer();

    connection.onIceCandidate = (candidate) async {
      var type = _initiator ? 'senderIceCandidate' : 'receiverIceCandidate';
      _signaling(type, candidate.toMap());
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
        if (message.isBinary) {
          onBinaryData?.call(message.binary);
        } else {
          onTextData?.call(message.text);
        }
        _print('Message received');
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
          if (message.isBinary) {
            onBinaryData?.call(message.binary);
          } else {
            onTextData?.call(message.text);
          }
          _print('Message received');
        };
      } else {
        connection.onDataChannel = (channel) {
          _dataChannel = channel;
          completer.complete();
          channel.onMessage = (message) {
            if (message.isBinary) {
              onBinaryData?.call(message.binary);
            } else {
              onTextData?.call(message.text);
            }
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
      var sdp = payload['sdp'];
      var type = payload['type'];
      var description = RTCSessionDescription(sdp, type);
      connection.setRemoteDescription(description);
      _print('Remote description set');
      if (info.isOffer) {
        var answer = await connection.createAnswer();
        await connection.setLocalDescription(answer);
        _signaling('answer', answer.toMap());
      }
    } else if (info.isIceCandidate) {
      var candidate = payload['candidate'];
      var sdpMid = payload['sdpMid'];
      var sdpMLineIndex = payload['sdpMLineIndex'];
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
      print('simple_peer $now $log${_initiator ? ' (initiator)' : ''}');
    }
  }
}
