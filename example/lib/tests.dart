// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:simple_peer/simple_peer.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_webrtc/flutter_webrtc.dart';

void main() {
  runApp(const App());
}

class Tester {
  testAll() async {
    print('Running tests...');
    await testDataChannel();
    await testNegotiatedDataChannel();
    await testDelayedConnection();
    print('Done');
  }

  testDataChannel() async {
    var testCompleter = Completer();
    testCompleter.future.timeout(const Duration(seconds: 5));
    print('Running testDataChannel...');

    var peer1 = await Peer.create(initiator: true);
    var peer2 = await Peer.create();

    peer1.onSignal = (message) async {
      await peer2.signal(message);
    };

    peer2.onSignal = (data) async {
      await peer1.signal(data);
    };

    peer2.onTextData = (data) async {
      print('Text message received');
      peer1.sendBinary(Uint8List.fromList([5, 5, 5, 5]));
    };

    peer2.onBinaryData = (data) async {
      print('Binary message received');
      testCompleter.complete();
    };

    peer2.connect();
    await peer1.connect();

    await peer1.sendText('hello!');

    await testCompleter.future;
    print('Completed testDataChannel');
  }

  testNegotiatedDataChannel() async {
    var testCompleter = Completer();
    testCompleter.future.timeout(const Duration(seconds: 5));
    print('Running testNegotiatedDataChannel...');

    var config = RTCDataChannelInit();
    config.negotiated = true;
    config.id = 1000;
    var peer1 = await Peer.create(initiator: true, dataChannelConfig: config);
    var peer2 = await Peer.create(dataChannelConfig: config);

    peer1.onSignal = (data) async {
      await peer2.signal(data);
    };

    peer2.onSignal = (data) async {
      await peer1.signal(data);
    };

    peer2.onTextData = (data) async {
      testCompleter.complete();
    };

    peer2.connect();
    await peer1.connect();

    await peer1.sendText('hello!');

    await testCompleter.future;
    print('Completed testNegotiatedDataChannel');
  }

  testDelayedConnection() async {
    var testCompleter = Completer();
    testCompleter.future.timeout(const Duration(seconds: 5));
    print('Running testDelayedConnection...');

    var peer1 = await Peer.create(initiator: true);
    var peer2 = await Peer.create();

    peer1.onSignal = (data) async {
      await Future.delayed(const Duration(seconds: 1));
      await peer2.signal(data);
    };

    peer2.onSignal = (data) async {
      await Future.delayed(const Duration(seconds: 1));
      await peer1.signal(data);
    };

    peer2.onTextData = (data) async {
      testCompleter.complete();
    };

    peer2.connect();
    await peer1.connect();

    await peer1.sendText('hello!');

    await testCompleter.future;
    print('Completed testDelayedConnection');
  }
}

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  @override
  void initState() {
    super.initState();
    Tester().testAll();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
          body: Center(
        child: OutlinedButton(
            onPressed: Tester().testAll, child: const Text('Run Tests')),
      )),
    );
  }
}
