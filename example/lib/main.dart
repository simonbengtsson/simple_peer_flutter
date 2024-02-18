import 'package:flutter/material.dart';
import 'package:simple_peer/simple_peer.dart';

void main() {
  runApp(const App());
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
    var peer1 = await Peer.create(initiator: true);
    var peer2 = await Peer.create();

    peer1.onSignal = (data) async {
      // when peer1 has signaling data, give it to peer2 somehow
      await peer2.signal(data);
    };

    peer2.onSignal = (data) async {
      // when peer2 has signaling data, give it to peer1 somehow
      await peer1.signal(data);
    };

    peer2.onTextData = (data) async {
      print("Got data from peer1: $data");
    };

    peer2.connect();
    await peer1.connect();

    await peer1.sendText('hello!');
  }
}
