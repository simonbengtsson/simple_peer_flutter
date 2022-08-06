import 'dart:io';

import 'command_runner.dart';

class VersionEditor {
  var pubspecFile = File('pubspec.yaml');

  List<int> bumpPatchVersion() {
    var oldVersion = readCurrentVersion();
    var newVersionParts = [oldVersion[0], oldVersion[1], oldVersion[2] + 1];

    var newVersion = newVersionParts.join('.');
    _replaceLine(pubspecFile, 'version: ${oldVersion.join('.')}',
        'version: $newVersion');

    var changelogFile = File('CHANGELOG.md');
    var changelog = changelogFile.readAsStringSync();
    if (!changelog.contains('#$newVersion')) {
      changelog = '#$newVersion\n$changelog';
      changelogFile.writeAsStringSync(changelog);
    }

    runLocalCommand('git reset');
    runLocalCommand('git add ${pubspecFile.path} ${changelogFile.path}');
    runLocalCommand('git commit -m v${newVersion}');
    runLocalCommand('git tag v${newVersion}');
    runLocalCommand('git push && git push --tags');

    print(newVersion);

    return newVersionParts;
  }

  List<int> readCurrentVersion() {
    var content = pubspecFile.readAsStringSync();
    var lines = content.split('\n');
    var index = lines.indexWhere((element) => element.startsWith('version:'));
    String versionLine = lines[index];
    var versionPart = versionLine.substring('version: '.length);
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
