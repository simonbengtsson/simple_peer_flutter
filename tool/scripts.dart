// ignore_for_file: avoid_print

import 'version_editor.dart';

main(List<String> args) async {
  var script = args.isEmpty ? null : args.first;
  if (script == 'release') {
    VersionEditor().bumpPatchVersion();
    //runLocalCommand('dart pub publish');
  } else {
    print('Invalid script: $script');
  }
}
