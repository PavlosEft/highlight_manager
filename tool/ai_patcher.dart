import 'dart:io';
import 'dart:async';
import 'dart:convert';

void main() async {
  print('====================================================');
  print('🤖 AI PATCHER - Ενεργός και ακούει το Clipboard...');
  print('====================================================');
  
  String lastClipboard = await getClipboard();

  Timer.periodic(const Duration(seconds: 1), (timer) async {
    final clipboard = await getClipboard();
    if (clipboard.isNotEmpty && clipboard != lastClipboard && clipboard.contains('<HM_PATCH>')) {
      lastClipboard = clipboard;
      print('\n✨ [AI PATCHER] Νέος κώδικας εντοπίστηκε! Εφαρμογή...');
      
      bool success = applyPatch(clipboard);
      
      if (success) {
        // Ανίχνευση Action tag που στέλνει το AI
        final actionRegex = RegExp(r'<ACTION>(.*?)</ACTION>', dotAll: true);
        final actionMatch = actionRegex.firstMatch(clipboard);
        String action = 'RELOAD'; // Προεπιλογή αν δεν βρεθεί
        if (actionMatch != null) {
          action = actionMatch.group(1)!.trim().toUpperCase();
        }

        try {
          // Γράφει το timestamp ΜΑΖΙ με το action (χωρισμένα με |)
          File('tool/.trigger_reload').writeAsStringSync('${DateTime.now().toIso8601String()}|$action');
        } catch (_) {}
        print('✅ Το patch εφαρμόστηκε. Action: $action. Ο Dev Server ενημερώνεται αυτόματα.');
      } else {
        print('⚠️ Αποτυχία εφαρμογής. Ελέγξτε τα αρχεία.');
      }
    }
  });
  
  // Κρατάει το script ζωντανό και καθαρίζει στο κλείσιμο
  ProcessSignal.sigint.watch().listen((_) {
    exit(0);
  });
}

Future<String> getClipboard() async {
  try {
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