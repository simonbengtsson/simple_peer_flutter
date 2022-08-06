// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:simple_peer/simple_peer.dart';

void main() {
  runApp(const App());
}

class App extends StatefulWidget {
  const App({Key? key}) : super(key: key);

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  @override
  void initState() {
    super.initState();
    reconnect();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
          body: Center(
        child: OutlinedButton(
            onPressed: reconnect, child: const Text('Reconnect')),
      )),
    );
  }

  reconnect() async {
    print('Connecting...');
    var peer1 = Peer(initiator: true);
    var peer2 = Peer();

    peer1.onSignal = (data) async {
      // when peer1 has signaling data, give it to peer2 somehow
      await peer2.signal(data);
    };

    peer2.onSignal = (data) async {
      // when peer2 has signaling data, give it to peer1 somehow
      await peer1.signal(data);
    };

    peer2.onData = (data) async {
      print("Got data from peer1: $data");
    };

    await Future.wait([
      peer1.connect(),
      peer2.connect(),
    ]);
    await peer1.send('hello!');
  }
}
