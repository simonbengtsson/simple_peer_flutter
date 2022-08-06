import 'dart:io';

import 'command_runner.dart';

class VersionEditor {
  var pubspecFile = File('pubspec.yaml');

  List<int> bumpPatchVersion() {
    var oldVersion = readCurrentVersion();
    var newVersion = [oldVersion[0], oldVersion[1], oldVersion[2] + 1];

    _replaceLine(
        pubspecFile,
        'version: ${oldVersion.join('.')}+${oldVersion[2]}',
        'version: ${newVersion.join('.')}+${newVersion[2]}');

    runLocalCommand('git reset');
    runLocalCommand('git add ${pubspecFile.path}');
    runLocalCommand('git commit -m v${newVersion.join('.')}');
    runLocalCommand('git tag v${newVersion.join('.')}');
    runLocalCommand('git push && git push --tags');
    runLocalCommand('dart pub publish');

    print(newVersion.join('.'));

    return newVersion;
  }

  List<int> readCurrentVersion() {
    var content = pubspecFile.readAsStringSync();
    var lines = content.split('\n');
    var index = lines.indexWhere((element) => element.startsWith('version:'));
    String versionLine = lines[index];
    var versionPart =
        versionLine.substring('version: '.length, versionLine.indexOf('+'));
    var parts = versionPart.split('.').map((it) => int.parse(it));
    return parts.toList();
  }

  _replaceLine(File file, Pattern lineMatch, String newLine) {
    var runnerFileContents = file.readAsStringSync();
    var lines = runnerFileContents.split('\n');
    var indexes = lines.where((element) => element.startsWith(lineMatch));
    if (indexes.length != 1) {
      throw Exception(
          'Not matching 1 line. Matches: ${indexes.length} Wanted: $lineMatch');
    }
    var index = lines.indexWhere((element) => element.startsWith(lineMatch));
    lines[index] = newLine;
    file.writeAsStringSync(lines.join('\n'));
  }
}
