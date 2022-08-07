// ignore_for_file: avoid_print

library simple_peer;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

final loopbackConstraints = <String, dynamic>{
  'mandatory': {},
  'optional': [
    {'DtlsSrtpKeyAgreement': true},
  ],
};

var googleStunConfig = <String, dynamic>{
  'iceServers': [
    {'url': 'stun:stun.l.google.com:19302'},
  ],
};

class Peer {
  final bool _initiator;
  final bool _verbose;
  final Map<String, dynamic>? _config;
  final RTCDataChannelInit? _dataChannelConfig;

  late RTCDataChannel _dataChannel;

  /// Peer connection from flutter_webrtc used for transfers.
  /// For advanced use cases some of the methods and properties of this object
  /// is useful. It is only available after connect() has been called.
  late RTCPeerConnection connection;

  /// Called when the peer wants to send signaling data to the remote peer.
  ///
  /// It is the responsibility of the application developer (that's you!) to
  /// get this data to the other peer. This usually entails using a WebSocket
  /// signaling server. Then, simply call peer.signal(data) on the remote peer.
  /// Be sure to set this before calling connect to avoid missing any events.
  Function(String)? onSignal;

  /// Called when text channel message was received from the remote peer
  Function(String)? onTextData;

  /// Called when binary channel message was received from the remote peer
  Function(Uint8List)? onBinaryData;

  /// Creates a new Peer
  ///
  /// Use [initiator] to specify if this is the peer that should initiate
  /// the connection. For the webrtc [config] the default is to use publicly
  /// available stun server config is used. Although this works during
  /// development it could get taken down at any moment and does not support
  /// the turn protocol. If transfer is not working you can turn on logging
  /// with the [verbose] option.
  Peer(
      {initiator = false,
      verbose = false,
      Map<String, dynamic>? config,
      RTCDataChannelInit? dataChannelConfig})
      : _initiator = initiator,
        _config = config,
        _dataChannelConfig = dataChannelConfig,
        _verbose = verbose {
    _print('Peer created');
  }

  /// Call to start connection to remote peer.
  Future connect() async {
    var completer = Completer();

    var config = _config ?? googleStunConfig;

    connection = await createPeerConnection(config, loopbackConstraints);

    connection.onIceCandidate = (candidate) async {
      _signaling('iceCandidate', candidate.toMap());
    };

    var dcInit = _dataChannelConfig ?? RTCDataChannelInit();
    if (_initiator) {
      _dataChannel =
          await connection.createDataChannel('simple_peer_dc', dcInit);
      _dataChannel.onDataChannelState = (state) async {
        if (state == RTCDataChannelState.RTCDataChannelOpen) {
          completer.complete();
        }
      };
      _dataChannel.onMessage = (message) {
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
        _dataChannel.onDataChannelState = (state) async {
          if (state == RTCDataChannelState.RTCDataChannelOpen) {
            completer.complete();
          }
        };
        _dataChannel.onMessage = (message) {
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
    _dataChannel.send(message);
    _print('Sent text message of length ${text.length}');
  }

  /// Send binary data to remote peer. Call peer.connect() first to ensure
  /// data channel is ready.
  sendBinary(Uint8List bytes) async {
    var message = RTCDataChannelMessage.fromBinary(bytes);
    await _dataChannel.send(message);
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
  signal(String data) async {
    var message = jsonDecode(data);
    String messageType = message['type'];
    var messageData = Map<String, dynamic>.from(message['data']);

    if (messageType == 'offer' || messageType == 'answer') {
      var sdp = messageData['sdp'];
      var type = messageData['type'];
      var description = RTCSessionDescription(sdp, type);
      connection.setRemoteDescription(description);
      _print('Remote description set');
      if (messageType == 'offer') {
        var answer = await connection.createAnswer();
        await connection.setLocalDescription(answer);
        _signaling('answer', answer.toMap());
      }
    } else if (messageType == 'iceCandidate') {
      var candidate = messageData['candidate'];
      var sdpMid = messageData['sdpMid'];
      var sdpMLineIndex = messageData['sdpMLineIndex'];
      var iceCandidate = RTCIceCandidate(candidate, sdpMid, sdpMLineIndex);
      await connection.addCandidate(iceCandidate);
      var type = candidate?.split(' ')[7];
      _print('Ice candidate $type added');
    }
  }

  _signaling(String type, dynamic data) {
    var json = jsonEncode({
      'type': type,
      'data': data,
    });
    onSignal!.call(json);
  }

  _print(String log) {
    if (kDebugMode && _verbose) {
      var now = DateTime.now().millisecondsSinceEpoch;
      print('simple_peer $now $log${_initiator ? ' (initiator)' : ''}');
    }
  }
}
