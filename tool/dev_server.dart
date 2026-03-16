import 'dart:io';
import 'dart:async';
import 'dart:convert';

List<Process> flutterProcesses = [];
bool isQuitting = false; 
bool isAttachReady = false;
Timer? debounceTimer;

void printMenu() {
  print('====================================================');
  print('⚡ HIGHLIGHT MANAGER - FAST DEV SERVER');
  print('====================================================');
  print('ΣΥΝΤΟΜΕΥΣΕΙΣ ΠΛΗΚΤΡΟΛΟΓΙΟΥ:');
  print('  [r] - Hot Reload: Εφαρμογή αλλαγών κώδικα ακαριαία.');
  print('  [e] - Hot Restart: Πλήρης επανεκκίνηση της εφαρμογής.');
  print('  [a] - Attach: Επανασύνδεση στο κινητό (χειροκίνητα).');
  print('  [b] - Build: Πλήρες Build και εγκατάσταση.');
  print('-----------------------------------------------------');
  print('  [h] - Help: Εμφάνιση αυτού του μενού.');
  print('  [x] - Clean Workspace: Λύνει προβλήματα (flutter clean).');
  print('  [q] - Quit: Τερματισμός του Server.');
  print('====================================================');
}

void main() async {
  print('🧹 Καθαρισμός προηγούμενων διεργασιών...');
  try {
    await Process.run('taskkill', ['/F', '/IM', 'highlight_manager.exe', '/T'], runInShell: true);
  } catch (_) {}
  
  printMenu();

  ProcessSignal.sigint.watch().listen((_) {
    isQuitting = true;
    for (var p in flutterProcesses) p.kill();
    exit(0);
  });

  String targetDevice = await detectDevice();

  bool forceBuild = false;
  final forceBuildFile = File('tool/.force_build');
  if (forceBuildFile.existsSync()) {
    forceBuild = true;
    try { forceBuildFile.deleteSync(); } catch (_) {}
  }

  if (targetDevice != 'windows' && !forceBuild) {
    print('📱 Βρέθηκε Android. Εκκίνηση εφαρμογής και σύνδεση στο παρασκήνιο...');
    await Process.run('adb', ['-s', targetDevice, 'forward', '--remove-all'], runInShell: true);
    await Process.run('adb', ['-s', targetDevice, 'shell', 'am', 'start', '-n', 'com.example.highlight_manager/.MainActivity'], runInShell: true);
    
    await Future.delayed(const Duration(seconds: 2));

    // Μία και μοναδική προσπάθεια (Τυφλή εμπιστοσύνη)
    startBlindAttach(targetDevice);
  } else {
    if (forceBuild) print('🏗️ Εντοπίστηκε πρόσφατος καθαρισμός. Αναγκαστικό πλήρες Build...');
    await startFlutterApp();
  }

  try {
    if (stdin.hasTerminal) {
      stdin.lineMode = false;
      stdin.echoMode = false;
    }
  } catch (_) {}

  stdin.listen((event) {
    final input = utf8.decode(event).trim().toLowerCase();
    
    if (input == 'q') {
      isQuitting = true;
      print('\nΤερματισμός...');
      for (var p in flutterProcesses) p.kill();
      exit(0);
    } else if (input == 'h' || input == '?') {
      printMenu();
    } else if (input == 'x') {
      isQuitting = true;
      print('\n🧹 Εκκίνηση εξωτερικού καθαρισμού... Ο Server θα τερματιστεί.');
      for (var p in flutterProcesses) p.kill();
      
      Process.run('cmd', ['/c', 'start', 'clean_workspace.bat'], runInShell: true);
      exit(0);
    } else if (input == 'a') {
      if (targetDevice != 'windows') {
        print('\n⏳ Χειροκίνητη επανασύνδεση (Attach)...');
        startBlindAttach(targetDevice);
      }
    } else if (input == 'b') {
      startFlutterApp();
    } else if (input == 'r') {
      if (!isAttachReady && targetDevice != 'windows') {
        print('⏳ Περίμενε... Η σύνδεση δεν έχει ολοκληρωθεί ακόμα!');
      } else {
        print('🔄 Στάλθηκε εντολή r (Hot Reload) στο Flutter.');
        for (var p in flutterProcesses) {
          try { p.stdin.writeln('r'); } catch (_) {}
        }
      }
    } else if (input == 'e') {
      if (!isAttachReady && targetDevice != 'windows') {
        print('⏳ Περίμενε... Η σύνδεση δεν έχει ολοκληρωθεί ακόμα!');
      } else {
        print('🔄 Στάλθηκε εντολή R (Hot Restart) στο Flutter.');
        for (var p in flutterProcesses) {
          try { p.stdin.writeln('R'); } catch (_) {}
        }
      }
    } else {
      for (var p in flutterProcesses) {
        try { p.stdin.add(event); } catch (_) {}
      }
    }
  });

  void handleManualSave(FileSystemEvent event) {
    final path = event.path.replaceAll('\\', '/');
    if (path.contains('Backups') || path.endsWith('.zip')) return;

    debounceTimer?.cancel();
    debounceTimer = Timer(const Duration(milliseconds: 150), () {
      if (path.endsWith('.trigger_reload')) {
        try {
          final content = File(path).readAsStringSync().trim();
          final parts = content.split('|');
          String action = 'RELOAD';
          if (parts.length == 2) action = parts[1].toUpperCase();

          print('\n🤖 [AI ACTION] Εκτέλεση αυτόματου: $action');
          if (action == 'RESTART') {
            for (var p in flutterProcesses) try { p.stdin.writeln('R'); } catch (_) {}
          } else if (action == 'CLEAN') {
            print('\n🧹 [AI CLEAN] Απαιτείται καθαρισμός. Κάνε restart τον server [x]!');
          } else {
            for (var p in flutterProcesses) try { p.stdin.writeln('r'); } catch (_) {}
          }
        } catch (_) {
          for (var p in flutterProcesses) try { p.stdin.writeln('r'); } catch (_) {}
        }
      } else if (path.endsWith('.dart')) {
        // Χειροκίνητη αποθήκευση από εσένα = Ακαριαίο Reload
        for (var p in flutterProcesses) try { p.stdin.writeln('r'); } catch (_) {}
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

void startBlindAttach(String device) async {
  isAttachReady = false;
  // Καθαρισμός παλιών διεργασιών Attach
  for (var oldP in flutterProcesses) oldP.kill();
  flutterProcesses.clear();

  print('🔌 Ξεκινάει το Attach (Κανάλι επικοινωνίας ανοιχτό)...');
  final p = await Process.start('flutter', ['attach', '-d', device, '--no-version-check'], runInShell: true);
  flutterProcesses.add(p);
  
  // Φιλτράρουμε την περιττή φλυαρία του attach και ψάχνουμε το Ready state
  p.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
    if (line.contains('Flutter run key commands') || line.contains('Syncing files to device') || line.contains('To hot reload changes')) {
      isAttachReady = true;
      print('\n✅ [ΕΤΟΙΜΟ] Η σύνδεση ολοκληρώθηκε! Μπορείς να κάνεις Reload/Restart.');
    }
    if (line.contains('Performing hot') || line.contains('Reloaded') || line.contains('Restarted')) {
      stdout.writeln('[system] $line');
    } else if (line.contains('[ANALYZE]') || line.contains('[USER ACTION]')) {
      stdout.writeln('\n👉 [ΕΦΑΡΜΟΓΗ]: $line');
    } else if (line.contains('flutter:')) {
      stdout.writeln('[app] ${line.split('flutter:').last.trim()}');
    }
  });

  p.exitCode.then((code) {
    isAttachReady = false;
    if (!isQuitting) {
      print('\n⚠️ Το κανάλι επικοινωνίας έκλεισε (Exit code: $code). Αν θες, πάτα [a] για χειροκίνητη επανασύνδεση.');
    }
  });
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

  p.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
    stdout.writeln('[$logPrefix] $line');
    if (line.contains('Flutter run key commands')) {
      overallStopwatch.stop();
      print('[INFO] TOTAL wait time: ${overallStopwatch.elapsed.inSeconds}s');
    }
  });
  p.stderr.transform(utf8.decoder).listen((data) => stderr.write('[$logPrefix] $data'));

  p.exitCode.then((code) {
    if (!isQuitting) {
      print('\n\n⚠️ Το Build διεκόπη.');
    }
  });
}