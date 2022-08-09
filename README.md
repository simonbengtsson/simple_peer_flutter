Simple WebRTC. Wraps [flutter_webrtc](https://github.com/flutter-webrtc/flutter-webrtc) similar to [simple-peer](https://github.com/feross/simple-peer)

IMPORTANT: Right now this library only supports data channels (and not media). Contributions welcome!

## Getting started

For now, see more information on how to in either flutter_webrtc or simple-peer.

## Roadmap

- Support media (in addition to currently supported data channels)
- Support batching large data (such as sending files byte by byte)

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

peer2.connect();
await peer1.connect();

await peer1.send('hello!');
```
