import 'dart:io';
import 'dart:async';
import 'dart:convert';

List<Process> flutterProcesses = [];
bool isConfirmingUndo = false;
bool isConfirmingGit = false;
bool isQuitting = false; // Σημαία για να μην βγάζει σφάλμα όταν κλείνουμε επίτηδες την εφαρμογή
Timer? debounceTimer;

void printMenu() {
  print('====================================================');
  print('HIGHLIGHT MANAGER - PRO DEV SERVER (Runner)');
  print('====================================================');
  print('ΣΥΝΤΟΜΕΥΣΕΙΣ ΠΛΗΚΤΡΟΛΟΓΙΟΥ:');
  print('  [c] - Create (OK) Zip: Μόνιμο Snapshot έξω, χωρίς να διαγράφεται.');
  print('  [g] - Git Push: Αυτόματο add, commit και push.');
  print('  [u] - Undo: Επαναφορά στην προηγούμενη έκδοση από το φάκελο Backups.');
  print('  [a] - Attach: Επανασύνδεση στο κινητό (χωρίς νέο build).');
  print('-----------------------------------------------------');
  print('  [r] - Hot Reload: Εφαρμογή αλλαγών κώδικα ακαριαία (μόνο σε Debug).');
  print('  [R] - Hot Restart: Πλήρης επανεκκίνηση της εφαρμογής.');
  print('  [h] - Help: Εμφάνιση αυτού του μενού συντομεύσεων.');
  print('  [x] - Clean Workspace: Λύνει προβλήματα κλειδωμένων αρχείων (build failed).');
  print('  [q] - Quit: Τερματισμός του Server και της εφαρμογής.');
  print('====================================================');
}

void main() async {
  print('====================================================');
  print('🧹 Καθαρισμός προηγούμενων διεργασιών...');
  try {
    await Process.run('taskkill', ['/F', '/IM', 'highlight_manager.exe', '/T'], runInShell: true);
  } catch (_) {}
  
  printMenu();
  
  final backupDir = Directory('Backups');
  if (!backupDir.existsSync()) backupDir.createSync();

  ProcessSignal.sigint.watch().listen((_) {
    isQuitting = true;
    for (var p in flutterProcesses) p.kill();
    exit(0);
  });

  String targetDevice = await detectDevice();
  bool connected = false;

  if (targetDevice != 'windows') {
    print('📱 Βρέθηκε Android συσκευή. Αυτόματη εκκίνηση και σύνδεση...');
    // Καθαρισμός τυχόν κολλημένων tunnels για αποφυγή συγκρούσεων
    await Process.run('adb', ['-s', targetDevice, 'forward', '--remove-all'], runInShell: true);
    // Εκκίνηση της εφαρμογής (την ανοίγει αν είναι κλειστή, την φέρνει μπροστά αν είναι ανοιχτή)
    await Process.run('adb', ['-s', targetDevice, 'shell', 'am', 'start', '-n', 'com.example.highlight_manager/.MainActivity'], runInShell: true);
    
    print('⏳ Αναμονή 2 δευτερολέπτων για προετοιμασία της Dart VM...');
    await Future.delayed(const Duration(seconds: 2));

    for (int i = 1; i <= 3; i++) {
      print('⏳ Προσπάθεια σύνδεσης (Attach) $i/3...');
      connected = await tryAttach(targetDevice);
      if (connected) break;
      if (i < 3) {
        print('😴 Αναμονή 2 δευτερολέπτων πριν την επόμενη προσπάθεια...');
        await Future.delayed(const Duration(seconds: 2));
      }
    }
  }

  bool isAwaitingAttachChoice = false;

  if (!connected) {
    if (targetDevice != 'windows') {
      print('\n❌ Αποτυχία σύνδεσης μετά από 3 προσπάθειες.');
      print('👉 [b] - Πλήρες Build');
      print('👉 [a] - Ξαναδοκίμασε Attach');
      print('👉 Ή χρησιμοποίησε οποιαδήποτε άλλη συντόμευση...');
      isAwaitingAttachChoice = true;
    } else {
      await startFlutterApp();
    }
  }

  try {
    if (stdin.hasTerminal) {
      // Προσπάθεια ρύθμισης για άμεση απόκριση πλήκτρων (χωρίς Enter)
      stdin.lineMode = false;
      stdin.echoMode = false;
    }
  } catch (_) {
    // Αν αποτύχει στα Windows (errno 87), συνεχίζει κανονικά
  }

  stdin.listen((event) {
    final input = utf8.decode(event).trim().toLowerCase();
    
    if (isAwaitingAttachChoice) {
      if (input == 'b') {
        isAwaitingAttachChoice = false;
        startFlutterApp();
        return;
      } else if (input == 'a') {
        isAwaitingAttachChoice = false;
        handleAttach();
        return;
      }
      // Αν πατηθεί κάτι άλλο, συνεχίζει κανονικά για να λειτουργούν οι συντομεύσεις
    }

    if (isConfirmingUndo) {
      handleUndoConfirmation(input);
      return;
    }
    
    if (isConfirmingGit) {
      handleGitConfirmation(input);
      return;
    }

    if (input == 'q') {
      isQuitting = true;
      print('\nΤερματισμός...');
      for (var p in flutterProcesses) p.kill();
      exit(0);
    } else if (input == 'h' || input == '?') {
      printMenu();
    } else if (input == 'x') {
      isQuitting = true;
      print('\n🧹 Τερματισμός Gradle Daemons & καθαρισμός (flutter clean)...');
      for (var p in flutterProcesses) p.kill();
      Process.runSync('cmd', ['/c', 'cd android && gradlew.bat --stop'], runInShell: true);
      
      try {
        final buildDir = Directory('build');
        if (buildDir.existsSync()) {
          buildDir.deleteSync(recursive: true);
          print('✅ Επιθετική διαγραφή φακέλου build πέτυχε.');
        }
      } catch (e) {
        print('⚠️ Σφάλμα διαγραφής φακέλου build (Αρχεία κλειδωμένα από τα Windows): $e');
      }

      final cleanResult = Process.runSync('flutter', ['clean'], runInShell: true);
      if (cleanResult.stdout.toString().trim().isNotEmpty) print(cleanResult.stdout);
      if (cleanResult.stderr.toString().trim().isNotEmpty) print('❌ [ΣΦΑΛΜΑ CLEAN]: ${cleanResult.stderr}');
      
      Process.runSync('flutter', ['pub', 'get'], runInShell: true);
      print('✅ Ολοκληρώθηκε! Κλείσε το παράθυρο και τρέξε ξανά το start_dev.bat');
      exit(0);
    } else if (input == 'u') {
      isConfirmingUndo = true;
      stdout.write('\n⚠️ [UNDO] Είσαι σίγουρος ότι θες επαναφορά στην προηγούμενη έκδοση; (y/n): ');
    } else if (input == 'g') {
      isConfirmingGit = true;
      stdout.write('\n⚠️ [GIT] Να γίνει αυτόματο commit και push; (y/n): ');
    } else if (input == 'c') {
      createOkZip();
    } else if (input == 'a') {
      handleAttach();
    } else {
      for (var p in flutterProcesses) p.stdin.add(event);
    }
  });

  void handleManualSave(FileSystemEvent event) {
    if (isConfirmingUndo || isConfirmingGit) return;
    
    final path = event.path.replaceAll('\\', '/');
    if (path.endsWith('.zip') || path.contains('Backups')) return;

    debounceTimer?.cancel();
    debounceTimer = Timer(const Duration(milliseconds: 800), () async {
      print('\n💾 [FILE WATCHER] Εντοπίστηκε αποθήκευση: ${event.path}');
      await manageZipsBeforePatch();
      await createCurrentZip();

      if (path.endsWith('.trigger_reload')) {
        try {
          final content = File(path).readAsStringSync().trim();
          final parts = content.split('|');
          String action = 'RELOAD';
          if (parts.length == 2) action = parts[1].toUpperCase();

          print('🤖 [AI ACTION] Απαίτηση για: $action');
          if (action == 'RESTART') {
            for (var p in flutterProcesses) p.stdin.write('R');
          } else if (action == 'CLEAN') {
            isQuitting = true;
            print('\n🧹 [AI CLEAN] Εκτελείται αυτόματος καθαρισμός (Clean) λόγω αλλαγών στα dependencies...');
            for (var p in flutterProcesses) p.kill();
            Process.runSync('cmd', ['/c', 'cd android && gradlew.bat --stop'], runInShell: true);
            Process.runSync('flutter', ['clean'], runInShell: true);
            Process.runSync('flutter', ['pub', 'get'], runInShell: true);
            print('✅ Ολοκληρώθηκε ο καθαρισμός! Κλείσε το παράθυρο και τρέξε ξανά το start_dev.bat');
            exit(0);
          } else {
            for (var p in flutterProcesses) p.stdin.write('r');
          }
        } catch (_) {
          for (var p in flutterProcesses) p.stdin.write('r');
        }
      } else {
        // Αν έγινε χειροκίνητη αποθήκευση, κάνει πάντα απλό reload
        for (var p in flutterProcesses) p.stdin.write('r');
      }
    });
  }

  if (Directory('lib').existsSync()) {
    Directory('lib').watch(recursive: true).listen(handleManualSave);
  }
  if (Directory('tool').existsSync()) {
    Directory('tool').watch(recursive: true).listen(handleManualSave);
  }
}

Future<String> detectDevice() async {
  try {
    final result = await Process.run('flutter', ['devices'], runInShell: true);
    if (result.stdout.toString().contains('L8AIB761L865GB7')) {
      return 'L8AIB761L865GB7';
    }
  } catch (_) {}
  return 'windows';
}

Future<bool> tryAttach(String device) async {
  for (var oldP in flutterProcesses) {
    oldP.kill();
  }
  flutterProcesses.clear();

  // 1. Έναρξη του Attach για Hot Reload / Restart
  final p = await Process.start('flutter', ['attach', '-d', device, '--no-version-check'], runInShell: true);
  final completer = Completer<bool>();
  
  final subscription = p.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
    // Φιλτράρουμε τα συστημικά μηνύματα του attach
    if (line.contains('Flutter run key commands') || line.contains('Syncing files to device')) {
      if (!completer.isCompleted) completer.complete(true);
    }
    if (line.contains('Performing hot') || line.contains('Reloaded') || line.contains('Restarted')) {
      stdout.writeln('[system] $line');
    }
  });

  // 2. ΠΑΡΑΛΛΗΛΟ LOGGER (ADB Logcat): Τραβάει τα logs απευθείας από το Android
  if (device != 'windows') {
    print('📡 [LOGGER] Έναρξη απευθείας μετάδοσης logs από τη συσκευή...');
    // Καθαρισμός του buffer για να βλέπουμε μόνο τα νέα logs κατά τη σύνδεση
    await Process.run('adb', ['-s', device, 'logcat', '-c'], runInShell: true);
    
    final loggerP = await Process.start('adb', ['-s', device, 'logcat', 'flutter:V', '*:S'], runInShell: true);
    flutterProcesses.add(loggerP);
    
    loggerP.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      // Βελτιωμένη ανίχνευση logs για συσκευές ASUS και διαφορετικά Android formats
      if (line.contains('flutter')) {
        if (line.contains('):')) {
          stdout.writeln(line.substring(line.indexOf('):') + 2).trim());
        } else {
          // Fallback για logs που δεν έχουν το κλασικό format (PID)
          final parts = line.split('flutter');
          if (parts.length > 1) {
            stdout.writeln(parts.last.replaceFirst(RegExp(r'^\s*\(.*?\):\s*'), '').trim());
          } else {
            stdout.writeln(line.trim());
          }
        }
      }
    });
  }

  p.exitCode.then((code) { if (!completer.isCompleted) completer.complete(false); });
  Future.delayed(const Duration(seconds: 15), () { if (!completer.isCompleted) completer.complete(false); });

  bool success = await completer.future;
  if (success) {
    flutterProcesses.add(p);
    
    p.exitCode.then((code) {
      if (!isQuitting) {
        print('\n⚠️ Η σύνδεση χάθηκε.');
        handleAttach();
      }
    });
  } else {
    p.kill();
    subscription.cancel();
  }
  return success;
}

Future<void> startFlutterApp() async {
  print('🔍 Προετοιμασία εκκίνησης...');
  String targetDevice = await detectDevice();
  if (targetDevice == 'L8AIB761L865GB7') {
    print('📱 Εκκίνηση Build στο Android...');
  } else {
    print('💻 Εκκίνηση στα Windows...');
  }

  final p = await Process.start('flutter', ['run', '--no-enable-impeller', '-d', targetDevice], runInShell: true);
  flutterProcesses.add(p);
  final logPrefix = targetDevice == 'windows' ? 'windows' : 'android';
  
  Stopwatch overallStopwatch = Stopwatch()..start();
  Stopwatch? stepStopwatch;
  bool sizeLogged = false;

  p.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
    stdout.writeln('[$logPrefix] $line');
    
    if (line.contains('Running Gradle task')) {
      stepStopwatch = Stopwatch()..start();
      print('\n[INFO] [PHASE 1] Starting build (Gradle)...');
    }
    
    if (line.contains('Built build') && line.contains('app-debug.apk')) {
      if (stepStopwatch != null) {
        stepStopwatch!.stop();
        print('\n[INFO] [PHASE 1] Build completed in: ${stepStopwatch!.elapsed.inSeconds}s');
      }
      
      if (!sizeLogged) {
        try {
          final apkFile = File('build/app/outputs/flutter-apk/app-debug.apk');
          if (apkFile.existsSync()) {
            final sizeInMb = apkFile.lengthSync() / (1024 * 1024);
            print('[INFO] Final APK Size: ${sizeInMb.toStringAsFixed(2)} MB');
            sizeLogged = true;
          }
        } catch (_) {}
      }
    }
    
    if (line.contains('Installing build') || line.contains('Installing ')) {
      stepStopwatch = Stopwatch()..start();
      print('\n[INFO] [PHASE 2] Starting APK transfer and installation (ADB)...');
    }

    if (line.contains('Syncing files to device')) {
      if (stepStopwatch != null) {
        stepStopwatch!.stop();
        print('\n[INFO] [PHASE 2] Installation completed in: ${stepStopwatch!.elapsed.inSeconds}s');
      }
      stepStopwatch = Stopwatch()..start();
      print('\n[INFO] [PHASE 3] Syncing Flutter files with device...');
    }

    if (line.contains('Flutter run key commands')) {
      overallStopwatch.stop();
      if (stepStopwatch != null) {
        stepStopwatch!.stop();
        print('\n[INFO] [PHASE 3] Sync completed in: ${stepStopwatch!.elapsed.inSeconds}s');
      }
      print('[INFO] TOTAL wait time (Build + Install + Sync): ${overallStopwatch.elapsed.inSeconds}s');
    }
  });
  p.stderr.transform(utf8.decoder).listen((data) => stderr.write('[$logPrefix] $data'));

  // Ανιχνευτής απώλειας σύνδεσης (Crash ή αποσύνδεση καλωδίου)
  p.exitCode.then((code) {
    if (!isQuitting) {
      print('\n\n⚠️ Η σύνδεση με την εφαρμογή/συσκευή διακόπηκε (Exit code: $code).');
      print('🔄 Προσπάθεια αυτόματης επανασύνδεσης (Attach) σε 3 δευτερόλεπτα...');
      Future.delayed(const Duration(seconds: 3), () {
        if (!isQuitting) handleAttach();
      });
    }
  });


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
      for (var p in flutterProcesses) p.stdin.write('r');
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
    final commitResult = await Process.run('git', ['commit', '-m', 'Auto commit from dev server - $timestamp'], runInShell: true);
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

void handleAttach() async {
  print('\n⏳ Επανασύνδεση (Attach)...');
  String targetDevice = await detectDevice();
  
  if (targetDevice != 'windows') {
    await Process.run('adb', ['-s', targetDevice, 'forward', '--remove-all'], runInShell: true);
  }

  bool connected = await tryAttach(targetDevice);
  if (!connected && !isQuitting) {
    print('❌ Αποτυχία αυτόματης επανασύνδεσης. Δοκίμασε χειροκίνητα με [a].');
  }
}