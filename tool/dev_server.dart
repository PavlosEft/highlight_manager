import 'dart:io';
import 'dart:async';
import 'dart:convert';

// --- ANSI Color Codes ---
const String reset = '\x1B[0m';
const String red = '\x1B[31m';
const String green = '\x1B[32m';
const String yellow = '\x1B[33m';
const String blue = '\x1B[34m';
const String cyan = '\x1B[36m';
const String magenta = '\x1B[35m';
const String bold = '\x1B[1m';

// --- Global Variables ---
List<Process> flutterProcesses = [];
bool isQuitting = false; 
bool isAttachReady = false;
bool isRecovering = false;
bool isAIWorking = false; // Shield (Mutex) to prevent double reload by the watcher
Timer? debounceTimer;
IOSink? logSink;

// AI Patcher State
bool isConfirmingUndo = false;
bool isConfirmingGit = false;
String lastClipboardText = '';

void printMenu() {
  print('\n$cyan====================================================$reset');
  print('$bold$cyan[*] HIGHLIGHT MANAGER - UNIFIED CONTROL PANEL$reset');
  print('$cyan====================================================$reset');
  print('$yellow SERVER COMMANDS:$reset');
  print('  [r] - Hot Reload  |  [e] - Hot Restart');
  print('  [a] - Attach      |  [b] - Build');
  print('  [x] - Clean (x)   |  [q] - Quit & Kill All');
  print('$cyan-----------------------------------------------------$reset');
  print('$yellow AI PATCHER COMMANDS (Listening to Clipboard...):$reset');
  print('  [c] - Create (OK) Zip Backup');
  print('  [g] - Git Commit & Push');
  print('  [u] - Undo (Restore previous Backup)');
  print('$cyan====================================================$reset\n');
}

void writeLog(String message) {
  if (isQuitting) return;
  final time = DateTime.now().toString().substring(11, 19);
  logSink?.writeln('[$time] $message');
}

void cleanupAndExit() {
  isQuitting = true;
  print('\n$yellow[*] Terminating Server... (The Watcher will clean up the rest)$reset');
  
  for (var p in flutterProcesses) p.kill();
  try { logSink?.close(); } catch (_) {}
  
  exit(0); 
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
  print('$blue[*] Initializing Smart Dev Server & AI Patcher...$reset');
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
    writeLog('[*] Android detected. Waking up app via ADB...');
    await wakeUpApp(targetDevice);
    startSmartAttach(targetDevice);
  } else {
    writeLog('[*] Starting full Build...');
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
      print('\n$yellow[*] Starting external cleanup...$reset');
      Process.run('cmd', ['/c', 'start', 'clean_workspace.bat'], runInShell: true);
    } else if (input == 'a') {
      if (targetDevice != 'windows') {
        print('\n$cyan[*] Manual reconnect (Attach)...$reset');
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
      stdout.write('\n$yellow[?] [GIT] Auto commit and push? (y/n): $reset');
    } else if (input == 'u') {
      isConfirmingUndo = true;
      stdout.write('\n$yellow[?] [UNDO] Are you sure you want to restore to the previous version? (y/n): $reset');
    } else {
      for (var p in flutterProcesses) {
        try { p.stdin.add(event); } catch (_) {}
      }
    }
  });

  void handleFileSave(FileSystemEvent event) {
    if (isAIWorking) return;

    final path = event.path.replaceAll('\\', '/');
    if (path.contains('Backups') || path.endsWith('.zip')) return;

    debounceTimer?.cancel();
    debounceTimer = Timer(const Duration(milliseconds: 300), () { // Increased delay for safety
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
    print('$red[!] Connection not established yet! $actionName cancelled.$reset');
    return;
  }
  print('$cyan[*] Executing: $actionName$reset');
  writeLog('[*] $actionName triggered...');
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
  
  print('\n$cyan[DEBUG] Sending delete command (Logging to file)...$reset');
  final result = await Process.run('adb', ['-s', device, 'shell', 'run-as com.example.highlight_manager rm -rf highlight_manager*'], runInShell: true);
  
  try {
    final debugFile = File('tool/adb_debug.txt');
    String logContent = '=== ADB DELETE LOG ===\nDate: ${DateTime.now()}\n\n';
    logContent += '[STDOUT]:\n${result.stdout}\n\n';
    logContent += '[STDERR]:\n${result.stderr}\n';
    debugFile.writeAsStringSync(logContent);
  } catch (_) {}
  
  await Process.run('adb', ['-s', device, 'shell', 'am', 'start', '-n', 'com.example.highlight_manager/.MainActivity'], runInShell: true);
  await Future.delayed(const Duration(seconds: 3)); 
}

void startSmartAttach(String device) async {
  if (isRecovering || isQuitting) return;
  isAttachReady = false;
  
  for (var oldP in flutterProcesses) oldP.kill();
  flutterProcesses.clear();

  writeLog('[*] Activating Attach...');
  final p = await Process.start('flutter', ['attach', '-d', device, '--no-version-check'], runInShell: true);
  flutterProcesses.add(p);
  
  p.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
    if (line.contains('Syncing files to device') && !isAttachReady) {
      isAttachReady = true;
      writeLog('[OK] Connection completed!');
      print('\n$green[OK] [READY] Connection completed! Auto-syncing code...$reset');
      
      Future.delayed(const Duration(milliseconds: 2500), () {
        triggerFlutterCommand('R', 'Initial Attach Sync (Hot Restart)');
      });
    }
    
    if (line.contains('Lost connection to device') || line.contains('Application dead')) {
      writeLog('[ERROR] CRASH DETECTED: $line');
      handleCrashRecovery(device);
    } else {
      writeLog(line);
    }
  });

  p.exitCode.then((code) {
    isAttachReady = false;
    if (!isQuitting && !isRecovering) {
      writeLog('[WARNING] Attach terminated unexpectedly (Exit code: $code).');
      handleCrashRecovery(device);
    }
  });
}

void handleCrashRecovery(String device) async {
  if (isRecovering || isQuitting) return;
  isRecovering = true;
  
  print('\n$bold$red[ERROR] Crash Detected! Starting Auto-Recovery...$reset');
  writeLog('[*] AUTO-RECOVERY: Starting recovery process...');
  
  for (var p in flutterProcesses) p.kill();
  flutterProcesses.clear();
  
  await wakeUpApp(device);
  isRecovering = false;
  startSmartAttach(device);
}

Future<void> startFlutterApp() async {
  writeLog('[*] Preparing to start Build...');
  String targetDevice = await detectDevice();
  
  final p = await Process.start('flutter', ['run', '--no-enable-impeller', '-d', targetDevice], runInShell: true);
  flutterProcesses.add(p);
  
  p.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
    writeLog(line);
    if (line.contains('Syncing files to device') || line.contains('To hot reload changes')) {
      isAttachReady = true;
      print('\n$green[OK] [READY] Build completed! Server "unlocked".$reset');
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
        print('\n$cyan[*] AI Patch Detected...$reset');
        
        isAIWorking = true; // WATCHER LOCK
        
        bool success = applyPatch(rawData);
        playSound(success);
        
        if (success) {
          print('$green[OK] Patch Applied! Creating snapshot...$reset');
          await createCurrentZip(); 

          Timer(const Duration(milliseconds: 1500), () {
            isAIWorking = false;
            triggerFlutterCommand('R', 'AI Auto-Restart');
          });
        } else {
          isAIWorking = false;
          print('$red[ERROR] Patch Failed!$reset');
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
      '-Sta', '-NoProfile', '-Command', 
      r"try { Add-Type -AssemblyName System.Windows.Forms; $t = [System.Windows.Forms.Clipboard]::GetText(); if (![string]::IsNullOrEmpty($t)) { [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($t)) } } catch {}"
    ], runInShell: true);
    
    final b64 = result.stdout.toString().trim();
    if (b64.isEmpty) return '';
    
    return utf8.decode(base64Decode(b64), allowMalformed: true);
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
          print('$red[ERROR] File $filename not found.$reset');
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
            print('$red[ERROR] Code block not found in $filename.$reset');
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
    print('$red[ERROR] Unexpected Error in Patcher: $e$reset');
  }
  return false; 
}

Future<void> createCurrentZip() async {
  print('\n$cyan[*] Auto-Zip: Executing external script...$reset');
  await Process.run('cmd', ['/c', 'zip_source_code.bat'], runInShell: true);
}

Future<void> createOkZip() async {
  print('\n$cyan[*] Creating Permanent (OK) Snapshot via external script...$reset');
  await Process.run('cmd', ['/c', 'zip_source_code.bat', 'OK'], runInShell: true);
}

void handleUndoConfirmation(String input) async {
  if (input == 'y') {
    print('\n$cyan[*] Starting Restore (Undo)...$reset');
    for (var file in Directory('.').listSync()) {
      if (file is File && file.path.contains('SourceCode_') && file.path.endsWith('.zip') && !file.path.contains('(OK)')) {
        file.deleteSync();
      }
    }

    final backupFiles = Directory('Backups').listSync().where((f) => f.path.endsWith('.zip') && !f.path.contains('(OK)')).toList();
    if (backupFiles.isEmpty) {
      print('$red[ERROR] No backups found.$reset');
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
      print('$green[OK] Restore completed! (File: $fileName)$reset');
      triggerFlutterCommand('R', 'Undo Restart');
    }
  } else {
    print('\n$red[!] Undo cancelled.$reset');
  }
  isConfirmingUndo = false;
}

void handleGitConfirmation(String input) async {
  if (input == 'y') {
    print('\n$cyan[*] Executing Git Push...$reset');
    await Process.run('git', ['add', '.'], runInShell: true);
    await Process.run('git', ['commit', '-m', 'Auto commit from Unified Panel'], runInShell: true); 
    final pushResult = await Process.run('git', ['push'], runInShell: true);
    if (pushResult.exitCode == 0) print('$green[OK] [GIT] Success!$reset');
    else print('$red[ERROR] [GIT] Push failed.$reset');
  } else {
    print('\n$red[!] Git operation cancelled.$reset');
  }
  isConfirmingGit = false;
}