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

  String lastSequence = '0';

  Timer.periodic(const Duration(seconds: 1), (timer) async {
    final rawData = await getClipboard();
    if (rawData.isEmpty) return; 

    final parts = rawData.split(':::CLIP_SEQ:::');
    if (parts.length < 2) return; 

    final currentSequence = parts[0].trim();
    final clipboard = parts.sublist(1).join(':::CLIP_SEQ:::');

    if (currentSequence != lastSequence && clipboard.contains('<HM_PATCH>')) {
      lastSequence = currentSequence;
      
      print('\n⏳ Εφαρμογή αλλαγών...');
      bool success = applyPatch(clipboard);
      
      if (success) {
        print('✨ [AI PATCHER] Το patch εφαρμόστηκε επιτυχώς! Δημιουργία snapshot...');
        
        await manageZipsBeforePatch();
        await createCurrentZip(); 

        final actionRegex = RegExp(r'<ACTION>(.*?)</ACTION>', dotAll: true);
        final actionMatch = actionRegex.firstMatch(clipboard);
        String action = 'RELOAD'; 
        if (actionMatch != null) {
          action = actionMatch.group(1)!.trim().toUpperCase();
        }

        try {
          File('tool/.trigger_reload').writeAsStringSync('${DateTime.now().toIso8601String()}|$action');
        } catch (_) {}
        print('✅ Το patch εφαρμόστηκε. Action: $action. Ο Dev Server ενημερώνεται αυτόματα.');
      } else {
        print('⚠️ Αποτυχία εφαρμογής. Ελέγξτε τα αρχεία.');
      }
    }
  });
  
  ProcessSignal.sigint.watch().listen((_) {
    exit(0);
  });
}

Future<String> getClipboard() async {
  try {
    // Χρήση triple-quotes r''' για την αποφυγή σφαλμάτων με τις διπλές εισαγωγικές της PowerShell
    final result = await Process.run('powershell', [
      '-NoProfile',
      '-Command',
      r'''$ErrorActionPreference = 'SilentlyContinue'; $code = '[DllImport("user32.dll")] public static extern uint GetClipboardSequenceNumber();'; $type = Add-Type -MemberDefinition $code -Name 'WinCB' -Namespace 'Win32' -PassThru; $seq = $type::GetClipboardSequenceNumber(); $txt = Get-Clipboard -Raw; if ($txt -eq $null) { $txt = '' }; Write-Output ($seq.ToString() + ':::CLIP_SEQ:::' + $txt)'''
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
    });

    return true;

  } catch (e) {
    print('❌ Απρόσμενο Σφάλμα: $e');
  }
  return false; 
}

Future<void> manageZipsBeforePatch() async {
  final rootFiles = Directory('.').listSync();
  for (var file in rootFiles) {
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
  
  final result = await Process.run('tar.exe', args, runInShell: true);
  
  if (result.exitCode == 0) {
    print('✅ Αυτόματο Snapshot δημιουργήθηκε: $zipName');
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
      backupFiles.sort((a, b) => a.path.compareTo(b.path));
      final lastZip = backupFiles.last as File;
      final fileName = lastZip.path.split(Platform.pathSeparator).last;
      
      await lastZip.rename(fileName);
      await Process.run('tar.exe', ['-x', '-f', fileName], runInShell: true); 
      
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