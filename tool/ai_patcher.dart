import 'dart:io';
import 'dart:async';
import 'dart:convert';

bool isConfirmingUndo = false;
bool isConfirmingGit = false;

void printMenu() {
  print('====================================================');
  print('🤖 AI PATCHER - Ενεργός (Ακούει το Clipboard)');
  print('====================================================');
  print('ΣΥΝΤΟΜΕΥΣΕΙΣ ΠΛΗΚΤΡΟΛΟΓΙΟΥ (Μόνο σε αυτό το παράθυρο):');
  print('  [c] - Create (OK) Zip: Μόνιμο Snapshot έξω, χωρίς να διαγράφεται.');
  print('  [g] - Git Push: Αυτόματο add, commit και push.');
  print('  [u] - Undo: Επαναφορά στην προηγούμενη έκδοση από το φάκελο Backups.');
  print('-----------------------------------------------------');
  print('Περιμένω για αντιγραφή κώδικα (Ctrl+C)...');
}

void playDetectSound() {
  if (Platform.isWindows) {
    Process.run('powershell', ['-c', '[console]::beep(600, 100)']);
  }
}

void playSound(bool success) {
  if (Platform.isWindows) {
    if (success) {
      Process.run('powershell', ['-c', '[console]::beep(1000, 150); [console]::beep(1200, 150)']);
    } else {
      Process.run('powershell', ['-c', '[console]::beep(300, 500)']);
    }
  } else {
    stdout.write('\x07');
  }
}

void main() async {
  printMenu();
  
  final backupDir = Directory('Backups');
  if (!backupDir.existsSync()) backupDir.createSync(); 

  try {
    if (stdin.hasTerminal) {
      stdin.lineMode = false;
      stdin.echoMode = false;
    }
  } catch (_) {}

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

    if (input == 'c') {
      createOkZip();
    } else if (input == 'g') {
      isConfirmingGit = true;
      stdout.write('\n⚠️ [GIT] Να γίνει αυτόματο commit και push; (y/n): ');
    } else if (input == 'u') {
      isConfirmingUndo = true;
      stdout.write('\n⚠️ [UNDO] Είσαι σίγουρος ότι θες επαναφορά στην προηγούμενη έκδοση; (y/n): ');
    } else if (input == 'h' || input == '?') {
      printMenu();
    }
  });

  String lastClipboardText = '';

  void scheduleNextCheck() {
    Timer(const Duration(seconds: 1), () async {
      final rawData = await getClipboard();

      // 1. Ελέγχουμε αν άλλαξε το clipboard
      if (rawData.isNotEmpty && rawData != lastClipboardText) {
        lastClipboardText = rawData;
        
        // 2. Ελέγχουμε αν είναι Patch ΚΑΙ δεν το έχουμε ήδη τρέξει
        if (rawData.contains('<HM_PATCH>') && !rawData.contains('//[HM_SEEN]')) {
          playDetectSound();
          print('\n⏳ Patch Detected...');
          bool success = applyPatch(rawData);
          
          playSound(success);
          
          if (success) {
            print('✅ Patch OK! Creating snapshot...');
            
            await manageZipsBeforePatch();
            await createCurrentZip(); 

            final actionRegex = RegExp(r'<ACTION>(.*?)</ACTION>', dotAll: true);
            final actionMatch = actionRegex.firstMatch(rawData);
            String action = 'RELOAD'; 
            if (actionMatch != null) {
              action = actionMatch.group(1)!.trim().toUpperCase();
            }

            try {
              File('tool/.trigger_reload').writeAsStringSync('${DateTime.now().toIso8601String()}|$action');
            } catch (_) {}
            print('🚀 Action: $action.');
          } else {
            print('❌ Patch Failed!');
          }

          // Μαρκάρουμε το clipboard ώστε να μην το ξανατρέξει κατά λάθος
          try {
            final tempFile = File('tool/.temp_clip.txt');
            tempFile.writeAsStringSync(rawData + '\n//[HM_SEEN]');
            await Process.run('powershell', ['-NoProfile', '-Command', 'Get-Content tool/.temp_clip.txt -Raw | Set-Clipboard']);
            try { tempFile.deleteSync(); } catch (_) {}
          } catch (_) {}
        }
      }
      
      scheduleNextCheck();
    });
  }

  scheduleNextCheck();
  
  ProcessSignal.sigint.watch().listen((_) {
    exit(0);
  });
}

Future<String> getClipboard() async {
  try {
    // Αναγκάζουμε το PowerShell να επιστρέψει τα δεδομένα σε UTF-8
    final result = await Process.run('powershell', [
      '-NoProfile',
      '-Command',
      '[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; Get-Clipboard -Raw'
    ], stdoutEncoding: utf8, runInShell: true);
    
    return result.stdout.toString().trim();
  } catch (e) {
    return '';
  }
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
        
        // ΑΣΦΑΛΗΣ ΚΑΘΑΡΙΣΜΟΣ: Μετατροπή Non-Breaking Spaces (\xA0) σε κανονικά κενά
        final oldCode = replaceMatch.group(1)!.replaceAll(RegExp(r'\xA0'), ' ');
        final newCode = withMatch.group(1)!.replaceAll(RegExp(r'\xA0'), ' ');

        final file = File(filename);
        if (!file.existsSync()) {
          print('❌ Σφάλμα: Δεν βρέθηκε το αρχείο $filename.');
          return false;
        }

        if (!fileContents.containsKey(filename)) {
          // Διαβάζουμε το αρχείο και καθαρίζουμε κι εδώ τα πιθανά κρυφά κενά
          fileContents[filename] = file.readAsStringSync()
              .replaceAll('\r\n', '\n')
              .replaceAll(RegExp(r'\xA0'), ' ');
          newFileContents[filename] = fileContents[filename]!;
        }

        // 1η Δοκιμή: Απόλυτη ταύτιση
        if (newFileContents[filename]!.contains(oldCode)) {
          newFileContents[filename] = newFileContents[filename]!.replaceFirst(oldCode, newCode);
        } 
        else {
          // 2η Δοκιμή (Fallback): Αφαίρεση κενών γραμμών μόνο πάνω-κάτω (trim)
          final trimmedOldCode = oldCode.trim();
          if (newFileContents[filename]!.contains(trimmedOldCode)) {
            newFileContents[filename] = newFileContents[filename]!.replaceFirst(trimmedOldCode, newCode.trim());
          } else {
            print('❌ Σφάλμα: Δεν βρέθηκε ο κώδικας στο $filename.');
            return false;
          }
        }
      } else {
          return false;
      }
    }

    // Αποθήκευση μόνο αν όλα τα patches του clipboard πέρασαν επιτυχώς
    newFileContents.forEach((filename, content) {
      File(filename).writeAsStringSync(content);
    });

    return true;

  } catch (e) {
    print('❌ Απρόσμενο Σφάλμα στο Patcher: $e');
  }
  return false; 
}

Future<void> manageZipsBeforePatch() async {
  final rootFiles = Directory('.').listSync();
  for (var file in rootFiles) {
    if (file is File && file.path.contains('SourceCode_') && file.path.endsWith('.zip') && !file.path.contains('(OK)')) {
      final fileName = file.path.split(Platform.pathSeparator).last;
      await file.rename('Backups/$fileName');
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
  
  final result = await Process.run('tar.exe', args, runInShell: true);
  
  if (result.exitCode == 0) {
    print('📦 Auto-Zip: OK ($zipName)');
  } else {
    print('❌ Auto-Zip Failed: ${result.stderr}');
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
  
  final result = await Process.run('tar.exe', args, runInShell: true);
  
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
      backupFiles.sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));
      final lastZip = backupFiles.last as File;
      final fileName = lastZip.path.split(Platform.pathSeparator).last;
      
      await lastZip.rename(fileName);
      await Process.run('tar.exe', ['-x', '-f', fileName], runInShell: true); 
      
      final dirs = [Directory('lib'), Directory('tool')];
      for (var dir in dirs) {
        if (dir.existsSync()) {
          for (var file in dir.listSync(recursive: true).whereType<File>()) {
            if (file.path.endsWith('.dart')) {
              try { file.setLastModifiedSync(DateTime.now()); } catch (_) {}
            }
          }
        }
      }
      
      print('Η επαναφορά ολοκληρώθηκε! (Αρχείο: $fileName)');
      
      try {
        File('tool/.trigger_reload').writeAsStringSync('${DateTime.now().toIso8601String()}|RESTART');
        print('🔄 Στάλθηκε εντολή RESTART στον Dev Server.');
      } catch (_) {}
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
    
    await Process.run('git', ['add', '.'], runInShell: true);
    final commitResult = await Process.run('git', ['commit', '-m', 'Auto commit from AI Patcher - $timestamp'], runInShell: true); 
    print(commitResult.stdout);
    
    final pushResult = await Process.run('git', ['push'], runInShell: true);
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