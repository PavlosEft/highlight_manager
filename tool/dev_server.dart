import 'dart:io';
import 'dart:async';
import 'dart:convert';

Process? flutterProcess;
bool isConfirmingUndo = false;

void main() async {
  print('====================================================');
  print('🚀 HIGHLIGHT MANAGER - PRO DEV SERVER');
  print('====================================================');
  
  // Διασφάλιση ότι υπάρχει ο φάκελος Backups
  final backupDir = Directory('Backups');
  if (!backupDir.existsSync()) backupDir.createSync();

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

    if (input == 'q') {
      print('\nΤερματισμός...');
      exit(0);
    } else if (input == 'u') {
      isConfirmingUndo = true;
      stdout.write('\n⚠️ [UNDO] Είσαι σίγουρος ότι θες επαναφορά στην προηγούμενη έκδοση; (y/n): ');
    } else {
      flutterProcess?.stdin.add(event);
    }
  });

  // Αρχικοποίηση clipboard (αγνόηση παλιών δεδομένων)
  String lastClipboard = await getClipboard();
  
  Timer.periodic(const Duration(seconds: 1), (timer) async {
    if (isConfirmingUndo) return;

    final clipboard = await getClipboard();
    if (clipboard.isNotEmpty && clipboard != lastClipboard && clipboard.contains('<HM_PATCH>')) {
      lastClipboard = clipboard;
      print('\n✨ [AI PATCHER] Νέος κώδικας εντοπίστηκε!');
      
      // 1. Πριν το patch, μετακίνηση του τρέχοντος ZIP στα Backups
      await manageZipsBeforePatch();
      
      // 2. Εφαρμογή Patch
      bool success = applyPatch(clipboard);
      
      if (success) {
        // 3. Μετά την επιτυχία, δημιουργία νέου ZIP έξω
        await createCurrentZip();
        print('🔄 [AI PATCHER] Hot Reload...');
        flutterProcess!.stdin.write('r'); 
      }
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
    if (file is File && file.path.contains('SourceCode_') && file.path.endsWith('.zip')) {
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
  
  // Συμπερίληψη όλων των επιλεγμένων αρχείων (lib, tool, instructions, yaml, bats)
  await Process.run('tar.exe', [
    '-a', '-c', '-f', zipName, 
    'lib', 'tool', 'AI_INSTRUCTIONS.txt', 'pubspec.yaml', 'start_dev.bat', 'zip_source_code.bat'
  ]);
  print('✅ Νέο Snapshot δημιουργήθηκε: $zipName');
}

void handleUndoConfirmation(String input) async {
  if (input == 'y') {
    print('\n⏳ Εκκίνηση Επαναφοράς (Undo)...');
    
    // 1. Διαγραφή του τρέχοντος "κακού" zip έξω
    final rootFiles = Directory('.').listSync();
    for (var file in rootFiles) {
      if (file is File && file.path.contains('SourceCode_') && file.path.endsWith('.zip')) {
        file.deleteSync();
      }
    }

    // 2. Εύρεση του τελευταίου zip στα Backups
    final backupFiles = Directory('Backups').listSync()
        .where((f) => f.path.endsWith('.zip'))
        .toList();
    
    if (backupFiles.isEmpty) {
      print('❌ Δεν βρέθηκαν backups για επαναφορά.');
    } else {
      backupFiles.sort((a, b) => a.path.compareTo(b.path));
      final lastZip = backupFiles.last as File;
      final fileName = lastZip.path.split(Platform.pathSeparator).last;
      
      // 3. Μεταφορά έξω
      await lastZip.rename(fileName);
      
      // 4. Extract
      await Process.run('tar.exe', ['-x', '-f', fileName]);
      
      print('⏪ Η επαναφορά ολοκληρώθηκε! (Αρχείο: $fileName)');
      flutterProcess!.stdin.write('r');
    }
  } else {
    print('\n🚫 Το Undo ακυρώθηκε.');
  }
  isConfirmingUndo = false;
}

bool applyPatch(String rawClipboard) {
  try {
    final text = rawClipboard.replaceAll('\r\n', '\n'); 
    final fileMatch = RegExp(r'<FILE>(.*?)</FILE>').firstMatch(text);
    final replaceMatch = RegExp(r'<REPLACE>\n?(.*?)\n?</REPLACE>', dotAll: true).firstMatch(text);
    final withMatch = RegExp(r'<WITH>\n?(.*?)\n?</WITH>', dotAll: true).firstMatch(text);

    if (fileMatch != null && replaceMatch != null && withMatch != null) {
      final filename = fileMatch.group(1)!.trim();
      final oldCode = replaceMatch.group(1)!;
      final newCode = withMatch.group(1)!;

      final file = File(filename);
      if (file.existsSync()) {
        String content = file.readAsStringSync().replaceAll('\r\n', '\n');
        if (content.contains(oldCode)) {
          final newContent = content.replaceFirst(oldCode, newCode);
          file.writeAsStringSync(newContent);
          print('✅ Επιτυχία στο αρχείο: $filename');
          return true; 
        } else {
          print('❌ Σφάλμα: Δεν βρέθηκε ο κώδικας.');
        }
      }
    }
  } catch (e) {
    print('❌ Απρόσμενο Σφάλμα: $e');
  }
  return false; 
}