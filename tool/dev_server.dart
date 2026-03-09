import 'dart:io';
import 'dart:async';
import 'dart:convert';

List<Process> flutterProcesses = [];
bool isConfirmingUndo = false;
bool isConfirmingGit = false;
bool isConfirmingBrowser = false;
Timer? debounceTimer;

void main() async {
  print('====================================================');
  print('🧹 Καθαρισμός προηγούμενων διεργασιών...');
  try {
    // Κλείνει την εφαρμογή αν τρέχει ήδη στα Windows για να επιτρέψει το νέο build
    await Process.run('taskkill', ['/F', '/IM', 'highlight_manager.exe', '/T'], runInShell: true);
  } catch (_) {}
  print('HIGHLIGHT MANAGER - PRO DEV SERVER (Runner)');
  print('====================================================');
  print('ΣΥΝΤΟΜΕΥΣΕΙΣ ΠΛΗΚΤΡΟΛΟΓΙΟΥ:');
  print('  [c] - Create (OK) Zip: Μόνιμο Snapshot έξω, χωρίς να διαγράφεται.');
  print('  [g] - Git Push: Αυτόματο add, commit και push.');
  print('  [u] - Undo: Επαναφορά στην προηγούμενη έκδοση από το φάκελο Backups.');
  print('  [b] - Browser: Άνοιγμα της εφαρμογής στον Chrome (Web).');
  print('  [a] - Attach: Επανασύνδεση στο κινητό (χωρίς νέο build).');
  print('-----------------------------------------------------');
  print('  [r] - Hot Reload: Εφαρμογή αλλαγών κώδικα ακαριαία (μόνο σε Debug).');
  print('  [R] - Hot Restart: Πλήρης επανεκκίνηση της εφαρμογής.');
  print('  [q] - Quit: Τερματισμός του Server και της εφαρμογής.');
  print('====================================================');
  
  final backupDir = Directory('Backups');
  if (!backupDir.existsSync()) backupDir.createSync();

  // Αισθητήρες για το κλείσιμο του παραθύρου για να κλείνει και το Flutter
  ProcessSignal.sigint.watch().listen((_) {
    for (var p in flutterProcesses) p.kill();
    exit(0);
  });

  print('🔍 Έλεγχος συσκευών (παίρνει ~1-2 δευτερόλεπτα)...');
  String targetDevice = 'windows';
  try {
    final result = await Process.run('flutter', ['devices'], runInShell: true);
    if (result.stdout.toString().contains('L8AIB761L865GB7')) {
      targetDevice = 'L8AIB761L865GB7';
      print('📱 Βρέθηκε συνδεδεμένο κινητό! Εκκίνηση στο Android...');
    } else {
      print('💻 Το κινητό δεν βρέθηκε. Εκκίνηση στα Windows...');
    }
  } catch (e) {
    print('💻 Σφάλμα ανίχνευσης. Προεπιλογή στα Windows...');
  }

  final p = await Process.start('flutter', ['run', '-d', targetDevice], runInShell: true);
  flutterProcesses.add(p);
  final logPrefix = targetDevice == 'windows' ? 'windows' : 'android';
  p.stdout.transform(utf8.decoder).listen((data) => stdout.write('[$logPrefix] $data'));
  p.stderr.transform(utf8.decoder).listen((data) => stderr.write('[$logPrefix] $data'));

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

    if (isConfirmingBrowser) {
      handleBrowserConfirmation(input);
      return;
    }

    if (input == 'q') {
      print('\nΤερματισμός...');
      for (var p in flutterProcesses) p.kill();
      exit(0);
    } else if (input == 'u') {
      isConfirmingUndo = true;
      stdout.write('\n⚠️ [UNDO] Είσαι σίγουρος ότι θες επαναφορά στην προηγούμενη έκδοση; (y/n): ');
    } else if (input == 'g') {
      isConfirmingGit = true;
      stdout.write('\n⚠️ [GIT] Να γίνει αυτόματο commit και push; (y/n): ');
    } else if (input == 'c') {
      createOkZip();
    } else if (input == 'b') {
      isConfirmingBrowser = true;
      stdout.write('\n⚠️ [BROWSER] Να ανοίξει η εφαρμογή και στον Chrome; (y/n): ');
    } else if (input == 'a') {
      handleAttach();
    } else {
      for (var p in flutterProcesses) p.stdin.add(event);
    }
  });

  void handleManualSave(FileSystemEvent event) {
    if (isConfirmingUndo) return;
    
    final path = event.path.replaceAll('\\', '/');
    if (path.endsWith('.zip') || path.contains('Backups')) return;

    debounceTimer?.cancel();
    debounceTimer = Timer(const Duration(milliseconds: 800), () async {
      print('\n💾 [FILE WATCHER] Εντοπίστηκε αποθήκευση: ${event.path}');
      await manageZipsBeforePatch();
      await createCurrentZip();
      for (var p in flutterProcesses) p.stdin.write('r');
    });
  }

  if (Directory('lib').existsSync()) {
    Directory('lib').watch(recursive: true).listen(handleManualSave);
  }
  if (Directory('tool').existsSync()) {
    Directory('tool').watch(recursive: true).listen(handleManualSave);
  }
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

void handleBrowserConfirmation(String input) async {
  if (input == 'y') {
    print('\n⏳ Εκκίνηση στον Chrome...');
    final p = await Process.start('flutter', ['run', '-d', 'chrome', '--web-port', '8080'], runInShell: true);
    flutterProcesses.add(p);
    p.stdout.transform(utf8.decoder).listen((data) => stdout.write('[chrome] $data'));
    p.stderr.transform(utf8.decoder).listen((data) => stderr.write('[chrome] $data'));
  } else {
    print('\n🚫 Το άνοιγμα στον Chrome ακυρώθηκε.');
  }
  isConfirmingBrowser = false;
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
  print('\n⏳ Εκκίνηση Attach... Ψάχνω για τη συσκευή...');
  String targetDevice = 'windows';
  try {
    final result = await Process.run('flutter', ['devices'], runInShell: true);
    if (result.stdout.toString().contains('L8AIB761L865GB7')) {
      targetDevice = 'L8AIB761L865GB7';
      print('📱 Βρέθηκε το κινητό! Σύνδεση με το υπάρχον App...');
    } else {
      print('💻 Το κινητό δεν βρέθηκε. Προεπιλογή στα Windows...');
    }
  } catch (e) {}

  final p = await Process.start('flutter', ['attach', '-d', targetDevice], runInShell: true);
  flutterProcesses.add(p);
  final logPrefix = targetDevice == 'windows' ? 'windows' : 'android';
  p.stdout.transform(utf8.decoder).listen((data) => stdout.write('[$logPrefix-attach] $data'));
  p.stderr.transform(utf8.decoder).listen((data) => stderr.write('[$logPrefix-attach] $data'));
}