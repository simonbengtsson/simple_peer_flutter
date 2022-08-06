Simple WebRTC. Wraps [flutter_webrtc](https://github.com/flutter-webrtc/flutter-webrtc) similar to [simple-peer](https://github.com/feross/simple-peer)

IMPORTANT: Although the example works this plugin is just a proof of concept that only support data channels and does not support specifying any options

## Getting started

For now, see more information on how to in either flutter_webrtc or simple-peer.

## Usage

```dart
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
```
