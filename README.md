Simple WebRTC. Wraps [flutter_webrtc](https://github.com/flutter-webrtc/flutter-webrtc) similar to [simple-peer](https://github.com/feross/simple-peer)

## Getting started

Read more about how to get started with webrtc in [flutter_webrtc](https://github.com/flutter-webrtc/flutter-webrtc) or the javascript [simple-peer](https://github.com/feross/simple-peer)

## Currently unsupported features (contributions welcome!)

- Media channels (only data channels supported right now)
- Batching of large data ie such as sending files byte by byte (needs to be handled in calling application right now)

## Usage

```dart
var peer1 = Peer(initiator: true);
var peer2 = Peer();

peer1.onSignal = (data) async {
  // When peer1 has signaling data, give it to peer2 somehow
  // https://developer.mozilla.org/en-US/docs/Web/API/WebRTC_API/Signaling_and_video_calling#the_signaling_server
  await peer2.signal(data);
};

peer2.onSignal = (data) async {
  // When peer2 has signaling data, give it to peer1 somehow
  // https://developer.mozilla.org/en-US/docs/Web/API/WebRTC_API/Signaling_and_video_calling#the_signaling_server
  await peer1.signal(data);
};

peer2.onData = (data) async {
  print(data); // hello!
};

peer2.connect();
await peer1.connect();

await peer1.send('hello!');
```

# Example

Run the example/main.dart application and check that connection worked in console.

## Release guide (for contributors)

- Test by opening example and check logs that it works
- Update CHANGELOG.md + pubspec.yml version
- Run `flutter pub publish`
