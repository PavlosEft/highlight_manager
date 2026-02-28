import 'dart:io';
import 'dart:async';
import 'dart:convert';

Process? flutterProcess;
bool isConfirmingUndo = false;
bool isConfirmingGit = false;
bool isApplyingPatch = false;
Timer? debounceTimer;

void main() async {
  print('====================================================');
  print('🚀 HIGHLIGHT MANAGER - PRO DEV SERVER');
  print('====================================================');
  print('⌨️ ΣΥΝΤΟΜΕΥΣΕΙΣ ΠΛΗΚΤΡΟΛΟΓΙΟΥ:');
  print('  [r] - Hot Reload: Εφαρμογή αλλαγών κώδικα ακαριαία.');
  print('  [R] - Hot Restart: Πλήρης επανεκκίνηση της εφαρμογής.');
  print('  [c] - Create (OK) Zip: Μόνιμο Snapshot έξω, χωρίς να διαγράφεται.');
  print('  [g] - Git Push: Αυτόματο add, commit και push.');
  print('  [u] - Undo: Επαναφορά στην προηγούμενη έκδοση από το φάκελο Backups.');
  print('  [q] - Quit: Τερματισμός του Server και της εφαρμογής.');
  print('====================================================');
  
  final backupDir = Directory('Backups');
  if (!backupDir.existsSync()) backupDir.createSync();

  // Αισθητήρες για το κλείσιμο του παραθύρου (π.χ. με Ctrl+C) για να κλείνει και το Flutter
  ProcessSignal.sigint.watch().listen((_) {
    flutterProcess?.kill();
    exit(0);
  });

  print('⏳ Ξεκινάει το Flutter...');
  flutterProcess = await Process.start('flutter', ['run', '-d', 'windows'], runInShell: true);

  flutterProcess!.stdout.transform(utf8.decoder).listen((data) => stdout.write(data));
  flutterProcess!.stderr.transform(utf8.decoder).listen((data) => stderr.write(data));

  try {
    stdin.lineMode = false;
    stdin.echoMode = false;
  } catch (e) {}

  stdin.listen((event) {
    final input = utf8.decode(event).trim().toLowerCase();
    
    if (isConfirmingUndo) {
      handleUndoConfirmation(input);
      return;
    }
    
    if (isConfirmingGit) {
      handleGitConfirmation(input);
      return;
    }

    if (input == 'q') {
      print('\nΤερματισμός...');
      flutterProcess?.kill();
      exit(0);
    } else if (input == 'u') {
      isConfirmingUndo = true;
      stdout.write('\n⚠️ [UNDO] Είσαι σίγουρος ότι θες επαναφορά στην προηγούμενη έκδοση; (y/n): ');
    } else if (input == 'g') {
      isConfirmingGit = true;
      stdout.write('\n⚠️ [GIT] Να γίνει αυτόματο commit και push; (y/n): ');
    } else if (input == 'c') {
      createOkZip();
    } else {
      flutterProcess?.stdin.add(event);
    }
  });

  String lastClipboard = await getClipboard();

  void handleManualSave(FileSystemEvent event) {
    if (isConfirmingUndo || isApplyingPatch) return;
    
    final path = event.path.replaceAll('\\', '/');
    if (path.endsWith('.zip') || path.contains('Backups')) return;

    debounceTimer?.cancel();
    debounceTimer = Timer(const Duration(milliseconds: 800), () async {
      print('\n💾 [FILE WATCHER] Εντοπίστηκε αποθήκευση: ${event.path}');
      await manageZipsBeforePatch();
      await createCurrentZip();
      flutterProcess?.stdin.write('r');
    });
  }

  if (Directory('lib').existsSync()) {
    Directory('lib').watch(recursive: true).listen(handleManualSave);
  }
  if (Directory('tool').existsSync()) {
    Directory('tool').watch(recursive: true).listen(handleManualSave);
  }

  Timer.periodic(const Duration(seconds: 1), (timer) async {
    if (isConfirmingUndo || isConfirmingGit) return;

    final clipboard = await getClipboard();
    if (clipboard.isNotEmpty && clipboard != lastClipboard && clipboard.contains('<HM_PATCH>')) {
      lastClipboard = clipboard;
      print('\n✨ [AI PATCHER] Νέος κώδικας εντοπίστηκε!');
      
      isApplyingPatch = true; 

      bool success = applyPatch(clipboard);
      
      if (success) {
        await Future.delayed(const Duration(milliseconds: 300)); 
        await manageZipsBeforePatch();
        await createCurrentZip();
        print('🔄 [AI PATCHER] Hot Reload...');
        flutterProcess!.stdin.write('r'); 
      } else {
        print('⚠️ Η εφαρμογή ακυρώθηκε. Κανένα αρχείο ή Zip δεν πειράχτηκε.');
      }

      Future.delayed(const Duration(seconds: 1), () {
        isApplyingPatch = false;
      });
    }
  });
}

Future<String> getClipboard() async {
  try {
    final result = await Process.run('powershell', [
      '-NoProfile',
      '-Command',
      '[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; Get-Clipboard -Raw'
    ], stdoutEncoding: utf8);
    return result.stdout.toString().trim();
  } catch (e) {
    return '';
  }
}

Future<void> manageZipsBeforePatch() async {
  final rootFiles = Directory('.').listSync();
  for (var file in rootFiles) {
    // Εξαιρούνται τα αρχεία που περιέχουν το "(OK)" από την μετακίνηση
    if (file is File && file.path.contains('SourceCode_') && file.path.endsWith('.zip') && !file.path.contains('(OK)')) {
      final fileName = file.path.split(Platform.pathSeparator).last;
      await file.rename('Backups/$fileName');
      print('📦 Το παλιό snapshot μεταφέρθηκε στα Backups.');
    }
  }
}

Future<void> createCurrentZip() async {
  final now = DateTime.now();
  final timestamp = "${now.day}-${now.month}-${now.year}_${now.hour}-${now.minute}-${now.second}";
  final zipName = "SourceCode_$timestamp.zip";
  
  final targets = ['lib', 'tool', 'AI_INSTRUCTIONS.txt', 'pubspec.yaml', 'start_dev.bat', 'zip_source_code.bat'];
  final existingTargets = targets.where((t) => FileSystemEntity.typeSync(t) != FileSystemEntityType.notFound).toList();

  final args = ['-a', '-c', '-f', zipName, ...existingTargets];
  
  final result = await Process.run('tar.exe', args);
  
  if (result.exitCode == 0) {
    print('✅ Νέο Snapshot δημιουργήθηκε: $zipName');
  } else {
    print('❌ Σφάλμα κατά τη δημιουργία ZIP: ${result.stderr}');
  }
}

Future<void> createOkZip() async {
  print('\n⏳ Δημιουργία Μόνιμου (OK) Snapshot...');
  final now = DateTime.now();
  final timestamp = "${now.day}-${now.month}-${now.year}_${now.hour}-${now.minute}-${now.second}";
  final zipName = "SourceCode_$timestamp(OK).zip";
  
  final targets = ['lib', 'tool', 'AI_INSTRUCTIONS.txt', 'pubspec.yaml', 'start_dev.bat', 'zip_source_code.bat'];
  final existingTargets = targets.where((t) => FileSystemEntity.typeSync(t) != FileSystemEntityType.notFound).toList();

  final args = ['-a', '-c', '-f', zipName, ...existingTargets];
  
  final result = await Process.run('tar.exe', args);
  
  if (result.exitCode == 0) {
    print('✅ [OK] Νέο Μόνιμο Snapshot δημιουργήθηκε επιτυχώς: $zipName');
  } else {
    print('❌ Σφάλμα κατά τη δημιουργία (OK) ZIP: ${result.stderr}');
  }
}

void handleUndoConfirmation(String input) async {
  if (input == 'y') {
    print('\n⏳ Εκκίνηση Επαναφοράς (Undo)...');
    
    final rootFiles = Directory('.').listSync();
    for (var file in rootFiles) {
      // Καθαρίζουμε τα κανονικά zips αλλά αφήνουμε ανέπαφα τα (OK)
      if (file is File && file.path.contains('SourceCode_') && file.path.endsWith('.zip') && !file.path.contains('(OK)')) {
        file.deleteSync();
      }
    }

    final backupFiles = Directory('Backups').listSync()
        .where((f) => f.path.endsWith('.zip') && !f.path.contains('(OK)'))
        .toList();
    
    if (backupFiles.isEmpty) {
      print('❌ Δεν βρέθηκαν backups για επαναφορά.');
    } else {
      backupFiles.sort((a, b) => a.path.compareTo(b.path));
      final lastZip = backupFiles.last as File;
      final fileName = lastZip.path.split(Platform.pathSeparator).last;
      
      await lastZip.rename(fileName);
      await Process.run('tar.exe', ['-x', '-f', fileName]);
      
      print('⏪ Η επαναφορά ολοκληρώθηκε! (Αρχείο: $fileName)');
      flutterProcess!.stdin.write('r');
    }
  } else {
    print('\n🚫 Το Undo ακυρώθηκε.');
  }
  isConfirmingUndo = false;
}

void handleGitConfirmation(String input) async {
  if (input == 'y') {
    print('\n⏳ Εκτέλεση Git Push...');
    final now = DateTime.now();
    final timestamp = "${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute}:${now.second}";
    
    // Προσθήκη όλων των αλλαγών
    await Process.run('git', ['add', '.']);
    
    // Αυτόματο Commit
    final commitResult = await Process.run('git', ['commit', '-m', 'Auto commit from dev server - $timestamp']);
    print(commitResult.stdout);
    
    // Push
    final pushResult = await Process.run('git', ['push']);
    if (pushResult.exitCode == 0) {
      print('✅ [GIT] Το Push ολοκληρώθηκε με επιτυχία!');
    } else {
      print('❌ [GIT] Σφάλμα κατά το Push:\n${pushResult.stderr}');
    }
  } else {
    print('\n🚫 Το Git Push ακυρώθηκε.');
  }
  isConfirmingGit = false;
}

bool applyPatch(String rawClipboard) {
  try {
    final text = rawClipboard.replaceAll('\r\n', '\n'); 
    final patchRegex = RegExp(r'<HM_PATCH>(.*?)</HM_PATCH>', dotAll: true);
    final patches = patchRegex.allMatches(text);

    if (patches.isEmpty) return false;

    Map<String, String> fileContents = {};
    Map<String, String> newFileContents = {};

    for (var match in patches) {
      final patchContent = match.group(1)!;
      final fileMatch = RegExp(r'<FILE>(.*?)</FILE>').firstMatch(patchContent);
      final replaceMatch = RegExp(r'<REPLACE>\n?(.*?)\n?</REPLACE>', dotAll: true).firstMatch(patchContent);
      final withMatch = RegExp(r'<WITH>\n?(.*?)\n?</WITH>', dotAll: true).firstMatch(patchContent);

      if (fileMatch != null && replaceMatch != null && withMatch != null) {
        final filename = fileMatch.group(1)!.trim();
        final oldCode = replaceMatch.group(1)!;
        final newCode = withMatch.group(1)!;

        final file = File(filename);
        if (!file.existsSync()) {
          print('❌ Σφάλμα: Το αρχείο $filename δεν βρέθηκε. Ακύρωση αλλαγών.');
          return false;
        }

        if (!fileContents.containsKey(filename)) {
          fileContents[filename] = file.readAsStringSync().replaceAll('\r\n', '\n');
          newFileContents[filename] = fileContents[filename]!;
        }

        if (newFileContents[filename]!.contains(oldCode)) {
          newFileContents[filename] = newFileContents[filename]!.replaceFirst(oldCode, newCode);
        } else {
          print('❌ Σφάλμα: Δεν βρέθηκε ο κώδικας στο αρχείο $filename.');
          return false;
        }
      } else {
        return false;
      }
    }

    newFileContents.forEach((filename, content) {
      File(filename).writeAsStringSync(content);
      print('✅ Επιτυχής ενημέρωση: $filename');
    });

    return true;

  } catch (e) {
    print('❌ Απρόσμενο Σφάλμα: $e');
  }
  return false; 
}