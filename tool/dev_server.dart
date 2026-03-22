import 'dart:io';
import 'dart:async';
import 'dart:convert';

// --- Global Variables ---
List<Process> flutterProcesses = [];
bool isQuitting = false; 
bool isAttachReady = false;
bool isRecovering = false;
bool isAIWorking = false; // ΝΕΟ: Ασπίδα (Mutex) για να μην κάνει διπλό reload ο watcher
Timer? debounceTimer;
IOSink? logSink;

// AI Patcher State
bool isConfirmingUndo = false;
bool isConfirmingGit = false;
String lastClipboardText = '';

void printMenu() {
  print('\n====================================================');
  print('⚡ HIGHLIGHT MANAGER - UNIFIED CONTROL PANEL');
  print('====================================================');
  print('SERVER COMMANDS:');
  print('  [r] - Hot Reload  |  [e] - Hot Restart');
  print('  [a] - Attach      |  [b] - Build');
  print('  [x] - Clean (x)   |  [q] - Quit & Kill All');
  print('-----------------------------------------------------');
  print('AI PATCHER COMMANDS (Ακούει το Clipboard...):');
  print('  [c] - Create (OK) Zip Backup');
  print('  [g] - Git Commit & Push');
  print('  [u] - Undo (Επαναφορά προηγούμενου Backup)');
  print('====================================================\n');
}

void writeLog(String message) {
  if (isQuitting) return;
  final time = DateTime.now().toString().substring(11, 19);
  logSink?.writeln('[$time] $message');
}

void cleanupAndExit() {
  isQuitting = true;
  print('\n🧹 Τερματισμός Server... (Ο Φύλακας θα καθαρίσει τα υπόλοιπα)');
  
  for (var p in flutterProcesses) p.kill();
  try { logSink?.close(); } catch (_) {}
  
  exit(0); // Μόλις το dart κλείσει, ο Φύλακας "ξυπνάει" και τρέχει το kill_all.bat!
}

void launchLogViewer() {
  final logFile = File('tool/.logs.txt');
  if (logFile.existsSync()) {
    logFile.writeAsStringSync(''); 
  } else {
    logFile.createSync(recursive: true);
  }
  
  logSink = logFile.openWrite(mode: FileMode.append);
  writeLog('=== LOG VIEWER STARTED ===');

  Process.run('cmd', [
    '/c', 'start', '"Flutter_Smart_Logs"', 'powershell', '-NoProfile', 
    '-Command', '\$Host.UI.RawUI.WindowTitle = \'Flutter_Smart_Logs\'; [Console]::OutputEncoding = [System.Text.Encoding]::UTF8; Get-Content tool/.logs.txt -Wait -Tail 40'
  ]);
}

void main() async {
  print('⚙️ Αρχικοποίηση Smart Dev Server & AI Patcher...');
  launchLogViewer();
  
  final backupDir = Directory('Backups');
  if (!backupDir.existsSync()) backupDir.createSync(); 
  
  printMenu();

  ProcessSignal.sigint.watch().listen((_) => cleanupAndExit());

  String targetDevice = await detectDevice();
  bool forceBuild = false;
  final forceBuildFile = File('tool/.force_build');
  
  if (forceBuildFile.existsSync()) {
    forceBuild = true;
    try { forceBuildFile.deleteSync(); } catch (_) {}
  }

  if (targetDevice != 'windows' && !forceBuild) {
    writeLog('📱 Βρέθηκε Android. Ξύπνημα εφαρμογής μέσω ADB...');
    await wakeUpApp(targetDevice);
    startSmartAttach(targetDevice);
  } else {
    writeLog('🏗️ Εκκίνηση πλήρους Build...');
    await startFlutterApp();
  }

  scheduleClipboardCheck();

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

    if (input == 'q') {
      cleanupAndExit();
    } else if (input == 'h' || input == '?') {
      printMenu();
    } else if (input == 'x') {
      print('\n🧹 Εκκίνηση εξωτερικού καθαρισμού...');
      Process.run('cmd', ['/c', 'start', 'clean_workspace.bat'], runInShell: true);
    } else if (input == 'a') {
      if (targetDevice != 'windows') {
        print('\n⏳ Χειροκίνητη επανασύνδεση (Attach)...');
        startSmartAttach(targetDevice);
      }
    } else if (input == 'b') {
      startFlutterApp();
    } else if (input == 'r') {
      triggerFlutterCommand('r', 'Hot Reload');
    } else if (input == 'e') {
      triggerFlutterCommand('R', 'Hot Restart');
    } else if (input == 'c') {
      createOkZip();
    } else if (input == 'g') {
      isConfirmingGit = true;
      stdout.write('\n⚠️ [GIT] Να γίνει αυτόματο commit και push; (y/n): ');
    } else if (input == 'u') {
      isConfirmingUndo = true;
      stdout.write('\n⚠️ [UNDO] Είσαι σίγουρος ότι θες επαναφορά στην προηγούμενη έκδοση; (y/n): ');
    } else {
      for (var p in flutterProcesses) {
        try { p.stdin.add(event); } catch (_) {}
      }
    }
  });

  void handleFileSave(FileSystemEvent event) {
    // Αν το AI κάνει δουλειά, αγνόησε τα events για να αποφύγουμε διπλό reload!
    if (isAIWorking) return;

    final path = event.path.replaceAll('\\', '/');
    if (path.contains('Backups') || path.endsWith('.zip')) return;

    debounceTimer?.cancel();
    debounceTimer = Timer(const Duration(milliseconds: 300), () { // Αυξημένο delay για ασφάλεια
      if (path.endsWith('.dart') || path.endsWith('.yaml')) {
         triggerFlutterCommand('R', 'Auto-Restart (File Save)');
      }
    });
  }

  if (Directory('lib').existsSync()) Directory('lib').watch(recursive: true).listen(handleFileSave);
  if (Directory('pubspec.yaml').existsSync()) File('pubspec.yaml').watch().listen(handleFileSave);
}

void triggerFlutterCommand(String command, String actionName) {
  if (!isAttachReady) {
    print('⏳ Η σύνδεση δεν έχει ολοκληρωθεί ακόμα! Το $actionName ακυρώθηκε.');
    return;
  }
  print('🔄 Εκτέλεση: $actionName');
  writeLog('🔄 $actionName triggered...');
  for (var p in flutterProcesses) {
    try { p.stdin.writeln(command); } catch (_) {}
  }
}

Future<String> detectDevice() async {
  try {
    final result = await Process.run('flutter', ['devices'], runInShell: true);
    if (result.stdout.toString().contains('L8AIB761L865GB7')) return 'L8AIB761L865GB7';
  } catch (_) {}
  return 'windows';
}

Future<void> wakeUpApp(String device) async {
  await Process.run('adb', ['-s', device, 'forward', '--remove-all'], runInShell: true);
  await Process.run('adb', ['-s', device, 'shell', 'am', 'force-stop', 'com.example.highlight_manager'], runInShell: true);
  await Process.run('adb', ['-s', device, 'shell', 'am', 'start', '-n', 'com.example.highlight_manager/.MainActivity'], runInShell: true);
  await Future.delayed(const Duration(seconds: 3)); // Δίνουμε χρόνο να ανοίξει η εφαρμογή
}

void startSmartAttach(String device) async {
  if (isRecovering || isQuitting) return;
  isAttachReady = false;
  
  for (var oldP in flutterProcesses) oldP.kill();
  flutterProcesses.clear();

  writeLog('🔌 Ενεργοποίηση Attach...');
  final p = await Process.start('flutter', ['attach', '-d', device, '--no-version-check'], runInShell: true);
  flutterProcesses.add(p);
  
  p.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
    if (line.contains('Syncing files to device') && !isAttachReady) {
      isAttachReady = true;
      writeLog('✅ Η σύνδεση ολοκληρώθηκε!');
      print('\n✅ [ΕΤΟΙΜΟ] Η σύνδεση ολοκληρώθηκε! Αυτόματος συγχρονισμός κώδικα...');
      
      // ΛΥΣΗ 1: Περιμένουμε 2.5 δευτερόλεπτα και στέλνουμε 'R' (Hot Restart) 
      // για να φορτώσει ολόφρεσκος ο κώδικας και να μην βλέπεις την παλιά έκδοση.
      Future.delayed(const Duration(milliseconds: 2500), () {
        triggerFlutterCommand('R', 'Initial Attach Sync (Hot Restart)');
      });
    }
    
    if (line.contains('Lost connection to device') || line.contains('Application dead')) {
      writeLog('🚨 CRASH ΑΝΙΧΝΕΥΤΗΚΕ: $line');
      handleCrashRecovery(device);
    } else {
      writeLog(line);
    }
  });

  p.exitCode.then((code) {
    isAttachReady = false;
    if (!isQuitting && !isRecovering) {
      writeLog('⚠️ Το attach τερμάτισε απροσδόκητα (Exit code: $code).');
      handleCrashRecovery(device);
    }
  });
}

void handleCrashRecovery(String device) async {
  if (isRecovering || isQuitting) return;
  isRecovering = true;
  
  print('\n🚨 Ανιχνεύτηκε Crash! Εκκίνηση Auto-Recovery...');
  writeLog('🔄 AUTO-RECOVERY: Εκκίνηση διαδικασίας ανάκτησης...');
  
  for (var p in flutterProcesses) p.kill();
  flutterProcesses.clear();
  
  await wakeUpApp(device);
  isRecovering = false;
  startSmartAttach(device);
}

Future<void> startFlutterApp() async {
  writeLog('🔍 Προετοιμασία εκκίνησης Build...');
  String targetDevice = await detectDevice();
  
  final p = await Process.start('flutter', ['run', '--no-enable-impeller', '-d', targetDevice], runInShell: true);
  flutterProcesses.add(p);
  
  p.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
    writeLog(line);
    // ΛΥΣΗ 2: Όταν το πλήρες build τελειώσει και συγχρονίσει, "ξεκλειδώνουμε" τον server
    if (line.contains('Syncing files to device') || line.contains('To hot reload changes')) {
      isAttachReady = true;
      print('\n✅ [ΕΤΟΙΜΟ] Το Build ολοκληρώθηκε! Ο Server "ξεκλείδωσε".');
    }
  });
  
  p.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((line) => writeLog('[ERROR] $line'));
}

void scheduleClipboardCheck() {
  Timer(const Duration(seconds: 1), () async {
    if (isQuitting) return;
    final rawData = await getClipboard();

    if (rawData.isNotEmpty && rawData != lastClipboardText) {
      lastClipboardText = rawData;
      
      if (rawData.contains('<HM_PATCH>') && !rawData.contains('//[HM_SEEN]')) {
        playDetectSound();
        print('\n⏳ AI Patch Detected...');
        
        isAIWorking = true; // ΚΛΕΙΔΩΜΑ WATCHER
        
        bool success = applyPatch(rawData);
        playSound(success);
        
        if (success) {
          print('✅ Patch Εφαρμόστηκε! Creating snapshot...');
          await createCurrentZip(); 


          // Ξεκλείδωμα watcher με μικρή καθυστέρηση για να προλάβει το σύστημα αρχείων
          Timer(const Duration(milliseconds: 1500), () {
            isAIWorking = false;
            triggerFlutterCommand('R', 'AI Auto-Restart');
          });
        } else {
          isAIWorking = false;
          print('❌ Patch Failed!');
        }

        try {
          final tempFile = File('tool/.temp_clip.txt');
          tempFile.writeAsStringSync(rawData + '\n//[HM_SEEN]');
          await Process.run('powershell', ['-NoProfile', '-Command', 'Get-Content tool/.temp_clip.txt -Raw | Set-Clipboard']);
          try { tempFile.deleteSync(); } catch (_) {}
        } catch (_) {}
      }
    }
    scheduleClipboardCheck();
  });
}

Future<String> getClipboard() async {
  try {
    final result = await Process.run('powershell', [
      '-NoProfile', '-Command', '[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; Get-Clipboard -Raw'
    ], stdoutEncoding: utf8, runInShell: true);
    return result.stdout.toString().trim();
  } catch (e) {
    return '';
  }
}

void playDetectSound() {
  if (Platform.isWindows) Process.run('powershell', ['-c', '[console]::beep(600, 100)']);
}

void playSound(bool success) {
  if (Platform.isWindows) {
    if (success) Process.run('powershell', ['-c', '[console]::beep(1000, 150); [console]::beep(1200, 150)']);
    else Process.run('powershell', ['-c', '[console]::beep(300, 500)']);
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
        final oldCode = replaceMatch.group(1)!.replaceAll(RegExp(r'\xA0'), ' ');
        final newCode = withMatch.group(1)!.replaceAll(RegExp(r'\xA0'), ' ');

        final file = File(filename);
        if (!file.existsSync()) {
          print('❌ Σφάλμα: Δεν βρέθηκε το αρχείο $filename.');
          return false;
        }

        if (!fileContents.containsKey(filename)) {
          fileContents[filename] = file.readAsStringSync().replaceAll('\r\n', '\n').replaceAll(RegExp(r'\xA0'), ' ');
          newFileContents[filename] = fileContents[filename]!;
        }

        if (newFileContents[filename]!.contains(oldCode)) {
          newFileContents[filename] = newFileContents[filename]!.replaceFirst(oldCode, newCode);
        } else {
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

    newFileContents.forEach((filename, content) => File(filename).writeAsStringSync(content));
    return true;

  } catch (e) {
    print('❌ Απρόσμενο Σφάλμα στο Patcher: $e');
  }
  return false; 
}



Future<void> createCurrentZip() async {
  print('\n📦 Auto-Zip: Εκτέλεση εξωτερικού script...');
  await Process.run('cmd', ['/c', 'zip_source_code.bat'], runInShell: true);
}

Future<void> createOkZip() async {
  print('\n⏳ Δημιουργία Μόνιμου (OK) Snapshot μέσω εξωτερικού script...');
  await Process.run('cmd', ['/c', 'zip_source_code.bat', 'OK'], runInShell: true);
}

void handleUndoConfirmation(String input) async {
  if (input == 'y') {
    print('\n⏳ Εκκίνηση Επαναφοράς (Undo)...');
    for (var file in Directory('.').listSync()) {
      if (file is File && file.path.contains('SourceCode_') && file.path.endsWith('.zip') && !file.path.contains('(OK)')) {
        file.deleteSync();
      }
    }

    final backupFiles = Directory('Backups').listSync().where((f) => f.path.endsWith('.zip') && !f.path.contains('(OK)')).toList();
    if (backupFiles.isEmpty) {
      print('❌ Δεν βρέθηκαν backups.');
    } else {
      backupFiles.sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));
      final lastZip = backupFiles.last as File;
      final fileName = lastZip.path.split(Platform.pathSeparator).last;
      
      await lastZip.rename(fileName);
      await Process.run('tar.exe', ['-x', '-f', fileName], runInShell: true); 
      
      for (var dir in [Directory('lib'), Directory('tool')]) {
        if (dir.existsSync()) {
          for (var file in dir.listSync(recursive: true).whereType<File>()) {
            if (file.path.endsWith('.dart')) try { file.setLastModifiedSync(DateTime.now()); } catch (_) {}
          }
        }
      }
      print('Η επαναφορά ολοκληρώθηκε! (Αρχείο: $fileName)');
      triggerFlutterCommand('R', 'Undo Restart');
    }
  } else {
    print('\n🚫 Το Undo ακυρώθηκε.');
  }
  isConfirmingUndo = false;
}

void handleGitConfirmation(String input) async {
  if (input == 'y') {
    print('\n⏳ Εκτέλεση Git Push...');
    await Process.run('git', ['add', '.'], runInShell: true);
    await Process.run('git', ['commit', '-m', 'Auto commit from Unified Panel'], runInShell: true); 
    final pushResult = await Process.run('git', ['push'], runInShell: true);
    if (pushResult.exitCode == 0) print('✅ [GIT] Επιτυχία!');
  }
  isConfirmingGit = false;
}