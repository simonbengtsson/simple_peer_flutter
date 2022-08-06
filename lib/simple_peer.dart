// ignore_for_file: avoid_print

library simple_peer;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_webrtc/flutter_webrtc.dart';

final loopbackConstraints = <String, dynamic>{
  'mandatory': {},
  'optional': [
    {'DtlsSrtpKeyAgreement': true},
  ],
};

var activeConfig = <String, dynamic>{
  'iceServers': [
    {'url': 'stun:stun.l.google.com:19302'},
  ],
};

class Peer {
  late bool initiator;
  late RTCPeerConnection connection;
  RTCDataChannel? dataChannel;

  Function(String)? onSignal;
  Function(String)? onData;

  Peer({this.initiator = false});

  Future connect() async {
    var completer = Completer();

    connection = await createPeerConnection(activeConfig, loopbackConstraints);

    connection.onIceCandidate = (candidate) async {
      await Future.delayed(const Duration(seconds: 1));
      _signaling('iceCandidate', candidate.toMap());
    };

    if (initiator) {
      var dcInit = RTCDataChannelInit();
      dataChannel =
          await connection.createDataChannel('simple_peer_dc', dcInit);
      dataChannel!.onDataChannelState = (state) async {
        print('$initiator Data channel state $state');
        if (state == RTCDataChannelState.RTCDataChannelOpen) {
          completer.complete();
        }
      };
      dataChannel!.onMessage = (message) {
        onData!(message.text);
      };

      var offer = await connection.createOffer();
      await connection.setLocalDescription(offer);
      _signaling('offer', offer.toMap());
    } else {
      connection.onDataChannel = (channel) {
        dataChannel = channel;
        completer.complete();
        channel.onMessage = (message) {
          print('Message ${message.text}');
          onData!(message.text);
        };
      };
    }

    print('$initiator Waiting for data channel');

    await completer.future;
  }

  send(String data) {
    var message = RTCDataChannelMessage(data);
    dataChannel!.send(message);
  }

  signal(String data) async {
    var message = jsonDecode(data);
    String messageType = message['type'];
    var messageData = Map<String, dynamic>.from(message['data']);

    if (messageType == 'offer' || messageType == 'answer') {
      var sdp = messageData['sdp'];
      var type = messageData['type'];
      var description = RTCSessionDescription(sdp, type);
      connection.setRemoteDescription(description);
      print('$initiator Set $messageType');
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
    }
  }

  _signaling(String type, dynamic data) {
    var json = jsonEncode({
      'type': type,
      'data': data,
    });
    onSignal!.call(json);
  }
}

class ManuallyNegotiatedChannel {
  RTCPeerConnection? local;
  RTCPeerConnection? remote;

  testConnection() async {
    local = await createPeerConnection(activeConfig, loopbackConstraints);
    print('Created local connection');
    var dcInit = RTCDataChannelInit();
    dcInit.negotiated = true;
    dcInit.id = 1000;
    var localChannel = await local!.createDataChannel('sendChannel', dcInit);
    print('Created local data channel');

    local!.onRenegotiationNeeded = () {
      print('Local: onRenegotiationNeeded');
    };
    local!.onConnectionState = (state) {
      print('Local connection state ${state.name}');
    };
    List<RTCIceCandidate> localIceCandidates = [];
    local!.onIceCandidate = (candidate) {
      var type = candidate.candidate?.split(' ')[7];
      print("Local ice: $type");
      localIceCandidates.add(candidate);
    };

    remote = await createPeerConnection(activeConfig, loopbackConstraints);

    var dcInit2 = RTCDataChannelInit();
    dcInit2.negotiated = true;
    dcInit2.id = 1000;
    var remoteChannel = await remote!.createDataChannel('sendChannel', dcInit2);
    print('Created local data channel');

    remote!.onConnectionState = (state) {
      print('Remote connection state ${state.name}');
    };
    remote!.onIceGatheringState = (state) {};
    remote!.onIceConnectionState = (state) {};
    remote!.onRenegotiationNeeded = () {
      print('Remote onRenegotiationNeeded');
    };
    List<RTCIceCandidate> remoteIceCandidates = [];
    remote!.onIceCandidate = (candidate) {
      var type = candidate.candidate?.split(' ')[7];
      print("Remote ice: $type");
      remoteIceCandidates.add(candidate);
    };
    print('Create remote connection');

    var offer = await local!.createOffer();
    print('Created offer');

    await local!.setLocalDescription(offer);
    print('Set offer locally');

    await remote!.setRemoteDescription(offer);
    print('Set offer remotely');

    var answer = await remote!.createAnswer();
    print('Created answer');

    await remote!.setLocalDescription(answer);
    print('Set answer on remote');

    await local!.setRemoteDescription(answer);
    print('Set answer on local');

    remoteChannel.onDataChannelState = (state) async {
      print('Remote channel state $state');
    };

    localChannel.onDataChannelState = (state) async {
      print('Local channel state $state');
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        var message = RTCDataChannelMessage('Hello from local!');
        await localChannel.send(message);
        print('Sent local message');
      }
    };

    print('Waiting for all ice candidates...');
    await Future.delayed(const Duration(seconds: 2));

    remoteIceCandidates.forEach((it) => local!.addCandidate(it));
    localIceCandidates.forEach((it) => remote!.addCandidate(it));
    print('Added ice candidates');

    var completer = Completer();
    localChannel.onMessage = (message) {
      print('Got reply: ${message.text}');
      completer.complete('done');
    };

    remoteChannel.onMessage = (message) async {
      print(
          'Remote channel message: ${message.text} ${remoteChannel.state.toString()}');
      var reply = RTCDataChannelMessage('Hello from remote!');
      await remoteChannel.send(reply);
      print('Sent reply');
    };
    await completer.future;
    remote!.close();
    local!.close();
    await Future.delayed(const Duration(seconds: 2));
    print('Done');
  }
}
