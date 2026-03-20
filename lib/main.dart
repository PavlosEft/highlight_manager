import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import 'package:window_manager/window_manager.dart';

// ==========================================
// 1. DATA MODELS (Τα δεδομένα μας)
// ==========================================

// Αφαιρέθηκε το Isolate: Η ανάλυση γίνεται on-the-fly μέσω FFmpeg ebur128!

class HighlightPhase {
  double timestamp;
  bool isHighlight;
  bool isSeen;
  bool isSelected;
  double? customStartOffset;
  double? customEndOffset;

  HighlightPhase({
    required this.timestamp,
    this.isHighlight = false,
    this.isSeen = false,
    this.isSelected = true,
    this.customStartOffset,
    this.customEndOffset,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp,
        'isHighlight': isHighlight,
        'isSeen': isSeen,
        'isSelected': isSelected,
        'customStartOffset': customStartOffset,
        'customEndOffset': customEndOffset,
      };

  factory HighlightPhase.fromJson(Map<String, dynamic> json) => HighlightPhase(
        timestamp: json['timestamp'].toDouble(),
        isHighlight: json['isHighlight'] ?? false,
        isSeen: json['isSeen'] ?? false,
        isSelected: json['isSelected'] ?? true,
        customStartOffset: json['customStartOffset']?.toDouble(),
        customEndOffset: json['customEndOffset']?.toDouble(),
      );
}

class Project {
  String id;
  String name;
  List<String> videoPaths;
  List<double> videoDurations;
  List<HighlightPhase> phases;
  DateTime createdAt;
  double totalDuration;
  double sensitivity;
  double grouping;
  double startOffset;
  double endOffset;
  bool autoplay;
  bool skipSeen;
  bool showHighlightsOnly;
  int lastActivePhaseIndex;
  int rotationPhaseLandscape;
  int rotationPhasePortrait;

  Project({
    required this.id,
    required this.name,
    required this.videoPaths,
    List<double>? videoDurations,
    List<HighlightPhase>? phases,
    DateTime? createdAt,
    this.totalDuration = 0.0,
    this.sensitivity = 55.0,
    this.grouping = 2.0,
    this.startOffset = 2.0,
    this.endOffset = 3.0,
    this.autoplay = false,
    this.skipSeen = false,
    this.showHighlightsOnly = false,
    this.lastActivePhaseIndex = -1,
    this.rotationPhaseLandscape = 0,
    this.rotationPhasePortrait = 0,
  })  : videoDurations = videoDurations ?? [],
        phases = phases ?? [],
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'videoPaths': videoPaths,
        'videoDurations': videoDurations,
        'phases': phases.map((e) => e.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'totalDuration': totalDuration,
        'sensitivity': sensitivity,
        'grouping': grouping,
        'startOffset': startOffset,
        'endOffset': endOffset,
        'autoplay': autoplay,
        'skipSeen': skipSeen,
        'showHighlightsOnly': showHighlightsOnly,
        'lastActivePhaseIndex': lastActivePhaseIndex,
        'rotationPhaseLandscape': rotationPhaseLandscape,
        'rotationPhasePortrait': rotationPhasePortrait,
      };

  factory Project.fromJson(Map<String, dynamic> json) => Project(
        id: json['id'],
        name: json['name'],
        videoPaths: List<String>.from(json['videoPaths']),
        videoDurations: json['videoDurations'] != null 
            ? List<double>.from(json['videoDurations'].map((x) => x.toDouble()))
            : [],
        phases: (json['phases'] as List)
            .map((e) => HighlightPhase.fromJson(e))
            .toList(),
        createdAt: DateTime.parse(json['createdAt']),
        totalDuration: json['totalDuration']?.toDouble() ?? 0.0,
        sensitivity: json['sensitivity']?.toDouble() ?? 55.0,
        grouping: json['grouping']?.toDouble() ?? 2.0,
        startOffset: json['startOffset']?.toDouble() ?? 2.0,
        endOffset: json['endOffset']?.toDouble() ?? 3.0,
        autoplay: json['autoplay'] ?? false,
        skipSeen: json['skipSeen'] ?? false,
        showHighlightsOnly: json['showHighlightsOnly'] ?? false,
        lastActivePhaseIndex: json['lastActivePhaseIndex'] ?? -1,
        rotationPhaseLandscape: json['rotationPhaseLandscape'] ?? 0,
        rotationPhasePortrait: json['rotationPhasePortrait'] ?? 0,
      );
}

// ==========================================
// 1.5 LOCALIZATION
// ==========================================
const Map<String, Map<String, String>> translations = {
  'el': {
    'title': 'Highlight Manager',
    'no_projects': 'Δεν υπάρχουν projects ακόμα.\nΠάτα το \'+\' για να ξεκινήσεις!',
    'new_project': 'Νέο Project',
    'cancel': 'Ακύρωση',
    'select_video': 'Επιλογή Βίντεο',
    'example_hint': 'π.χ. Αγώνας Κυριακής',
    'video_files': 'αρχεία βίντεο',
    'updated': 'Ανανεώθηκε:',
    'open_editor': 'Άνοιγμα Editor για:',
    'err_load': 'Σφάλμα φόρτωσης projects:',
    'err_save': 'Σφάλμα αποθήκευσης project:',
    'err_delete': 'Σφάλμα διαγραφής project:',
    'add_videos': 'Προσθήκη Βίντεο',
    'loading_files': 'Φόρτωση...',
    'clear_all': 'Καθαρισμός',
    'create_btn': 'ΔΗΜΙΟΥΡΓΙΑ',
    'duplicate_title': 'Υπάρχον Project',
    'duplicate_msg': 'Υπάρχει ήδη project με αυτά τα βίντεο ή όνομα. Θέλετε να δημιουργήσετε αντίγραφο;',
    'yes': 'Ναι',
    'no': 'Όχι',
    'delete_confirm_title': 'Διαγραφή Project',
    'delete_confirm_msg': 'Είστε σίγουροι ότι θέλετε να διαγράψετε αυτό το project; Η ενέργεια δεν αναιρείται.',
    'duration': 'Συνολική Διάρκεια:',
    'rename_project': 'Μετονομασία Project',
    'new_name': 'Νέο Όνομα',
    'save': 'Αποθήκευση',
    'editor_title': 'Επεξεργασία Project',
    'manual_add': 'Χειροκίνητη Προσθήκη',
    'pool_tab': 'Ανιχνευμένα',
    'high_tab': 'Highlights',
    'preparation': 'Προετοιμασία',
    'analysis_step': 'Ανάλυση {i}/{total}...',
    'time_label': 'Χρόνος',
    'progress_label': 'Πρόοδος',
    'eta_label': 'Εκτίμηση',
    'cancel_analysis': 'ΑΚΥΡΩΣΗ',
    'cancelling': 'ΑΚΥΡΩΝΕΤΑΙ...',
    'cancel_confirm_title': 'Ακύρωση Ανάλυσης',
    'cancel_confirm_msg': 'Είστε σίγουροι ότι θέλετε να διακόψετε την ανάλυση;',
  },
  'en': {
    'title': 'Highlight Manager',
    'no_projects': 'No projects yet.\nTap \'+\' to get started!',
    'new_project': 'New Project',
    'cancel': 'Cancel',
    'select_video': 'Select Video',
    'example_hint': 'e.g. Sunday Match',
    'video_files': 'video files',
    'updated': 'Updated:',
    'open_editor': 'Opening Editor for:',
    'err_load': 'Error loading projects:',
    'err_save': 'Error saving project:',
    'err_delete': 'Error deleting project:',
    'add_videos': 'Add Videos',
    'loading_files': 'Loading...',
    'clear_all': 'Clear All',
    'create_btn': 'CREATE',
    'duplicate_title': 'Existing Project',
    'duplicate_msg': 'A project with these videos or name already exists. Create a copy?',
    'yes': 'Yes',
    'no': 'No',
    'delete_confirm_title': 'Delete Project',
    'delete_confirm_msg': 'Are you sure you want to delete this project? This action cannot be undone.',
    'duration': 'Total Duration:',
    'rename_project': 'Rename Project',
    'new_name': 'New Name',
    'save': 'Save',
    'editor_title': 'Edit Project',
    'manual_add': 'Manual Add',
    'pool_tab': 'Detected',
    'high_tab': 'Highlights',
    'preparation': 'Preparation',
    'analysis_step': 'Analysis {i}/{total}...',
    'time_label': 'Time',
    'progress_label': 'Progress',
    'eta_label': 'ETA',
    'cancel_analysis': 'CANCEL',
    'cancelling': 'CANCELLING...',
    'cancel_confirm_title': 'Cancel Analysis',
    'cancel_confirm_msg': 'Are you sure you want to cancel the analysis?',
  }
};

// ==========================================
// 1.8 THEMES
// ==========================================

final lightTheme = ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple, brightness: Brightness.light),
  useMaterial3: true,
  typography: Typography.material2021(),
  cardTheme: CardThemeData(
    elevation: 2,
    margin: const EdgeInsets.only(bottom: 12),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ),
);

final darkTheme = ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple, brightness: Brightness.dark),
  useMaterial3: true,
  typography: Typography.material2021(),
  cardTheme: CardThemeData(
    elevation: 2,
    margin: const EdgeInsets.only(bottom: 12),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ),
);

// ==========================================
// 2. BACKEND / STATE MANAGEMENT
// ==========================================

Future<Map<String, dynamic>> _analyzePcmTask(Map<String, dynamic> args) async {
  final String path = args['path'];
  final double cumulativeTime = args['cumulativeTime'];
  
  final pcmFile = File(path);
  if (!pcmFile.existsSync()) return {'rms': <double>[], 'times': <double>[]};

  final bytes = pcmFile.readAsBytesSync();
  // Μετατροπή των bytes σε Native Int16 Array. Είναι ~100x πιο γρήγορο από το byteData.getInt16()
  final int16List = bytes.buffer.asInt16List(bytes.offsetInBytes, bytes.lengthInBytes ~/ 2);
  
  const sampleRate = 8000;
  // Προσομοίωση EBUR128 Momentary: Υπολογισμός κάθε 100ms (800 δείγματα),
  // αλλά εξετάζοντας "παράθυρο" 400ms (3200 δείγματα) για εξομάλυνση.
  const int stepSamples = 800; 
  const int windowSamples = 3200; 
  
  final int totalSteps = (int16List.length / stepSamples).ceil();
  List<double> isolateRms = List<double>.filled(totalSteps, 0.0);
  List<double> isolateTimes = List<double>.filled(totalSteps, 0.0);

  for (int step = 0; step < totalSteps; step++) {
    int startIdx = step * stepSamples;
    int endIdx = startIdx + windowSamples;
    if (endIdx > int16List.length) endIdx = int16List.length;
    if (startIdx >= int16List.length) break;
    
    double sumSquares = 0.0;
    for (int j = startIdx; j < endIdx; j++) {
      final double normalized = int16List[j] / 32768.0;
      sumSquares += normalized * normalized;
    }
    
    final int count = endIdx - startIdx;
    final rms = count > 0 ? math.sqrt(sumSquares / count) : 0.0;
    
    isolateRms[step] = rms; // Καθαρό γραμμικό RMS, όπως ακριβώς το υπολόγιζε η αρχική σου εξίσωση
    isolateTimes[step] = (startIdx / sampleRate) + cumulativeTime;
  }
  
  try { pcmFile.deleteSync(); } catch (_) {}
  
  return {'rms': isolateRms, 'times': isolateTimes};
}

class AppState extends ChangeNotifier {
  List<Project> projects = [];
  bool isLoading = true;
  String currentLang = 'en';
  bool isDarkMode = true;
  String appDirPath = '';

  String t(String key) => translations[currentLang]?[key] ?? key;

  void toggleLanguage() {
    currentLang = currentLang == 'el' ? 'en' : 'el';
    print('----------------------------------------------------');
    print('[USER ACTION] Γλώσσα άλλαξε σε: $currentLang');
    print('----------------------------------------------------');
    notifyListeners();
  }

  void toggleTheme() async {
    isDarkMode = !isDarkMode;
    print('----------------------------------------------------');
    print('[USER ACTION] Αλλαγή Theme. Dark Mode: $isDarkMode');
    print('----------------------------------------------------');
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isDarkMode', isDarkMode);
    } catch (_) {}
  }

  AppState() {
    _initApp();
  }

  Future<void> _initApp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      isDarkMode = prefs.getBool('isDarkMode') ?? true;
      final directory = await getApplicationDocumentsDirectory();
      appDirPath = '${directory.path}/HighlightManager';
    } catch (_) {}
    await loadAllProjects();
  }

  // Βρίσκει τον τοπικό φάκελο της εφαρμογής
  Future<Directory> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    final projDir = Directory('${directory.path}/HighlightManager');
    if (!await projDir.exists()) {
      await projDir.create(recursive: true);
    }
    return projDir;
  }

  // Φορτώνει όλα τα JSON αρχεία κατά την εκκίνηση (και κάνει migration αν χρειάζεται)
  Future<void> loadAllProjects() async {
    isLoading = true;
    notifyListeners();

    try {
      final dir = await _localPath;
      final entities = dir.listSync();
      
      projects.clear();
      for (var entity in entities) {
        if (entity is Directory) {
          final file = File('${entity.path}/project.json');
          if (await file.exists()) {
            final content = await file.readAsString();
            projects.add(Project.fromJson(jsonDecode(content)));
          }
        } else if (entity is File && entity.path.endsWith('.json') && !entity.path.contains('_analysis')) {
          // Migration παλιών flat αρχείων στον νέο φάκελο
          final content = await entity.readAsString();
          final p = Project.fromJson(jsonDecode(content));
          final pDir = Directory('${dir.path}/${p.id}');
          if (!await pDir.exists()) await pDir.create();
          await File('${pDir.path}/project.json').writeAsString(content);
          projects.add(p);
          try { await entity.delete(); } catch(_) {}
        }
      }
      
      projects.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (e) {
      debugPrint("${t('err_load')} $e");
    }

    isLoading = false;
    notifyListeners();
  }

  // Αποθηκεύει ακαριαία ένα Project στον δικό του φάκελο
  Future<void> saveProject(Project project) async {
    try {
      final dir = await _localPath;
      final pDir = Directory('${dir.path}/${project.id}');
      if (!await pDir.exists()) await pDir.create();
      
      final file = File('${pDir.path}/project.json');
      await file.writeAsString(jsonEncode(project.toJson()));
      
      if (!projects.any((p) => p.id == project.id)) {
        projects.insert(0, project);
      }
      notifyListeners();
    } catch (e) {
      debugPrint("${t('err_save')} $e");
    }
  }

  // Μετονομασία Project
  Future<void> renameProject(String id, String newName) async {
    final index = projects.indexWhere((p) => p.id == id);
    if (index != -1) {
      projects[index].name = newName;
      await saveProject(projects[index]);
    }
  }

  // Διαγραφή ολόκληρου του φακέλου του Project
  Future<void> deleteProject(String id) async {
    try {
      final dir = await _localPath;
      final projectDir = Directory('${dir.path}/$id');
      if (await projectDir.exists()) {
        await projectDir.delete(recursive: true);
      }
      projects.removeWhere((p) => p.id == id);
      notifyListeners();
    } catch (e) {
      debugPrint("${t('err_delete')} $e");
    }
  }

  // Έλεγχος για διπλότυπα projects
  bool hasDuplicateProject(String name, List<String> paths) {
    return projects.any((p) {
      if (p.name == name) return true;
      if (p.videoPaths.length == paths.length) {
        bool samePaths = true;
        for (int i = 0; i < paths.length; i++) {
          if (p.videoPaths[i] != paths[i]) samePaths = false;
        }
        if (samePaths) return true;
      }
      return false;
    });
  }

  bool _isAnalysisCancelled = false;
  List<Process> _activeFfmpegProcesses = [];

  void cancelAnalysis() {
    _isAnalysisCancelled = true;
    if (Platform.isWindows || Platform.isLinux) {
      for (var p in _activeFfmpegProcesses) p.kill();
    } else {
      FFmpegKit.cancel(); 
    }
  }

  Future<String> _getDesktopFFmpegPath() async {
    final devFile = File('assets/bin/ffmpeg.exe');
    if (devFile.existsSync()) return devFile.absolute.path;
    
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final releaseFile = File('$exeDir/ffmpeg.exe');
    if (releaseFile.existsSync()) return releaseFile.absolute.path;
    
    throw Exception('Δεν βρέθηκε το ffmpeg.exe!');
  }

  // Ανάλυση και δημιουργία Project με Progress Callback και Ακύρωση
  Future<Project?> analyzeAndCreateProject(String baseName, List<String> paths, Function(String, double) onStatusUpdate) async {
    _isAnalysisCancelled = false;
    String finalName = baseName;
    int counter = 1;
    
    while (projects.any((p) => p.name == finalName)) {
      finalName = '$baseName ($counter)';
      counter++;
    }

    final projectId = DateTime.now().millisecondsSinceEpoch.toString();
    final dir = await _localPath;
    final projectDir = Directory('${dir.path}/$projectId');
    await projectDir.create();

    double totalDur = 0.0;
    List<double> videoDurations = [];
    
    List<double> allRms = [];
    List<double> allTimes = [];
    double cumulativeTime = 0.0;
    
    int totalLines = 0;
    final totalStopwatch = Stopwatch()..start();

    try {
      print('\n[ANALYZE] Ξεκινάει η ανάλυση για: $finalName');
      final stepStopwatch = Stopwatch()..start();

      // 1ο Πέρασμα: Υπολογισμός Συνολικής Διάρκειας (Απαραίτητο για το συνολικό ποσοστό % progress)
      for (int i = 0; i < paths.length; i++) {
        if (_isAnalysisCancelled) throw Exception('Cancelled');
        
        String path = paths[i];
        onStatusUpdate(t('analysis_step').replaceAll('{i}', '${i + 1}').replaceAll('{total}', '${paths.length}'), 0.0);
        
        double dur = 0.0;
        final tempPlayer = Player();
        await tempPlayer.open(Media(path), play: false);
        for (int j = 0; j < 30; j++) {
          if (tempPlayer.state.duration != Duration.zero) break;
          await Future.delayed(const Duration(milliseconds: 100));
        }
        dur = tempPlayer.state.duration.inMilliseconds / 1000.0;
        await tempPlayer.dispose();
        
        if (dur <= 0.0) dur = 1.0; 

        totalDur += dur;
        videoDurations.add(dur);
      }

      print('[ANALYZE] Υπολογισμός διάρκειας ολοκληρώθηκε σε ${stepStopwatch.elapsedMilliseconds}ms. Συνολική διάρκεια: $totalDur s');
      stepStopwatch.reset();

      // 2ο Πέρασμα: Ανάλυση Ήχου
      for (int i = 0; i < paths.length; i++) {
        print('[ANALYZE] Ξεκινάει FFmpeg για αρχείο ${i + 1}/${paths.length}...');
        final fileStopwatch = Stopwatch()..start();

        if (_isAnalysisCancelled) throw Exception('Cancelled');
        
        String path = paths[i];
        double dur = videoDurations[i];
        
        _activeFfmpegProcesses.clear();
        
        List<double> currentRms = [];
        List<double> currentTimes = [];
        double currentTime = 0.0;
        
        final afFilter = "aformat=channel_layouts=mono,aresample=11025,asetnsamples=1024,astats=metadata=1:reset=1,ametadata=print:key=lavfi.astats.Overall.RMS_level";

        void processRmsLine(String line) {
          totalLines++;
          if (line.contains('lavfi.astats.Overall.RMS_level=')) {
            final strVal = line.split('=').last.trim();
            double? db = strVal == '-inf' ? -100.0 : double.tryParse(strVal);
            if (db != null) {
              double linear = db <= -100.0 ? 0.0 : math.pow(10, db / 20.0).toDouble();
              currentRms.add(linear);
              currentTimes.add(currentTime + cumulativeTime);
              currentTime += (1024.0 / 11025.0);
              
              if (currentRms.length % 50 == 0) {
                double globalProgress = (cumulativeTime + currentTime) / totalDur;
                onStatusUpdate(t('analysis_step').replaceAll('{i}', '${i + 1}').replaceAll('{total}', '${paths.length}'), globalProgress.clamp(0.0, 0.99));
              }
            }
          }
        }

        if (Platform.isWindows || Platform.isLinux) {
          final ffmpegExe = await _getDesktopFFmpegPath();
          final p = await Process.start(
            ffmpegExe,
            ['-y', '-threads', '4', '-i', path, '-vn', '-af', afFilter, '-f', 'null', '-'],
          );
          _activeFfmpegProcesses.add(p);
          
          p.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen(processRmsLine);
          
          final exitCode = await p.exitCode;
          print('[ANALYZE] Desktop FFmpeg ολοκληρώθηκε σε ${fileStopwatch.elapsedMilliseconds}ms (Exit: $exitCode)');
          if (exitCode != 0 && !_isAnalysisCancelled) throw Exception('FFmpeg failed');
          if (_isAnalysisCancelled) throw Exception('Cancelled');
        } else {
          String ffmpegPath = path;
          if (Platform.isAndroid && path.startsWith('content://')) {
             try {
               final saf = await FFmpegKitConfig.getSafParameterForRead(path);
               if (saf != null) ffmpegPath = saf;
             } catch (_) {}
          }

          final cmd = "-y -threads 4 -i \"$ffmpegPath\" -vn -af \"$afFilter\" -f null -";
          
          final completer = Completer<void>();
          FFmpegKit.executeAsync(
            cmd,
            (session) async {
              final returnCode = await session.getReturnCode();
              print('[ANALYZE] Mobile FFmpeg ολοκληρώθηκε σε ${fileStopwatch.elapsedMilliseconds}ms (Return Code: $returnCode)');
              if (ReturnCode.isCancel(returnCode) || _isAnalysisCancelled) {
                completer.completeError(Exception('Cancelled'));
              } else {
                completer.complete();
              }
            },
            (log) {
              final msg = log.getMessage();
              if (msg != null) {
                final lines = msg.split('\n');
                for (var line in lines) {
                  processRmsLine(line);
                }
              }
            }
          );
          await completer.future;
        }

        List<double> smoothedRms = [];
        for (int k = 0; k < currentRms.length; k++) {
           double sumSq = 0.0;
           int count = 0;
           for (int w = 0; w < 4; w++) {
             if (k + w < currentRms.length) {
               double r = currentRms[k + w];
               sumSq += (r * r);
               count++;
             }
           }
           smoothedRms.add(count > 0 ? math.sqrt(sumSq / count) : 0.0);
        }
        
        allRms.addAll(smoothedRms);
        allTimes.addAll(currentTimes);
        cumulativeTime += dur;
      }

      if (_isAnalysisCancelled) throw Exception('Cancelled');

      print('[ANALYZE] Συνολική Ανάλυση Ήχου ολοκληρώθηκε σε ${stepStopwatch.elapsedMilliseconds}ms');
      print('[TELEMETRY] Συνολικές γραμμές logs που επεξεργάστηκαν: $totalLines');
      onStatusUpdate(t('analysis_step').replaceAll('{i}', '${paths.length}').replaceAll('{total}', '${paths.length}'), 1.0);
      stepStopwatch.reset();
      
      double sumRms = 0.0;
      for (double r in allRms) {
        sumRms += r;
      }
      double avgRms = allRms.isEmpty ? 0.0 : sumRms / allRms.length;
      
      double maxRms = 0.0;
      if (allRms.isNotEmpty) {
        maxRms = allRms.reduce(math.max);
      }

      final analysisFile = File('${projectDir.path}/analysis.json');
      final analysisData = {
        'max_rms': maxRms,
        'avg_rms': avgRms,
        'times': allTimes,
        'rms': allRms,
      };
      await analysisFile.writeAsString(jsonEncode(analysisData));
      print('[TELEMETRY] Χρόνος εγγραφής JSON στο δίσκο: ${stepStopwatch.elapsedMilliseconds}ms');

      onStatusUpdate(t('analysis_step').replaceAll('{i}', '${paths.length}').replaceAll('{total}', '${paths.length}'), 0.95);
      try {
        List<Map<String, dynamic>> extractTasks = [];
        if (paths.length >= 4) {
          for(int i=0; i<4; i++) extractTasks.add({'path': paths[i], 'time': videoDurations[i] * 0.2});
        } else {
          for(int i=0; i<4; i++) extractTasks.add({'path': paths[0], 'time': videoDurations[0] * (0.1 + (i*0.2))});
        }

        for (int i=0; i<4; i++) {
          if (_isAnalysisCancelled) break;
          String outPath = '${projectDir.path}/thumb_$i.jpg';
          String inPath = extractTasks[i]['path'];
          double time = extractTasks[i]['time'];

          if (Platform.isWindows || Platform.isLinux) {
            final ffmpegExe = await _getDesktopFFmpegPath();
            await Process.run(ffmpegExe, ['-y', '-ss', time.toStringAsFixed(2), '-i', inPath, '-vframes', '1', '-vf', 'scale=320:-1', outPath]);
          } else {
            String safeInPath = inPath;
            if (Platform.isAndroid && inPath.startsWith('content://')) {
               try {
                 final saf = await FFmpegKitConfig.getSafParameterForRead(inPath);
                 if (saf != null) safeInPath = saf;
               } catch (_) {}
            }
            await FFmpegKit.execute("-y -ss ${time.toStringAsFixed(2)} -i \"$safeInPath\" -vframes 1 -vf scale=320:-1 \"$outPath\"");
          }
        }
      } catch (e) {
        print('[ANALYZE] Σφάλμα μικρογραφιών: $e');
      }

      // Υπολογισμός στόχου φάσεων: 250 φάσεις ανά 100 λεπτά (ή 2.5 φάσεις / λεπτό)
      double targetPhases = (totalDur / 60.0) * 2.5;
      if (targetPhases < 1) targetPhases = 1;
      
      double bestSensitivity = 55.0;
      double lowS = 1.0;
      double highS = 99.0;
      int bestCountDiff = 999999;
      
      // Αλγόριθμος εύρεσης ιδανικής ευαισθησίας (Binary Search)
      for (int iter = 0; iter < 12; iter++) {
        double midS = (lowS + highS) / 2;
        double level = maxRms - (midS / 100.0) * (maxRms - avgRms);
        int count = 0;
        double lastT = -999.0;
        
        for (int i = 0; i < allRms.length; i++) {
          if (allRms[i] > level) {
            if (allTimes[i] - lastT > 2.0) { // Default grouping test
              count++;
              lastT = allTimes[i];
            }
          }
        }
        
        int diff = (count - targetPhases).abs().toInt();
        if (diff < bestCountDiff) {
          bestCountDiff = diff;
          bestSensitivity = midS;
        }
        
        if (count > targetPhases) {
          highS = midS; // Έχουμε πολλές φάσεις -> ρίχνουμε το sensitivity
        } else {
          lowS = midS;  // Έχουμε λίγες φάσεις -> ανεβάζουμε το sensitivity
        }
      }

      final newProject = Project(
        id: projectId,
        name: finalName,
        videoPaths: paths,
        videoDurations: videoDurations,
        totalDuration: totalDur,
        sensitivity: bestSensitivity,
      );

      await saveProject(newProject);
      print('[ANALYZE] Δυναμική Ευαισθησία ρυθμίστηκε στο: ${bestSensitivity.toStringAsFixed(1)} (Στόχος φάσεων: ${targetPhases.toInt()})');
      print('[ANALYZE] ΟΛΟΚΛΗΡΟ ΤΟ PROJECT ΔΗΜΙΟΥΡΓΗΘΗΚΕ ΣΕ: ${totalStopwatch.elapsed.inSeconds} δευτερόλεπτα.');
      return newProject;

    } catch (e) {
      print('[ANALYZE] ΣΦΑΛΜΑ κατά την ανάλυση: $e');
      if (await projectDir.exists()) {
        await projectDir.delete(recursive: true);
      }
      return null;
    }
  }
}

// ==========================================
// 3. FRONTEND / UI
// ==========================================

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  print('\n🚀 [SYSTEM] Η ΕΦΑΡΜΟΓΗ ΞΕΚΙΝΗΣΕ ΚΑΙ Η ΣΥΝΔΕΣΗ ΜΕ ΤΟ ΤΕΡΜΑΤΙΚΟ ΕΙΝΑΙ ΕΝΕΡΓΗ!\n');
  
  // Ασπίδα προστασίας: Αν "σκάσει" κάτι, θα δείξει κόκκινη οθόνη με το σφάλμα αντί για μαύρη
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      child: Container(
        color: const Color(0xFF8B0000),
        padding: const EdgeInsets.all(16),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Text(
              details.exceptionAsString() + '\n\n' + (details.stack?.toString() ?? ''),
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  };

  try {
    MediaKit.ensureInitialized();
  } catch (e) {
    debugPrint('MediaKit init error: $e');
  }
  
  try {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      await windowManager.ensureInitialized();
      final prefs = await SharedPreferences.getInstance();
      final width = prefs.getDouble('win_w') ?? 1200.0;
      final height = prefs.getDouble('win_h') ?? 800.0;
      final posX = prefs.getDouble('win_x');
      final posY = prefs.getDouble('win_y');

      WindowOptions windowOptions = WindowOptions(
        size: Size(width, height),
        center: posX == null,
        title: 'Highlight Manager',
      );
      
      windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
        if (posX != null && posY != null) {
          await windowManager.setPosition(Offset(posX, posY));
        }
      });
    }
  } catch (e) {
    debugPrint('Window manager error: $e');
  }

  Widget app = const HighlightManagerApp();
  try {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      app = DesktopWindowWrapper(child: app);
    }
  } catch (_) {}

  runApp(
    ChangeNotifierProvider(
      create: (context) => AppState(),
      child: app,
    ),
  );
}

class HighlightManagerApp extends StatefulWidget {
  const HighlightManagerApp({super.key});

  @override
  State<HighlightManagerApp> createState() => _HighlightManagerAppState();
}

class DesktopWindowWrapper extends StatefulWidget {
  final Widget child;
  const DesktopWindowWrapper({super.key, required this.child});
  @override
  State<DesktopWindowWrapper> createState() => _DesktopWindowWrapperState();
}

class _DesktopWindowWrapperState extends State<DesktopWindowWrapper> with WindowListener {
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _saveTimer?.cancel();
    super.dispose();
  }

  void _saveWindowBounds() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), () async {
      final prefs = await SharedPreferences.getInstance();
      final size = await windowManager.getSize();
      final pos = await windowManager.getPosition();
      await prefs.setDouble('win_w', size.width);
      await prefs.setDouble('win_h', size.height);
      await prefs.setDouble('win_x', pos.dx);
      await prefs.setDouble('win_y', pos.dy);
    });
  }

  @override
  void onWindowResized() {
    _saveWindowBounds();
    setState(() {}); 
  }

  @override
  void onWindowMoved() => _saveWindowBounds();

  @override
  Widget build(BuildContext context) => widget.child;
}

class _HighlightManagerAppState extends State<HighlightManagerApp> {
  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppState>(context);
    return MaterialApp(
      title: 'Highlight Manager',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: state.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) {
        final size = MediaQuery.of(context).size;
        final isDesktop = size.width > 600;
        
        // Δυναμικός υπολογισμός scale βάσει πλάτους
        final double textScale = isDesktop 
            ? (size.width / 1200).clamp(1.0, 1.25) 
            : (size.width / 375).clamp(0.85, 1.15);

        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        );
      },
      home: const HomeScreen(),
    );
  }
}

class ProcessingDialog extends StatefulWidget {
  final AppState state;
  final String baseName;
  final List<String> paths;
  const ProcessingDialog({super.key, required this.state, required this.baseName, required this.paths});

  @override
  State<ProcessingDialog> createState() => _ProcessingDialogState();
}

class _ProcessingDialogState extends State<ProcessingDialog> {
  late String status;
  double progress = 0.0;
  bool isCancelled = false;
  DateTime? startTime;
  Timer? timer;
  String elapsedTimeStr = "00:00";
  String etaStr = "--:--";

  String _formatDuration(Duration d) {
    int m = d.inMinutes.remainder(60);
    int s = d.inSeconds.remainder(60);
    int h = d.inHours;
    if (h > 0) return "${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
    return "${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
  }

  @override
  void initState() {
    super.initState();
    status = widget.state.t('preparation');
    startTime = DateTime.now();
    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (mounted && startTime != null && !isCancelled && progress < 1.0) {
        final elapsed = DateTime.now().difference(startTime!);
        final elapsedSec = elapsed.inSeconds;
        
        setState(() {
          elapsedTimeStr = _formatDuration(elapsed);
          if (progress > 0.03) { 
            final totalEstimatedSec = elapsedSec / progress;
            final remainingSec = totalEstimatedSec - elapsedSec;
            etaStr = _formatDuration(Duration(seconds: remainingSec.toInt()));
          }
        });
      }
    });
    _startProcess();
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  void _startProcess() async {
    final project = await widget.state.analyzeAndCreateProject(
      widget.baseName,
      widget.paths,
      (newStatus, newProgress) {
        if (mounted) {
          setState(() {
            status = newStatus;
            progress = newProgress;
          });
        }
      }
    );
    if (mounted) {
      Navigator.pop(context, project);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 600;
    return AlertDialog(
      insetPadding: isDesktop ? const EdgeInsets.symmetric(horizontal: 40.0, vertical: 24.0) : const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(widget.state.t('preparation'), style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      content: SizedBox(
        width: isDesktop ? 400 : MediaQuery.of(context).size.width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(value: progress > 0 ? progress : null, minHeight: 6, borderRadius: BorderRadius.circular(4)),
            const SizedBox(height: 20),
            Text(status, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Column(
                  children: [
                    Text(widget.state.t('time_label'), style: const TextStyle(fontSize: 14, color: Colors.grey)),
                    const SizedBox(height: 4),
                    Text(elapsedTimeStr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  ],
                ),
                Column(
                  children: [
                    Text(widget.state.t('progress_label'), style: const TextStyle(fontSize: 14, color: Colors.grey)),
                    const SizedBox(height: 4),
                    Text('${(progress * 100).toStringAsFixed(1)}%', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  ],
                ),
                Column(
                  children: [
                    Text(widget.state.t('eta_label'), style: const TextStyle(fontSize: 14, color: Colors.grey)),
                    const SizedBox(height: 4),
                    Text(etaStr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: isCancelled ? null : () async {
            bool? confirm = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(widget.state.t('cancel_confirm_title'), style: const TextStyle(fontWeight: FontWeight.bold)),
                content: Text(widget.state.t('cancel_confirm_msg')),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(widget.state.t('no'))),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
                    child: Text(widget.state.t('yes')),
                  ),
                ],
              ),
            );
            if (confirm == true && mounted) {
              setState(() {
                isCancelled = true;
                status = widget.state.t('cancelling');
              });
              widget.state.cancelAnalysis();
            }
          },
          child: Text(isCancelled ? widget.state.t('cancelling') : widget.state.t('cancel_analysis'), style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16)),
        ),
      ],
    );
  }
}

class NewProjectDialog extends StatefulWidget {
  final AppState state;
  const NewProjectDialog({super.key, required this.state});

  @override
  State<NewProjectDialog> createState() => _NewProjectDialogState();
}

class _NewProjectDialogState extends State<NewProjectDialog> {
  final TextEditingController _nameController = TextEditingController();
  final List<String> _selectedPaths = [];
  final Map<String, String> _pathNames = {};
  bool _userEditedName = false;
  bool _isPickingFiles = false;

  static const platform = MethodChannel('com.example.highlight_manager/native_picker');

  void _pickFiles() async {
    if (_isPickingFiles) return;
    setState(() {
      _isPickingFiles = true;
    });

    try {
      if (Platform.isAndroid) {
        final List<dynamic>? result = await platform.invokeListMethod('pickVideos');
        if (result != null && result.isNotEmpty) {
          setState(() {
            for (var item in result) {
              final map = Map<String, String>.from(item);
              final path = map['path']!;
              final name = map['name']!;
              if (!_selectedPaths.contains(path)) {
                _selectedPaths.add(path);
                _pathNames[path] = name;
              }
            }
            _updateAutoName();
          });
        }
      } else {
        FilePickerResult? result = await FilePicker.platform.pickFiles(
          type: FileType.video,
          allowMultiple: true,
        );
        if (result != null && result.files.isNotEmpty) {
          setState(() {
            for (var file in result.files) {
              String? path = file.path;
              if (path != null && !_selectedPaths.contains(path)) {
                _selectedPaths.add(path);
                _pathNames[path] = file.name;
              }
            }
            _updateAutoName();
          });
        }
      }
    } catch (e) {
      debugPrint('Error picking files: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isPickingFiles = false;
        });
      }
    }
  }

  void _updateAutoName() {
    if (_userEditedName || _selectedPaths.isEmpty) return;
    
    List<String> baseNames = _selectedPaths.map((path) {
      String fileName = _pathNames[path] ?? path.split(RegExp(r'[\\/]')).last;
      return fileName.replaceAll(RegExp(r'\.[^.]*$'), ''); // Αφαίρεση κατάληξης (π.χ. .mp4)
    }).toList();

    _nameController.text = baseNames.join(' + ');
  }

  void _attemptCreate() async {
    if (_selectedPaths.isEmpty || _nameController.text.trim().isEmpty) return;
    
    final name = _nameController.text.trim();
    final state = widget.state;

    if (state.hasDuplicateProject(name, _selectedPaths)) {
      bool? proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(state.t('duplicate_title'), style: const TextStyle(fontWeight: FontWeight.bold)),
          content: Text(state.t('duplicate_msg')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(state.t('no'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(state.t('yes'))),
          ],
        ),
      );
      if (proceed != true) return;
    }

    Project? resultProject = await showDialog<Project?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ProcessingDialog(
        state: state,
        baseName: name,
        paths: _selectedPaths,
      ),
    );

    if (mounted && resultProject != null) {
      Navigator.pop(context);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => EditorScreen(project: resultProject),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.state.t;
    final isDesktop = MediaQuery.of(context).size.width > 600;
    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(horizontal: isDesktop ? 24.0 : 4.0, vertical: isDesktop ? 24.0 : 4.0),
      contentPadding: EdgeInsets.only(left: isDesktop ? 24.0 : 8.0, right: isDesktop ? 24.0 : 8.0, top: 16.0, bottom: isDesktop ? 24.0 : 0.0),
      actionsPadding: EdgeInsets.only(bottom: isDesktop ? 16.0 : 4.0, right: isDesktop ? 24.0 : 8.0, top: 8.0),
      title: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(t('new_project'), style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 600, maxHeight: MediaQuery.of(context).size.height * (isDesktop ? 0.9 : 0.98)),
        child: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            TextField(
              controller: _nameController,
              minLines: 1,
              maxLines: 4,
              keyboardType: TextInputType.multiline,
              onChanged: (v) => _userEditedName = v.isNotEmpty,
              decoration: InputDecoration(
                hintText: t('example_hint'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isPickingFiles ? null : _pickFiles,
                    icon: _isPickingFiles 
                        ? Container(width: 20, height: 20, padding: const EdgeInsets.all(2.0), child: const CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.folder_open),
                    label: Text(t(_isPickingFiles ? 'loading_files' : 'add_videos')),
                  ),
                ),
                if (_selectedPaths.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: () {
                      setState(() {
                        _selectedPaths.clear();
                        _userEditedName = false;
                        _nameController.clear();
                      });
                    },
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    tooltip: t('clear_all'),
                  ),
                ]
              ],
            ),
            const SizedBox(height: 16),
            if (_selectedPaths.isNotEmpty)
              Flexible(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.all(4.0),
                  child: ReorderableListView.builder(
                    shrinkWrap: true,
                  buildDefaultDragHandles: false,
                  itemCount: _selectedPaths.length,
                  onReorder: (oldIndex, newIndex) {
                    setState(() {
                      if (oldIndex < newIndex) newIndex -= 1;
                      final item = _selectedPaths.removeAt(oldIndex);
                      _selectedPaths.insert(newIndex, item);
                      if (!_userEditedName) _updateAutoName();
                    });
                  },
                  itemBuilder: (context, index) {
                    final path = _selectedPaths[index];
                    final fileName = _pathNames[path] ?? path.split(RegExp(r'[\\/]')).last;
                    return ReorderableDelayedDragStartListener(
                      key: ValueKey(path),
                      index: index,
                      child: Card(
                        margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 2.0),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ListTile(
                          visualDensity: VisualDensity.compact,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 0.0),
                          dense: true,
                          leading: CircleAvatar(
                            radius: 12,
                            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                            child: Text('${index + 1}', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onPrimaryContainer, fontWeight: FontWeight.bold)),
                          ),
                          title: Text(fileName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                          trailing: IconButton(
                            icon: Icon(Icons.delete_outline, size: 18, color: Theme.of(context).colorScheme.error),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              setState(() {
                                _selectedPaths.removeAt(index);
                                if (!_userEditedName) _updateAutoName();
                              });
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            )
          ],
        ),
      ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t('cancel')),
        ),
        FilledButton(
          onPressed: _selectedPaths.isEmpty || _nameController.text.trim().isEmpty ? null : _attemptCreate,
          style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary),
          child: Text(t('create_btn')),
        ),
      ],
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _showCreateProjectDialog(BuildContext context, AppState state) {
    print('----------------------------------------------------');
    print('[USER ACTION] Κλικ στο κουμπί Νέο Project');
    print('----------------------------------------------------');
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => NewProjectDialog(state: state),
    );
  }

  void _showRenameDialog(BuildContext context, Project project, AppState state) {
    final TextEditingController controller = TextEditingController(text: project.name);
    showDialog(
      context: context,
      builder: (ctx) {
        final isDesktop = MediaQuery.of(ctx).size.width > 600;
        return AlertDialog(
          insetPadding: EdgeInsets.symmetric(horizontal: isDesktop ? 24.0 : 12.0, vertical: 24.0),
          titlePadding: EdgeInsets.only(left: isDesktop ? 24.0 : 16.0, right: isDesktop ? 24.0 : 16.0, top: 16.0, bottom: 8.0),
          contentPadding: EdgeInsets.only(left: isDesktop ? 24.0 : 16.0, right: isDesktop ? 24.0 : 16.0, top: 8.0, bottom: 0.0),
          actionsPadding: EdgeInsets.only(bottom: 12.0, right: isDesktop ? 24.0 : 12.0, top: 12.0),
          title: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(state.t('rename_project'), style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(
                labelText: state.t('new_name'),
                border: const OutlineInputBorder(),
              ),
              autofocus: true,
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(state.t('cancel'))),
            FilledButton(
              onPressed: () {
                final newName = controller.text.trim();
                if (newName.isNotEmpty && newName != project.name) {
                  state.renameProject(project.id, newName);
                }
                Navigator.pop(ctx);
              },
              child: Text(state.t('save')),
            ),
          ],
        );
      },
    );
  }

  Widget _buildProjectCard(BuildContext context, Project project, AppState state) {
    final isDesktop = MediaQuery.of(context).size.width > 600 || Platform.isWindows || Platform.isMacOS || Platform.isLinux;

    String formatDuration(double totalSeconds) {
      if (totalSeconds <= 0) return "--:--";
      int h = totalSeconds ~/ 3600;
      int m = ((totalSeconds % 3600) ~/ 60);
      int s = (totalSeconds % 60).toInt();
      if (h > 0) return "${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
      return "${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
    }

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onLongPress: () => _showRenameDialog(context, project, state),
        onTap: () {
          print('----------------------------------------------------');
          print('[USER ACTION] Άνοιγμα Editor για το project: ${project.name}');
          print('----------------------------------------------------');
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => EditorScreen(project: project),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              // Πλαίσιο Thumbnail (4-πλό κολάζ)
              Container(
                width: 100,
                height: 64,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: File('${state.appDirPath}/${project.id}/thumb_0.jpg').existsSync()
                    ? Column(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Expanded(child: Image.file(File('${state.appDirPath}/${project.id}/thumb_0.jpg'), fit: BoxFit.cover, errorBuilder: (_,__,___) => Container(color: Colors.black12))),
                                const SizedBox(width: 2),
                                Expanded(child: Image.file(File('${state.appDirPath}/${project.id}/thumb_1.jpg'), fit: BoxFit.cover, errorBuilder: (_,__,___) => Container(color: Colors.black12))),
                              ],
                            ),
                          ),
                          const SizedBox(height: 2),
                          Expanded(
                            child: Row(
                              children: [
                                Expanded(child: Image.file(File('${state.appDirPath}/${project.id}/thumb_2.jpg'), fit: BoxFit.cover, errorBuilder: (_,__,___) => Container(color: Colors.black12))),
                                const SizedBox(width: 2),
                                Expanded(child: Image.file(File('${state.appDirPath}/${project.id}/thumb_3.jpg'), fit: BoxFit.cover, errorBuilder: (_,__,___) => Container(color: Colors.black12))),
                              ],
                            ),
                          ),
                        ],
                      )
                    : Center(
                        child: Icon(
                          Icons.movie_filter_rounded, 
                          size: 48, 
                          color: Theme.of(context).colorScheme.tertiary
                        ),
                      ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(project.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.movie_creation_outlined, size: 16, color: Colors.grey),
                            const SizedBox(width: 4),
                            Text('(${project.videoPaths.length})', style: const TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.access_time, size: 16, color: Colors.grey),
                                const SizedBox(width: 4),
                                Text(formatDuration(project.totalDuration), style: const TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text('${project.createdAt.day}/${project.createdAt.month}/${project.createdAt.year}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (isDesktop)
                IconButton(
                  icon: Icon(Icons.edit_outlined, color: Theme.of(context).colorScheme.primary),
                  onPressed: () => _showRenameDialog(context, project, state),
                  tooltip: state.t('rename_project'),
                ),
              IconButton(
                icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                onPressed: () async {
                  bool? confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(state.t('delete_confirm_title'), style: const TextStyle(fontWeight: FontWeight.bold)),
                      content: RichText(
                        text: TextSpan(
                          style: Theme.of(ctx).textTheme.bodyMedium,
                          children: [
                            TextSpan(text: '${state.t('delete_confirm_msg')}\n\n'),
                            TextSpan(text: project.name, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent)),
                          ],
                        ),
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(state.t('no'))),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
                          child: Text(state.t('yes')),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    print('----------------------------------------------------');
                    print('[USER ACTION] Διαγραφή project: ${project.name}');
                    print('----------------------------------------------------');
                    state.deleteProject(project.id);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppState>(context);
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 600;

    final horizontalPadding = isDesktop ? 16.0 : 8.0;
    final iconSize = isDesktop ? 28.0 : 24.0;
    final topActionFontSize = isDesktop ? 18.0 : 16.0;

    return Scaffold(
      appBar: AppBar(
        title: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(state.t('title'), style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        centerTitle: true,
        elevation: 2,
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report),
            tooltip: 'Εξαγωγή JSON Αναλύσεων',
            onPressed: () async {
              print('----------------------------------------------------');
              print('[USER ACTION] Πάτησες το "Ζουζούνι" (Bug Report / Export)');
              print('----------------------------------------------------');
              try {
                // Χρήση του εξωτερικού φακέλου της εφαρμογής που είναι ορατός μέσω USB
                final extDir = await getExternalStorageDirectory();
                if (extDir == null) {
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Δεν βρέθηκε εξωτερικός χώρος')));
                  return;
                }

                final exportPath = '${extDir.path}/JSON_Exports';
                final exportDir = Directory(exportPath);
                if (!exportDir.existsSync()) exportDir.createSync();

                final appDir = await getApplicationDocumentsDirectory();
                final hmDir = Directory('${appDir.path}/HighlightManager');
                int count = 0;

                if (hmDir.existsSync()) {
                  for (var entity in hmDir.listSync()) {
                    if (entity is Directory) {
                      final analysisFile = File('${entity.path}/analysis.json');
                      final projectFile = File('${entity.path}/project.json');
                      final errFile = File('${entity.path}/ffmpeg_error.txt');
                      if (analysisFile.existsSync() && projectFile.existsSync()) {
                        String pName = entity.path.split(Platform.pathSeparator).last;
                        try {
                          final pData = jsonDecode(projectFile.readAsStringSync());
                          pName = pData['name'] ?? pName;
                        } catch(_) {}
                        final safeName = pName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
                        
                        // Δημιουργία ξεχωριστού φακέλου για το Project
                        final projectExportDir = Directory('$exportPath/$safeName');
                        if (!projectExportDir.existsSync()) {
                          projectExportDir.createSync(recursive: true);
                        }
                        
                        // Εξαγωγή του Project (Backup) στον δικό του φάκελο
                        projectFile.copySync('${projectExportDir.path}/project.json');
                        
                        // Εξαγωγή της Ανάλυσης στον ίδιο φάκελο
                        if (analysisFile.existsSync()) {
                          analysisFile.copySync('${projectExportDir.path}/analysis.json');
                        }
                        
                        count++;
                      }
                    }
                  }
                }
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✅ Έγινε Backup $count Projects σε φακέλους!\nΒρίσκονται στο:\n$exportPath'),
                      duration: const Duration(seconds: 8),
                    )
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Σφάλμα: $e')));
                }
              }
            },
          ),
          IconButton(
            iconSize: iconSize,
            icon: Icon(state.isDarkMode ? Icons.wb_sunny : Icons.nightlight_round),
            onPressed: state.toggleTheme,
          ),
          TextButton(
            onPressed: state.toggleLanguage,
            child: Text(state.currentLang.toUpperCase(), style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold, fontSize: topActionFontSize)),
          ),
          SizedBox(width: horizontalPadding),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 12.0),
                  child: SizedBox(
                    width: double.infinity,
                    height: isDesktop ? 56 : 48,
                    child: FilledButton.icon(
                    onPressed: () => _showCreateProjectDialog(context, state),
                    icon: const Icon(Icons.add_to_photos_rounded, size: 28),
                    label: Text(state.t('new_project'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 0.5)),
                    style: FilledButton.styleFrom(
                      elevation: 4,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: state.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : state.projects.isEmpty
                        ? Center(
                            child: Text(
                              state.t('no_projects'),
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
                            ),
                          )
                        : ListView.builder(
                            padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 8),
                            itemCount: state.projects.length,
                            itemBuilder: (context, index) => _buildProjectCard(context, state.projects[index], state),
                          ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

// ==========================================
// 4. EDITOR SCREEN (Phase 2)
// ==========================================

class ExportSettingsDialog extends StatefulWidget {
  final String mode;
  const ExportSettingsDialog({super.key, required this.mode});

  @override
  State<ExportSettingsDialog> createState() => _ExportSettingsDialogState();
}

class _ExportSettingsDialogState extends State<ExportSettingsDialog> {
  bool compress = false;
  String transPath = '';
  double transDur = 1.0;

  @override
  Widget build(BuildContext context) {
    final title = widget.mode == 'join' ? 'Εξαγωγή Video (Join)' : 'Εξαγωγή Clips';
    return AlertDialog(
      title: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CheckboxListTile(
              title: const Text('Συμπίεση H.265 (Small Size)'),
              subtitle: const Text('Μειώνει το μέγεθος αρχείου. Η εξαγωγή θα διαρκέσει περισσότερο.'),
              value: compress,
              onChanged: (v) => setState(() => compress = v ?? false),
              contentPadding: EdgeInsets.zero,
            ),
            if (widget.mode == 'join') ...[
              const Divider(),
              const Text('Transition (Προαιρετικό)', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(transPath.isEmpty ? 'Εικόνα ή Video...' : transPath.split(RegExp(r'[\\/]')).last, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  IconButton(
                    icon: const Icon(Icons.folder_open),
                    onPressed: () async {
                      final res = await FilePicker.platform.pickFiles(
                        type: FileType.media,
                        withReadStream: Platform.isAndroid,
                      );
                      if (res != null && res.files.isNotEmpty) {
                        String? path = Platform.isAndroid ? res.files.single.identifier : res.files.single.path;
                        path ??= res.files.single.path;
                        if (path != null) {
                          setState(() => transPath = path!);
                        }
                      }
                    },
                  ),
                  if (transPath.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear, color: Colors.red),
                      onPressed: () => setState(() => transPath = ''),
                    ),
                ],
              ),
              if (transPath.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Διάρκεια:'),
                    Expanded(
                      child: Slider(
                        value: transDur,
                        min: 0.1,
                        max: 2.0,
                        divisions: 19,
                        label: '${transDur.toStringAsFixed(1)}s',
                        onChanged: (v) => setState(() => transDur = v),
                      ),
                    ),
                    Text('${transDur.toStringAsFixed(1)}s'),
                  ],
                ),
              ],
            ]
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('ΑΚΥΡΩΣΗ')),
        FilledButton(
          onPressed: () => Navigator.pop(context, {
            'compress': compress,
            'trans_path': transPath,
            'trans_dur': transDur,
          }),
          child: const Text('ΕΞΑΓΩΓΗ'),
        ),
      ],
    );
  }
}

class ExportProgressDialog extends StatefulWidget {
  final Project project;
  final List<HighlightPhase> highlights;
  final Map<String, dynamic> config;
  final String mode;
  final String outDir;
  final double startOffset;
  final double endOffset;

  const ExportProgressDialog({
    super.key,
    required this.project,
    required this.highlights,
    required this.config,
    required this.mode,
    required this.outDir,
    required this.startOffset,
    required this.endOffset,
  });

  @override
  State<ExportProgressDialog> createState() => _ExportProgressDialogState();
}

class _ExportProgressDialogState extends State<ExportProgressDialog> {
  String status = "Προετοιμασία...";
  double progress = 0.0;
  bool isFinished = false;
  bool isCancelled = false;
  Process? _activeProcess;

  @override
  void initState() {
    super.initState();
    _startExport();
  }

  ({String path, double localSeconds}) _getLocalVideoData(double globalSeconds) {
    if (widget.project.videoPaths.isEmpty) return (path: '', localSeconds: 0.0);
    if (widget.project.videoDurations.isEmpty) return (path: widget.project.videoPaths.first, localSeconds: globalSeconds);

    double accumulated = 0.0;
    for (int i = 0; i < widget.project.videoDurations.length; i++) {
      double dur = widget.project.videoDurations[i];
      if (globalSeconds <= accumulated + dur || i == widget.project.videoDurations.length - 1) {
        double localSec = globalSeconds - accumulated;
        if (localSec < 0) localSec = 0;
        return (path: widget.project.videoPaths[i], localSeconds: localSec);
      }
      accumulated += dur;
    }
    return (path: widget.project.videoPaths.last, localSeconds: 0.0);
  }

  void _cancel() {
    setState(() {
      isCancelled = true;
      status = "Ακύρωση...";
    });
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      _activeProcess?.kill();
    } else {
      FFmpegKit.cancel();
    }
  }

  Future<String> _getDesktopFFmpegPath() async {
    final devFile = File('assets/bin/ffmpeg.exe');
    if (devFile.existsSync()) return devFile.absolute.path;
    
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final releaseFile = File('$exeDir/ffmpeg.exe');
    if (releaseFile.existsSync()) return releaseFile.absolute.path;
    
    throw Exception('Δεν βρέθηκε το ffmpeg.exe!');
  }

  Future<int> _runFFmpeg(List<String> args) async {
    if (isCancelled) return 255;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final ffmpegExe = await _getDesktopFFmpegPath();
      _activeProcess = await Process.start(ffmpegExe, args);
      _activeProcess!.stdout.drain();
      _activeProcess!.stderr.drain();
      return await _activeProcess!.exitCode;
    } else {
      List<String> safeArgs = [];
      for (String arg in args) {
        if (Platform.isAndroid && arg.startsWith('content://')) {
          try {
            final saf = await FFmpegKitConfig.getSafParameterForRead(arg);
            safeArgs.add(saf ?? arg);
          } catch (_) {
            safeArgs.add(arg);
          }
        } else {
          safeArgs.add(arg);
        }
      }
      final session = await FFmpegKit.executeWithArguments(safeArgs);
      final returnCode = await session.getReturnCode();
      if (returnCode?.isValueSuccess() != true) {
        final logs = await session.getAllLogsAsString();
        try {
          final dir = await getApplicationDocumentsDirectory();
          final errFile = File('${dir.path}/HighlightManager/${widget.project.id}/ffmpeg_error.txt');
          await errFile.writeAsString('CMD: ${safeArgs.join(' ')}\n\nLOGS:\n$logs');
        } catch (_) {}
      }
      return returnCode?.isValueSuccess() == true ? 0 : 1;
    }
  }

  Future<void> _startExport() async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      Directory tempDir;
      if (Platform.isAndroid || Platform.isIOS) {
        final appDir = await getTemporaryDirectory();
        tempDir = Directory('${appDir.path}/temp_$timestamp');
      } else {
        tempDir = Directory('${widget.outDir}/temp_$timestamp');
      }
      await tempDir.create(recursive: true);

      final isCompress = widget.config['compress'] as bool;
      
      List<String> videoParams;
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        videoParams = isCompress 
            ? ['-c:v', 'libx265', '-crf', '26', '-preset', 'medium', '-tag:v', 'hvc1']
            : ['-c:v', 'libx264', '-preset', 'ultrafast', '-crf', '23'];
      } else {
        videoParams = isCompress 
            ? ['-c:v', 'mpeg4', '-q:v', '10']
            : ['-c:v', 'mpeg4', '-q:v', '2'];
      }

      if (widget.mode == 'separate') {
        final clipsDir = Directory('${widget.outDir}/${widget.project.name}_clips_$timestamp');
        try { await clipsDir.create(); } catch (_) {}

        for (int i = 0; i < widget.highlights.length; i++) {
          if (isCancelled) throw Exception('Cancelled');
          setState(() {
            status = "Εξαγωγή ${i + 1}/${widget.highlights.length}...";
            progress = i / widget.highlights.length;
          });

          final ts = widget.highlights[i].timestamp;
          final cStart = widget.highlights[i].customStartOffset ?? widget.startOffset;
          final cEnd = widget.highlights[i].customEndOffset ?? widget.endOffset;
          final startGlobal = math.max(0.0, ts - cStart);
          final localData = _getLocalVideoData(startGlobal);
          final dur = cStart + cEnd + 0.5;
          final tempOutPath = '${tempDir.path}/clip_${i + 1}.mp4';
          final finalOutPath = '${clipsDir.path}/clip_${i + 1}.mp4';

          final args = [
            '-y', '-ss', localData.localSeconds.toStringAsFixed(3), '-i', localData.path, '-t', dur.toString(),
            ...videoParams, '-c:a', 'aac', tempOutPath
          ];
          
          final code = await _runFFmpeg(args);
          if (code != 0 && !isCancelled) throw Exception('FFmpeg error');
          
          try {
            await File(tempOutPath).copy(finalOutPath);
          } catch (e) {
            throw Exception('Αποτυχία αποθήκευσης στο φάκελο: $e');
          }
        }
      } else {
        List<String> processedClips = [];
        final transPath = widget.config['trans_path'] as String;
        final transDur = widget.config['trans_dur'] as double;
        String transTemp = '';

        if (transPath.isNotEmpty) {
          setState(() => status = "Προετοιμασία Transition...");
          transTemp = '${tempDir.path}/trans.mp4';
          final isImage = transPath.toLowerCase().endsWith('.jpg') || transPath.toLowerCase().endsWith('.png');
          
          List<String> trArgs = ['-y'];
          if (isImage) trArgs.addAll(['-loop', '1']);
          trArgs.addAll([
            '-i', transPath,
            '-vf', 'scale=1920:1080:force_original_aspect_ratio=increase,crop=1920:1080',
            '-t', transDur.toString(),
            ...videoParams, '-c:a', 'aac', '-f', 'mp4', transTemp
          ]);
          await _runFFmpeg(trArgs);
        }

        for (int i = 0; i < widget.highlights.length; i++) {
          if (isCancelled) throw Exception('Cancelled');
          setState(() {
            status = "Προετοιμασία ${i + 1}/${widget.highlights.length}...";
            progress = i / widget.highlights.length * 0.9;
          });

          final ts = widget.highlights[i].timestamp;
          final cStart = widget.highlights[i].customStartOffset ?? widget.startOffset;
          final cEnd = widget.highlights[i].customEndOffset ?? widget.endOffset;
          final startGlobal = math.max(0.0, ts - cStart);
          final localData = _getLocalVideoData(startGlobal);
          final dur = cStart + cEnd + 0.5;
          final clipTemp = '${tempDir.path}/part_$i.mp4';

          final args = [
            '-y', '-ss', localData.localSeconds.toStringAsFixed(3), '-i', localData.path, '-t', dur.toString(),
            ...videoParams, '-c:a', 'aac', '-vf', 'scale=1920:1080', clipTemp
          ];
          final code = await _runFFmpeg(args);
          if (code != 0 && !isCancelled) throw Exception('FFmpeg error');
          processedClips.add(clipTemp);
        }

        if (isCancelled) throw Exception('Cancelled');
        setState(() {
          status = "Ένωση αρχείων (Finalizing)...";
          progress = 0.95;
        });

        final listFile = File('${tempDir.path}/inputs.txt');
        String listContent = '';
        for (int i = 0; i < processedClips.length; i++) {
          // Χρήση σχετικών μονοπατιών (relative paths) για αποφυγή σφαλμάτων demuxer στο Android
          listContent += "file 'part_$i.mp4'\n";
          if (transTemp.isNotEmpty && i < processedClips.length - 1) {
            listContent += "file 'trans.mp4'\n";
          }
        }
        await listFile.writeAsString(listContent, flush: true);

        final mergedOutTemp = '${tempDir.path}/merged_$timestamp.mp4';
        final mergedOutFinal = '${widget.outDir}/${widget.project.name}_merged_$timestamp.mp4';
        
        final catArgs = [
          '-y', '-f', 'concat', '-safe', '0', '-i', listFile.path, '-c', 'copy', mergedOutTemp
        ];
        final code = await _runFFmpeg(catArgs);
        if (code != 0 && !isCancelled) throw Exception('FFmpeg error concat');
        
        try {
          await File(mergedOutTemp).copy(mergedOutFinal);
        } catch (e) {
          throw Exception('Αποτυχία αποθήκευσης στο φάκελο: $e');
        }
        
        try { await tempDir.delete(recursive: true); } catch (_) {}
      }

      if (isCancelled) throw Exception('Cancelled');
      setState(() {
        status = "Ολοκληρώθηκε!";
        progress = 1.0;
        isFinished = true;
      });
    } catch (e) {
      if (!isCancelled) {
        setState(() {
          status = "Σφάλμα: $e";
          isFinished = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(isFinished ? 'Ολοκληρώθηκε' : 'Επεξεργασία...', style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(status, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 8),
          Text('${(progress * 100).toInt()}%', style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
      actions: [
        if (!isFinished)
          TextButton(
            onPressed: isCancelled ? null : _cancel,
            child: Text(isCancelled ? 'ΑΚΥΡΩΝΕΤΑΙ...' : 'ΑΚΥΡΩΣΗ', style: const TextStyle(color: Colors.red)),
          )
        else
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ΚΛΕΙΣΙΜΟ'),
          ),
      ],
    );
  }
}

class EditorScreen extends StatefulWidget {
  final Project project;
  const EditorScreen({super.key, required this.project});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final Player player;
  late final VideoController controller;

  StreamSubscription? playingSub;
  StreamSubscription? durationSub;
  StreamSubscription? positionSub;

  bool isPlaying = false;
  Duration duration = Duration.zero;
  double globalPositionSeconds = 0.0;
  final ValueNotifier<double> globalPositionNotifier = ValueNotifier<double>(0.0);
  
  int activePhaseIndex = -1;
  HighlightPhase? currentPlayingPhase;
  bool isTrackingPhase = false;
  bool isAutoplaySuspended = false;
  bool isSeeking = false;
  bool isFullscreen = false;
  
  List<HighlightPhase> historyStack = [];
  List<HighlightPhase> forwardStack = [];

  // --- UI Settings State ---
  late double sensitivity;
  late double grouping;
  late double startOffset;
  late double endOffset;
  late bool autoplay;
  late bool skipSeen;
  
  // --- Filters ---
  late bool showHighlightsOnly;

  // --- Analysis Data ---
  List<double> rmsData = [];
  List<double> timesData = [];
  double maxRms = 0.0;
  double avgRms = 0.0;
  bool isLoadingAnalysis = true;

  final ScrollController _listScrollController = ScrollController();
  double _sidebarWidth = 400.0;

  @override
  void initState() {
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) {
        setState(() {
          _sidebarWidth = prefs.getDouble('sidebar_width') ?? 400.0;
        });
      }
    });
    super.initState();
    sensitivity = widget.project.sensitivity;
    grouping = widget.project.grouping;
    startOffset = widget.project.startOffset;
    endOffset = widget.project.endOffset;
    autoplay = widget.project.autoplay;
    skipSeen = widget.project.skipSeen;
    showHighlightsOnly = widget.project.showHighlightsOnly;

    player = Player();
    controller = VideoController(
      player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true,
      ),
    );

    isPlaying = player.state.playing;
    duration = player.state.duration;

    // Listeners για την ανανέωση των Custom Controls (με έλεγχο mounted)
    playingSub = player.stream.playing.listen((p) {
      if (mounted) setState(() => isPlaying = p);
    });
    durationSub = player.stream.duration.listen((d) {
      if (mounted) setState(() => duration = d);
    });
    
    if (widget.project.videoDurations.isEmpty && widget.project.videoPaths.isNotEmpty) {
      double avg = widget.project.totalDuration / widget.project.videoPaths.length;
      widget.project.videoDurations = List.filled(widget.project.videoPaths.length, avg);
    }

    positionSub = player.stream.position.listen((pos) {
      if (!mounted) return;
      
      int currentIndex = player.state.playlist.index;
      if (currentIndex < 0) currentIndex = 0;
      
      double accumulated = 0.0;
      for (int i = 0; i < currentIndex && i < widget.project.videoDurations.length; i++) {
        accumulated += widget.project.videoDurations[i];
      }
      
      double currentGlobalSec = accumulated + (pos.inMilliseconds / 1000.0);
      globalPositionSeconds = currentGlobalSec;
      globalPositionNotifier.value = currentGlobalSec;

      if (isPlaying && !isSeeking) {
        bool isCurrentlyInHighlight = false;
        for (var phase in widget.project.phases) {
          if (phase.isHighlight) {
            double start = math.max(0.0, phase.timestamp - (phase.customStartOffset ?? startOffset));
            double end = phase.timestamp + (phase.customEndOffset ?? endOffset);
            if (currentGlobalSec >= start && currentGlobalSec <= end) {
              isCurrentlyInHighlight = true;
              break;
            }
          }
        }
        
        if (_autoStarFeedback != isCurrentlyInHighlight) {
          setState(() => _autoStarFeedback = isCurrentlyInHighlight);
        }
      }

      if (!isPlaying || currentPlayingPhase == null || !isTrackingPhase || isSeeking) return;
      
      final targetEnd = currentPlayingPhase!.timestamp + (currentPlayingPhase!.customEndOffset ?? endOffset);

      if (currentGlobalSec >= targetEnd) {
        if (currentGlobalSec > targetEnd + 2.0) return; // Αποτροπή skip από stream delay glitches (media_kit)
        
        if (autoplay && !isAutoplaySuspended) {
          _navigate(1, isAuto: true);
        } else if (showHighlightsOnly && currentPlayingPhase!.isHighlight && isTrackingPhase) {
          player.pause();
        }
      }
    });
    
    if (widget.project.videoPaths.isNotEmpty) {
      final playlist = Playlist(widget.project.videoPaths.map((p) => Media(p)).toList());
      player.open(playlist, play: false);
    }
    
    _loadAnalysisData();
  }

  Future<void> _loadAnalysisData() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final pDir = Directory('${dir.path}/HighlightManager/${widget.project.id}');
      final file = File('${pDir.path}/analysis.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final data = jsonDecode(content);
        maxRms = data['max_rms']?.toDouble() ?? 0.0;
        avgRms = data['avg_rms']?.toDouble() ?? 0.0;
        rmsData = List<double>.from(data['rms'].map((x) => x.toDouble()));
        timesData = List<double>.from(data['times'].map((x) => x.toDouble()));

        if (widget.project.phases.isEmpty) {
          _recalcPhases();
        }
      }
    } catch (e) {
      debugPrint("Error loading analysis: $e");
    } finally {
      if (mounted) {
        setState(() => isLoadingAnalysis = false);
        if (widget.project.lastActivePhaseIndex >= 0 && widget.project.lastActivePhaseIndex < widget.project.phases.length) {
          setState(() {
            currentPlayingPhase = widget.project.phases[widget.project.lastActivePhaseIndex];
            activePhaseIndex = _filteredPhases.indexOf(currentPlayingPhase!);
          });
          _scrollToActivePhase();
        }
      }
    }
  }

  void _recalcPhases() {
    if (rmsData.isEmpty) return;
    
    // Μαθηματικός τύπος από την παλιά Python εφαρμογή
    double level = maxRms - (sensitivity / 100.0) * (maxRms - avgRms);
    List<double> rawTimes = [];
    for (int i = 0; i < rmsData.length; i++) {
      if (rmsData[i] > level) rawTimes.add(timesData[i]);
    }
    
    // Ομαδοποίηση (Grouping)
    List<double> grouped = [];
    if (rawTimes.isNotEmpty) {
      grouped.add(rawTimes[0]);
      for (int i = 1; i < rawTimes.length; i++) {
        if (rawTimes[i] - grouped.last > grouping) {
          grouped.add(rawTimes[i]);
        }
      }
    }

    List<HighlightPhase> finalPhases = [];
    
    // 1. Διατηρούμε όσα έχει κάνει ρητά Highlight ο χρήστης
    final existingHighlights = widget.project.phases.where((p) => p.isHighlight).toList();
    finalPhases.addAll(existingHighlights);

    // 2. Εισάγουμε τις νέες φάσεις, ελέγχοντας αν προϋπάρχουν και αν ήταν "Seen"
    for (double t in grouped) {
      bool isAlreadyHighlight = finalPhases.any((p) => (p.timestamp - t).abs() < 0.5);
      if (!isAlreadyHighlight) {
        bool wasSeen = widget.project.phases.any((p) => !p.isHighlight && p.isSeen && (p.timestamp - t).abs() < 0.5);
        finalPhases.add(HighlightPhase(timestamp: t, isHighlight: false, isSeen: wasSeen));
      }
    }

    setState(() {
      widget.project.phases = finalPhases;
    });
  }

  List<HighlightPhase> get _filteredPhases {
    if (showHighlightsOnly) {
      return widget.project.phases.where((p) => p.isHighlight).toList();
    } else {
      final list = widget.project.phases.toList();
      list.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      return list;
    }
  }

  void _navigate(int direction, {bool isAuto = false}) {
    final phases = _filteredPhases;
    if (phases.isEmpty) return;
    
    if (direction == -1 && historyStack.isNotEmpty) {
      if (currentPlayingPhase != null) forwardStack.add(currentPlayingPhase!);
      final prevPhase = historyStack.removeLast();
      int idx = phases.indexOf(prevPhase);
      if (idx != -1) {
        _playPhase(idx, phases, recordHistory: false);
        return;
      }
    } else if (direction == 1 && !isAuto && forwardStack.isNotEmpty) {
      if (currentPlayingPhase != null) historyStack.add(currentPlayingPhase!);
      final nextPhase = forwardStack.removeLast();
      int idx = phases.indexOf(nextPhase);
      if (idx != -1) {
        _playPhase(idx, phases, recordHistory: false);
        return;
      }
    }
    
    int newIndex = activePhaseIndex + direction;
    
    if (direction == 1 && skipSeen) {
      while (newIndex < phases.length && phases[newIndex].isSeen) {
        newIndex++;
      }
    }
    
    if (newIndex >= 0 && newIndex < phases.length) {
      _playPhase(newIndex, phases, recordHistory: !isAuto);
    } else {
      player.pause();
    }
  }

  Future<void> _seekGlobal(double targetSeconds) async {
    bool wasPlaying = isPlaying;
    double accumulated = 0.0;
    for (int i = 0; i < widget.project.videoDurations.length; i++) {
      double dur = widget.project.videoDurations[i];
      if (targetSeconds <= accumulated + dur || i == widget.project.videoDurations.length - 1) {
        double localSeconds = targetSeconds - accumulated;
        if (localSeconds < 0) localSeconds = 0;
        
        if (player.state.playlist.index != i) {
          await player.pause();
          await player.jump(i);
          
          // Force a safe delay to allow media_kit to fully load the new video pipeline
          await Future.delayed(const Duration(milliseconds: 600));
          
          await player.seek(Duration(milliseconds: (localSeconds * 1000).toInt()));
          if (wasPlaying) {
            await player.play();
          }
        } else {
          await player.seek(Duration(milliseconds: (localSeconds * 1000).toInt()));
        }
        break;
      }
      accumulated += dur;
    }
  }

  void _scrollToActivePhase() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (currentPlayingPhase == null) return;
      
      final context = GlobalObjectKey(currentPlayingPhase!).currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
          alignment: 0.5, // Απόλυτο κεντράρισμα ανεξαρτήτως ύψους
        );
      }
    });
  }

  Future<void> _playPhase(int index, List<HighlightPhase> phases, {bool recordHistory = true}) async {
    if (index < 0 || index >= phases.length) return;
    
    if (recordHistory && currentPlayingPhase != null) {
      historyStack.add(currentPlayingPhase!);
      forwardStack.clear();
    }
    
    setState(() {
      activePhaseIndex = index;
      currentPlayingPhase = phases[index];
      currentPlayingPhase!.isSeen = true;
      isTrackingPhase = true;
      isAutoplaySuspended = false;
      isSeeking = true;
    });

    widget.project.lastActivePhaseIndex = widget.project.phases.indexOf(currentPlayingPhase!);

    _scrollToActivePhase();
    
    Provider.of<AppState>(context, listen: false).saveProject(widget.project);
    
    double startSeconds = math.max(0.0, currentPlayingPhase!.timestamp - (currentPlayingPhase!.customStartOffset ?? startOffset));
    print('[PLAYBACK] Starting phase at ${startSeconds.toStringAsFixed(2)}s globally');
    await _seekGlobal(startSeconds);
    if (mounted) {
      setState(() {
        isSeeking = false;
      });
    }
    player.play();
  }

  @override
  void dispose() {
    if (isFullscreen) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    _seekTimer?.cancel();
    playingSub?.cancel();
    durationSub?.cancel();
    positionSub?.cancel();
    player.dispose();
    _listScrollController.dispose();
    globalPositionNotifier.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    int h = d.inHours;
    int m = d.inMinutes.remainder(60);
    int s = d.inSeconds.remainder(60);
    if (h > 0) return "${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
    return "${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
  }

  void _adjustOffset(HighlightPhase phase, String type, double delta, AppState state) {
    setState(() {
      if (type == 'start') {
        double current = phase.customStartOffset ?? startOffset;
        phase.customStartOffset = math.max(0.0, current + delta);
      } else {
        double current = phase.customEndOffset ?? endOffset;
        phase.customEndOffset = math.max(0.0, current + delta);
      }
      currentPlayingPhase = phase;
      activePhaseIndex = _filteredPhases.indexOf(phase);
      phase.isSeen = true;
      isTrackingPhase = true;
      isAutoplaySuspended = false;
      isSeeking = true;
    });
    state.saveProject(widget.project);
    
    double previewStart = math.max(0.0, phase.timestamp - (phase.customStartOffset ?? startOffset));
    if (type == 'end') {
      double previewEnd = phase.timestamp + (phase.customEndOffset ?? endOffset);
      previewStart = math.max(0.0, previewEnd - 2.0);
    }
    
    _seekGlobal(previewStart).then((_) {
      if (mounted) {
        setState(() {
          isSeeking = false;
        });
      }
      player.play();
    });
  }

  void _addManualHighlight() {
    final state = Provider.of<AppState>(context, listen: false);
    final currentPos = globalPositionSeconds;
    print('----------------------------------------------------');
    print('[USER ACTION] Χειροκίνητο Highlight στο ${currentPos.toStringAsFixed(2)}s');
    print('----------------------------------------------------');
    
    setState(() {
      widget.project.phases.add(HighlightPhase(
        timestamp: currentPos,
        isHighlight: true,
      ));
    });
    
    state.saveProject(widget.project);
  }

  bool _areAllHighlightsSelected() {
    final highlights = widget.project.phases.where((p) => p.isHighlight);
    if (highlights.isEmpty) return false;
    return highlights.every((p) => p.isSelected);
  }

  void _toggleAllHighlights(bool? val) {
    final bool select = val ?? true;
    setState(() {
      for (var p in widget.project.phases.where((p) => p.isHighlight)) {
        p.isSelected = select;
      }
    });
    Provider.of<AppState>(context, listen: false).saveProject(widget.project);
  }

  void _resetSeen() {
    setState(() {
      for (var p in widget.project.phases) {
        p.isSeen = false;
      }
    });
    Provider.of<AppState>(context, listen: false).saveProject(widget.project);
  }

  Widget _buildVideoPlayer(BuildContext context) {
    return Column(
      children: [
        // Βίντεο με Tap για Play/Pause (Κανένα άλλο Control)
        Expanded(
          child: GestureDetector(
            onTap: () => player.playOrPause(),
            child: Container(
              color: Colors.black,
              child: Center(
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Video(
                    controller: controller,
                    controls: NoVideoControls, // Απενεργοποίηση προεπιλεγμένων Controls
                  ),
                ),
              ),
            ),
          ),
        ),
        // Custom Μόνιμα Controls από κάτω
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Row(
            children: [
              IconButton(
                iconSize: 32,
                color: Theme.of(context).colorScheme.primary,
                icon: const Icon(Icons.skip_previous),
                onPressed: () => _navigate(-1),
              ),
              IconButton(
                iconSize: 42,
                color: Theme.of(context).colorScheme.primary,
                icon: Icon(isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill),
                onPressed: () => player.playOrPause(),
              ),
              IconButton(
                iconSize: 32,
                color: Theme.of(context).colorScheme.primary,
                icon: const Icon(Icons.skip_next),
                onPressed: () => _navigate(1),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ValueListenableBuilder<double>(
                  valueListenable: globalPositionNotifier,
                  builder: (context, currentPos, child) {
                    return SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 6.0,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8.0),
                        inactiveTrackColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
                        activeTrackColor: Theme.of(context).colorScheme.primary,
                      ),
                      child: Slider(
                        value: currentPos.clamp(0.0, widget.project.totalDuration > 0 ? widget.project.totalDuration : 1.0),
                        max: widget.project.totalDuration > 0 ? widget.project.totalDuration : 1.0,
                        onChangeStart: (v) {
                          setState(() {
                            isTrackingPhase = false;
                            isAutoplaySuspended = true;
                          });
                        },
                        onChanged: (v) {
                          globalPositionSeconds = v;
                          globalPositionNotifier.value = v;
                          double accumulated = 0.0;
                          for (int i = 0; i < widget.project.videoDurations.length; i++) {
                            double dur = widget.project.videoDurations[i];
                            if (v <= accumulated + dur || i == widget.project.videoDurations.length - 1) {
                              if (player.state.playlist.index == i) {
                                double localSeconds = v - accumulated;
                                player.seek(Duration(milliseconds: (math.max(0.0, localSeconds) * 1000).toInt()));
                              }
                              break;
                            }
                            accumulated += dur;
                          }
                        },
                        onChangeEnd: (v) {
                          setState(() {
                            isTrackingPhase = false;
                            isAutoplaySuspended = true;
                          });
                          _seekGlobal(v).then((_) {
                            player.play();
                          });
                        },
                      ),
                    );
                  }
                ),
              ),
              const SizedBox(width: 8),
              ValueListenableBuilder<double>(
                valueListenable: globalPositionNotifier,
                builder: (context, currentPos, child) {
                  final posDuration = Duration(milliseconds: (currentPos * 1000).toInt());
                  final totalDur = Duration(milliseconds: (widget.project.totalDuration * 1000).toInt());
                  return Text('${_formatDuration(posDuration)} / ${_formatDuration(totalDur)}', style: const TextStyle(fontWeight: FontWeight.bold));
                }
              ),
            ],
          ),
        ),
      ],
    );
  }

  Timer? _seekTimer;
  bool _isSeekingActive = false;
  bool _isForwardSeek = true;
  bool _showJumpIndicator = false;
  String _jumpText = "";
  Timer? _jumpTimer;

  void _showJumpFeedback(bool forward) {
    setState(() {
      _showJumpIndicator = true;
      _jumpText = forward ? "+5s" : "-5s";
      _isForwardSeek = forward;
    });
    _jumpTimer?.cancel();
    _jumpTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _showJumpIndicator = false);
    });
  }

  void _startSeeking(bool forward) {
    setState(() {
      _isSeekingActive = true;
      _isForwardSeek = forward;
    });
    _seekTimer?.cancel();
    _seekTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      final currentPos = globalPositionSeconds;
      final newPos = forward ? currentPos + 2.0 : currentPos - 2.0;
      final target = newPos.clamp(0.0, widget.project.totalDuration);
      
      double accumulated = 0.0;
      for (int i = 0; i < widget.project.videoDurations.length; i++) {
        double dur = widget.project.videoDurations[i];
        if (target <= accumulated + dur || i == widget.project.videoDurations.length - 1) {
          if (player.state.playlist.index == i) {
            double localSeconds = target - accumulated;
            player.seek(Duration(milliseconds: (math.max(0.0, localSeconds) * 1000).toInt()));
          }
          break;
        }
        accumulated += dur;
      }
    });
  }

  void _stopSeeking() {
    if (mounted) {
      setState(() => _isSeekingActive = false);
    }
    _seekTimer?.cancel();
  }

  bool _showStarFeedback = false;
  bool _autoStarFeedback = false;
  HighlightPhase? _lastAutoStarPhase;
  Timer? _autoStarTimer;

  void _triggerStarFeedback() {
    _addManualHighlight();
    setState(() => _showStarFeedback = true);
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _showStarFeedback = false);
    });
  }

  Widget _buildMobileVideoPlayer(BuildContext context) {
    final posDuration = Duration(milliseconds: (globalPositionSeconds * 1000).toInt());
    final totalDur = Duration(milliseconds: (widget.project.totalDuration * 1000).toInt());

    int uiTurns = 0;
    if (isFullscreen) {
      if (widget.project.rotationPhaseLandscape == 2 || widget.project.rotationPhaseLandscape == 3) uiTurns = 3;
    }

    Widget videoContainer = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTapDown: (details) {
            final width = MediaQuery.of(context).size.width;
            final x = details.localPosition.dx;
            if (x < width * 0.3) {
              double target = (globalPositionSeconds - 5.0).clamp(0.0, widget.project.totalDuration);
              _showJumpFeedback(false);
              _seekGlobal(target);
            } else if (x > width * 0.7) {
              double target = (globalPositionSeconds + 5.0).clamp(0.0, widget.project.totalDuration);
              _showJumpFeedback(true);
              _seekGlobal(target);
            }
          },
          onTapUp: (details) {
            final width = MediaQuery.of(context).size.width;
            final x = details.localPosition.dx;
            if (x < width * 0.3) {
              _navigate(-1);
            } else if (x > width * 0.7) {
              _navigate(1);
            } else {
              player.playOrPause();
            }
          },
          onPanEnd: (details) {
            if (details.velocity.pixelsPerSecond.dx > 100) {
              _triggerStarFeedback();
            }
          },
          onLongPressStart: (details) {
            final width = MediaQuery.of(context).size.width;
            final x = details.localPosition.dx;
            if (x < width * 0.3) {
              _startSeeking(false);
            } else if (x > width * 0.7) {
              _startSeeking(true);
            }
          },
          onLongPressEnd: (_) => _stopSeeking(),
          child: Container(
            color: Colors.black,
            width: double.infinity,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (isFullscreen)
                  Builder(
                    builder: (context) {
                      int vTurns = 0;
                      switch (widget.project.rotationPhaseLandscape) {
                        case 1: vTurns = 2; break; // 1ο: ΜΟΝΟ βίντεο 180 (τα πάνω κάτω)
                        case 2: vTurns = 3; break; // 2ο: UI πλάι, βίντεο κάτω μεριά δεξιά
                        case 3: vTurns = 1; break; // 3ο: UI πλάι, βίντεο κάτω μεριά αριστερά
                      }
                      return RotatedBox(
                        quarterTurns: vTurns,
                        child: Video(
                          controller: controller,
                          controls: NoVideoControls,
                        ),
                      );
                    },
                  )
                else
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Builder(
                      builder: (context) {
                        int pTurns = 0;
                        switch (widget.project.rotationPhasePortrait) {
                          case 1: pTurns = 3; break; // Video Bottom -> Right
                          case 2: pTurns = 2; break; // Video Bottom -> Up
                          case 3: pTurns = 1; break; // Video Bottom -> Left
                        }
                        return RotatedBox(
                          quarterTurns: pTurns,
                          child: Video(
                            controller: controller,
                            controls: NoVideoControls,
                          ),
                        );
                      },
                    ),
                  ),
                Positioned.fill(
                  child: RotatedBox(
                    quarterTurns: uiTurns,
                    child: Stack(
                      children: [
                        Positioned(
                          top: isFullscreen ? ((widget.project.rotationPhaseLandscape == 2 || widget.project.rotationPhaseLandscape == 3) ? 12 : 12) : 4,
                          left: isFullscreen ? ((widget.project.rotationPhaseLandscape == 2 || widget.project.rotationPhaseLandscape == 3) ? 16 : 12) : 4,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              if (isFullscreen) _showSettingsSheet(context, Provider.of<AppState>(context, listen: false));
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black45,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isFullscreen) ...[
                                    const Padding(
                                      padding: EdgeInsets.all(2.0),
                                      child: Icon(Icons.settings, color: Colors.white70, size: 22),
                                    ),
                                    const SizedBox(width: 6),
                                  ],
                                  Text(
                                    '${activePhaseIndex >= 0 ? activePhaseIndex + 1 : 0} / ${widget.project.phases.length}',
                                    style: TextStyle(
                                      fontSize: isFullscreen ? 14 : 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                Positioned(
                  top: isFullscreen ? ((widget.project.rotationPhaseLandscape == 2 || widget.project.rotationPhaseLandscape == 3) ? 12 : 12) : 4,
                  right: isFullscreen ? ((widget.project.rotationPhaseLandscape == 2 || widget.project.rotationPhaseLandscape == 3) ? 16 : 12) : 4,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      Container(
                        decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                        child: const Padding(
                          padding: EdgeInsets.all(6.0),
                          child: Icon(Icons.screen_rotation, color: Colors.white70, size: 24),
                        ),
                      ),
                      Positioned(
                        top: -16, bottom: -16, left: -16, right: -16,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            setState(() {
                              if (isFullscreen) {
                                widget.project.rotationPhaseLandscape = (widget.project.rotationPhaseLandscape + 1) % 4;
                              } else {
                                widget.project.rotationPhasePortrait = (widget.project.rotationPhasePortrait + 1) % 4;
                              }
                            });
                            Provider.of<AppState>(context, listen: false).saveProject(widget.project);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  bottom: isFullscreen ? ((widget.project.rotationPhaseLandscape == 2 || widget.project.rotationPhaseLandscape == 3) ? 56 : 40) : 16,
                  left: isFullscreen ? ((widget.project.rotationPhaseLandscape == 2 || widget.project.rotationPhaseLandscape == 3) ? 16 : 12) : 4,
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: 6, horizontal: isFullscreen ? 4 : 2),
                    decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(16)),
                    child: StreamBuilder<double>(
                      stream: player.stream.volume,
                      initialData: player.state.volume,
                      builder: (context, snapshot) {
                        final vol = snapshot.data ?? 100.0;
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              height: isFullscreen ? 130 : 80,
                              child: RotatedBox(
                                quarterTurns: 3,
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 1.5,
                                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 12.0),
                                    activeTrackColor: Colors.grey.shade400,
                                    inactiveTrackColor: Colors.grey.shade700,
                                    thumbColor: Colors.grey.shade400,
                                  ),
                                  child: Slider(
                                    value: vol.clamp(0.0, 100.0),
                                    max: 100.0,
                                    onChanged: (v) => player.setVolume(v),
                                  ),
                                ),
                              ),
                            ),
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => player.setVolume(vol == 0 ? 100.0 : 0.0),
                              child: Padding(
                                padding: EdgeInsets.all(isFullscreen ? 6.0 : 4.0),
                                child: Icon(vol == 0 ? Icons.volume_off : Icons.volume_up, color: Colors.grey.shade400, size: 24),
                              ),
                            ),
                          ],
                        );
                      }
                    ),
                  ),
                ),
                Positioned(
                  bottom: isFullscreen ? ((widget.project.rotationPhaseLandscape == 2 || widget.project.rotationPhaseLandscape == 3) ? 32 : 40) : 2,
                  right: isFullscreen ? ((widget.project.rotationPhaseLandscape == 2 || widget.project.rotationPhaseLandscape == 3) ? 16 : 12) : 4,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(16)),
                        child: ValueListenableBuilder<double>(
                          valueListenable: globalPositionNotifier,
                          builder: (context, currentPos, child) {
                            final pDur = Duration(milliseconds: (currentPos * 1000).toInt());
                            return Text(
                              '${_formatDuration(pDur)} / ${_formatDuration(totalDur)}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade400,
                              ),
                            );
                          }
                        ),
                      ),
                      const SizedBox(width: 4),
                      Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          Container(
                            decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                            child: Padding(
                              padding: const EdgeInsets.all(6.0),
                              child: Icon(isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen, color: Colors.grey.shade400, size: 26),
                            ),
                          ),
                          Positioned(
                            top: -16, bottom: -16, left: -16, right: -16,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () async {
                                if (isFullscreen) {
                                  // 1. Ζητάμε από το OS να γυρίσει την οθόνη (Portrait)
                                  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
                                  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
                                  // 2. Δίνουμε χρόνο στο native animation να τρέξει χωρίς "σπάσιμο"
                                  await Future.delayed(const Duration(milliseconds: 200));
                                  // 3. Ξαναχτίζουμε το βαρύ UI (Λίστα με Highlights κ.λπ.)
                                  if (mounted) {
                                    setState(() {
                                      isFullscreen = false;
                                    });
                                  }
                                } else {
                                  // Κατά την είσοδο, το UI είναι ελαφρύ οπότε γίνεται ακαριαία
                                  setState(() {
                                    isFullscreen = true;
                                  });
                                  SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeRight, DeviceOrientation.landscapeLeft]);
                                  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (isFullscreen)
                  Positioned(
                    bottom: 0,
                    left: (widget.project.rotationPhaseLandscape == 2 || widget.project.rotationPhaseLandscape == 3) ? 0 : 16,
                    right: (widget.project.rotationPhaseLandscape == 2 || widget.project.rotationPhaseLandscape == 3) ? 0 : 16,
                    child: ValueListenableBuilder<double>(
                      valueListenable: globalPositionNotifier,
                      builder: (context, currentPos, child) {
                        return SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 6.0,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8.0),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16.0),
                            trackShape: const RectangularSliderTrackShape(),
                            activeTrackColor: Theme.of(context).colorScheme.primary,
                            inactiveTrackColor: Colors.white38,
                            thumbColor: Theme.of(context).colorScheme.primary,
                          ),
                          child: Slider(
                            value: currentPos.clamp(0.0, widget.project.totalDuration > 0 ? widget.project.totalDuration : 1.0),
                            max: widget.project.totalDuration > 0 ? widget.project.totalDuration : 1.0,
                            onChangeStart: (v) {
                              setState(() {
                                isTrackingPhase = false;
                                isAutoplaySuspended = true;
                              });
                            },
                            onChanged: (v) {
                              globalPositionSeconds = v;
                              globalPositionNotifier.value = v;
                              double accumulated = 0.0;
                              for (int i = 0; i < widget.project.videoDurations.length; i++) {
                                double dur = widget.project.videoDurations[i];
                                if (v <= accumulated + dur || i == widget.project.videoDurations.length - 1) {
                                  if (player.state.playlist.index == i) {
                                    double localSeconds = v - accumulated;
                                    player.seek(Duration(milliseconds: (math.max(0.0, localSeconds) * 1000).toInt()));
                                  }
                                  break;
                                }
                                accumulated += dur;
                              }
                            },
                            onChangeEnd: (v) {
                              setState(() {
                                isTrackingPhase = false;
                                isAutoplaySuspended = true;
                              });
                              _seekGlobal(v).then((_) => player.play());
                            },
                          ),
                        );
                      }
                    ),
                  ),
                if (_showStarFeedback || _autoStarFeedback)
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final double minSize = math.min(constraints.maxWidth, constraints.maxHeight);
                      final double starSize = minSize * 0.75; // 75% της μικρότερης διάστασης
                      return Center(
                        child: TweenAnimationBuilder<double>(
                          key: ValueKey('star_$_showStarFeedback'),
                          tween: Tween<double>(begin: _showStarFeedback ? 0.4 : 1.0, end: 1.0),
                          duration: Duration(milliseconds: _showStarFeedback ? 300 : 0),
                          curve: Curves.elasticOut,
                          builder: (context, scale, child) {
                            return Transform.scale(
                              scale: scale,
                              child: Opacity(
                                opacity: _showStarFeedback ? 0.8 : 0.35, // Πιο λεπτό/αχνό το άδειο αστεράκι
                                child: Icon(
                                  _showStarFeedback ? Icons.star : Icons.star_border,
                                  color: Colors.amber,
                                  size: starSize,
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                if (_showJumpIndicator || _isSeekingActive)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      decoration: BoxDecoration(
                        color: const Color(0x33000000), // ~20% αχνό μαύρο
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isForwardSeek ? Icons.fast_forward : Icons.fast_rewind,
                            color: Colors.white60, // Αχνό λευκό για το εικονίδιο
                            size: 48,
                          ),
                          if (_showJumpIndicator) ...[
                            const SizedBox(height: 8),
                            Text(
                              _jumpText,
                              style: const TextStyle(
                                color: Colors.white70, // Αχνό λευκό για το κείμενο
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );

    if (isFullscreen) {
      return Container(
        color: Colors.black,
        width: double.infinity,
        height: double.infinity,
        child: SafeArea(child: videoContainer),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        videoContainer,
        const SizedBox(height: 16),
        // Γραμμή 1: Slider
        SizedBox(
          height: 12,
          child: ValueListenableBuilder<double>(
            valueListenable: globalPositionNotifier,
            builder: (context, currentPos, child) {
              return SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3.0,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12.0),
                  trackShape: const RectangularSliderTrackShape(), 
                ),
                child: Slider(
                  value: currentPos.clamp(0.0, widget.project.totalDuration > 0 ? widget.project.totalDuration : 1.0),
                  max: widget.project.totalDuration > 0 ? widget.project.totalDuration : 1.0,
                  onChangeStart: (v) {
                    setState(() {
                      isTrackingPhase = false;
                      isAutoplaySuspended = true;
                    });
                  },
                  onChanged: (v) {
                    globalPositionSeconds = v;
                    globalPositionNotifier.value = v;
                    double accumulated = 0.0;
                    for (int i = 0; i < widget.project.videoDurations.length; i++) {
                      double dur = widget.project.videoDurations[i];
                      if (v <= accumulated + dur || i == widget.project.videoDurations.length - 1) {
                        if (player.state.playlist.index == i) {
                          double localSeconds = v - accumulated;
                          player.seek(Duration(milliseconds: (math.max(0.0, localSeconds) * 1000).toInt()));
                        }
                        break;
                      }
                      accumulated += dur;
                    }
                  },
                  onChangeEnd: (v) {
                    setState(() {
                      isTrackingPhase = false;
                      isAutoplaySuspended = true;
                    });
                    _seekGlobal(v).then((_) => player.play());
                  },
                ),
              );
            }
          ),
        ),
        const SizedBox(height: 12),
        // Γραμμή 2: Κουμπιά (Συμπαγή & Οβάλ Play)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              InkWell(
                onTap: () => _showSettingsSheet(context, Provider.of<AppState>(context, listen: false)),
                customBorder: const CircleBorder(),
                child: Container(
                  padding: const EdgeInsets.all(8.0),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.settings, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 24),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      GestureDetector(
                        onTap: () => _navigate(-1),
                        onDoubleTap: () {
                          double target = (globalPositionSeconds - 5.0).clamp(0.0, widget.project.totalDuration);
                          _showJumpFeedback(false);
                          _seekGlobal(target);
                        },
                        onLongPressStart: (_) => _startSeeking(false),
                        onLongPressEnd: (_) => _stopSeeking(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 6.0),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Icon(Icons.fast_rewind, color: Theme.of(context).colorScheme.primary, size: 28),
                        ),
                      ),
                      InkWell(
                        onTap: () => player.playOrPause(),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(isPlaying ? Icons.pause : Icons.play_arrow, color: Theme.of(context).colorScheme.onPrimaryContainer, size: 28),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => _navigate(1),
                        onDoubleTap: () {
                          double target = (globalPositionSeconds + 5.0).clamp(0.0, widget.project.totalDuration);
                          _showJumpFeedback(true);
                          _seekGlobal(target);
                        },
                        onLongPressStart: (_) => _startSeeking(true),
                        onLongPressEnd: (_) => _stopSeeking(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 6.0),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Icon(Icons.fast_forward, color: Theme.of(context).colorScheme.primary, size: 28),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              InkWell(
                onTap: _triggerStarFeedback,
                customBorder: const CircleBorder(),
                child: Container(
                  padding: const EdgeInsets.all(8.0),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.star_border, color: Colors.amber, size: 24),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  void _showSettingsSheet(BuildContext context, AppState state) async {
    int uiTurns = 0;
    if (isFullscreen) {
      if (widget.project.rotationPhaseLandscape == 2 || widget.project.rotationPhaseLandscape == 3) uiTurns = 3;
    }
    final bool isRotatedFullscreen = uiTurns != 0;
    
    double tempSensitivity = sensitivity;
    double tempGrouping = grouping;
    
    int calculatePreviewCount() {
      if (rmsData.isEmpty) return widget.project.phases.length;
      double level = maxRms - (tempSensitivity / 100.0) * (maxRms - avgRms);
      List<double> rawTimes = [];
      for (int i = 0; i < rmsData.length; i++) {
        if (rmsData[i] > level) rawTimes.add(timesData[i]);
      }
      List<double> grouped = [];
      if (rawTimes.isNotEmpty) {
        grouped.add(rawTimes[0]);
        for (int i = 1; i < rawTimes.length; i++) {
          if (rawTimes[i] - grouped.last > tempGrouping) {
            grouped.add(rawTimes[i]);
          }
        }
      }
      int explicitCount = widget.project.phases.where((p) => p.isHighlight).length;
      int newCount = 0;
      for (double t in grouped) {
        bool isAlreadyHighlight = widget.project.phases.any((p) => p.isHighlight && (p.timestamp - t).abs() < 0.5);
        if (!isAlreadyHighlight) newCount++;
      }
      return explicitCount + newCount;
    }

    int previewCount = widget.project.phases.length;

    Widget buildSettingsContent(BuildContext ctx, StateSetter setModalState, bool isPortraitLayout) {
      Widget buildSensitivity() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ευαισθησία: ${tempSensitivity.toInt()}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          SliderTheme(
            data: SliderTheme.of(ctx).copyWith(trackShape: const RectangularSliderTrackShape()),
            child: Slider(
              value: tempSensitivity, max: 100,
              onChanged: (v) {
                setModalState(() {
                  tempSensitivity = v;
                  previewCount = calculatePreviewCount();
                });
              },
            ),
          ),
        ],
      );

      Widget buildGrouping() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ομαδοποίηση: ${tempGrouping.toStringAsFixed(1)}s', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          SliderTheme(
            data: SliderTheme.of(ctx).copyWith(trackShape: const RectangularSliderTrackShape()),
            child: Slider(
              value: tempGrouping, max: 10, divisions: 10,
              onChanged: (v) {
                setModalState(() {
                  tempGrouping = v;
                  previewCount = calculatePreviewCount();
                });
              },
            ),
          ),
        ],
      );

      return SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 16.0, right: 16.0, top: 16.0,
            bottom: isRotatedFullscreen ? 16.0 : MediaQuery.of(ctx).viewInsets.bottom + 8.0
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  const Center(child: Text('Ρυθμίσεις', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                  Positioned(
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.movie_filter_outlined, size: 16, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(
                            '$previewCount',
                            style: const TextStyle(color: Color(0xFF900020), fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(),
              if (isPortraitLayout) ...[
                buildSensitivity(),
                buildGrouping(),
              ] else ...[
                Row(
                  children: [
                    Expanded(child: buildSensitivity()),
                    Expanded(child: buildGrouping()),
                  ],
                ),
              ],
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Start Offset: ${startOffset.toStringAsFixed(1)}s', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        SliderTheme(
                          data: SliderTheme.of(ctx).copyWith(trackShape: const RectangularSliderTrackShape()),
                          child: Slider(
                            value: startOffset, max: 10, divisions: 10,
                            onChanged: (v) {
                              setModalState(() => startOffset = v);
                            },
                            onChangeEnd: (v) {
                              setState(() {
                                startOffset = v;
                                widget.project.startOffset = v;
                              });
                              state.saveProject(widget.project);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('End Offset: ${endOffset.toStringAsFixed(1)}s', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        SliderTheme(
                          data: SliderTheme.of(ctx).copyWith(trackShape: const RectangularSliderTrackShape()),
                          child: Slider(
                            value: endOffset, max: 10, divisions: 10,
                            onChanged: (v) {
                              setModalState(() => endOffset = v);
                            },
                            onChangeEnd: (v) {
                              setState(() {
                                endOffset = v;
                                widget.project.endOffset = v;
                              });
                              state.saveProject(widget.project);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Row(
                    children: [
                      Checkbox(visualDensity: VisualDensity.compact, value: autoplay, onChanged: (v) {
                        setModalState(() => autoplay = v ?? false);
                        setState(() {
                          autoplay = v ?? false;
                          widget.project.autoplay = autoplay;
                        });
                        state.saveProject(widget.project);
                      }),
                      const Text('Autoplay', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                  Row(
                    children: [
                      Checkbox(visualDensity: VisualDensity.compact, value: skipSeen, onChanged: (v) {
                        setModalState(() => skipSeen = v ?? false);
                        setState(() {
                          skipSeen = v ?? false;
                          widget.project.skipSeen = skipSeen;
                        });
                        state.saveProject(widget.project);
                      }),
                    const Text('Skip Seen', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final bool isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;

    final initialSensitivity = sensitivity;
    final initialGrouping = grouping;

    if (isRotatedFullscreen) {
      // 1. Κατάσταση: Rotated Landscape (Το κινητό κάθετα, το UI γυρισμένο).
      await showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setModalState) {
            return RotatedBox(
              quarterTurns: uiTurns,
              child: Dialog(
                insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
                backgroundColor: Theme.of(ctx).canvasColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: SizedBox(
                  width: MediaQuery.of(ctx).size.height,
                  child: SingleChildScrollView(
                    child: buildSettingsContent(ctx, setModalState, true),
                  ),
                ),
              ),
            );
          }
        )
      );
    } else if (isFullscreen) {
      // 2. Κατάσταση: True Landscape (Το κινητό κανονικά οριζόντια).
      await showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              backgroundColor: Theme.of(ctx).canvasColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: SizedBox(
                width: MediaQuery.of(ctx).size.width, // Απλώνεται στο φάρδος
                child: SingleChildScrollView(
                  child: buildSettingsContent(ctx, setModalState, false),
                ),
              ),
            );
          }
        )
      );
    } else {
      // 3. Κατάσταση: Κανονικό Portrait.
      await showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
              backgroundColor: Theme.of(ctx).canvasColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: SizedBox(
                width: MediaQuery.of(ctx).size.width, // Απλώνεται στο φάρδος
                child: SingleChildScrollView(
                  child: buildSettingsContent(ctx, setModalState, true),
                ),
              ),
            );
          }
        )
      );
    }

    if (tempSensitivity != initialSensitivity || tempGrouping != initialGrouping) {
      if (mounted) {
        setState(() {
          sensitivity = tempSensitivity;
          grouping = tempGrouping;
          widget.project.sensitivity = tempSensitivity;
          widget.project.grouping = tempGrouping;
        });
        _recalcPhases();
        state.saveProject(widget.project);
      }
    }
  }

  Widget _buildSidePanel(BuildContext context, AppState state) {
    final phases = _filteredPhases;
    final chronologicalPhases = widget.project.phases.toList()..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return Column(
      children: [
        // --- SMART TOOLBAR ---
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
            border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
          ),
          child: Row(
            children: [
              if (showHighlightsOnly) ...[
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: _areAllHighlightsSelected(),
                    onChanged: widget.project.phases.where((p) => p.isHighlight).isEmpty ? null : _toggleAllHighlights,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              InkWell(
                onTap: () {
                  bool phaseChanged = false;
                  int targetIndex = -1;
                  List<HighlightPhase> targetPhases = [];

                  setState(() {
                    showHighlightsOnly = !showHighlightsOnly;
                    widget.project.showHighlightsOnly = showHighlightsOnly;
                    
                    targetPhases = showHighlightsOnly 
                        ? widget.project.phases.where((p) => p.isHighlight).toList()
                        : widget.project.phases.toList()..sort((a, b) => a.timestamp.compareTo(b.timestamp));

                    if (currentPlayingPhase != null) {
                      if (targetPhases.isEmpty) {
                         activePhaseIndex = -1;
                      } else {
                         int newIndex = targetPhases.indexOf(currentPlayingPhase!);
                         if (newIndex != -1) {
                            activePhaseIndex = newIndex;
                         } else {
                            HighlightPhase? closestPhase;
                            double minDiff = double.infinity;
                            
                            for (var p in targetPhases) {
                               double diff = (p.timestamp - currentPlayingPhase!.timestamp).abs();
                               if (diff < minDiff) {
                                  minDiff = diff;
                                  closestPhase = p;
                               } else if (diff == minDiff && closestPhase != null) {
                                  if (p.timestamp < closestPhase!.timestamp) {
                                      closestPhase = p;
                                  }
                               }
                            }
                            
                            if (closestPhase != null) {
                               targetIndex = targetPhases.indexOf(closestPhase);
                               phaseChanged = true;
                            }
                         }
                      }
                    }
                  });
                  state.saveProject(widget.project);

                  if (phaseChanged && targetIndex != -1) {
                     _playPhase(targetIndex, targetPhases, recordHistory: false);
                  }
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: showHighlightsOnly ? Theme.of(context).colorScheme.primaryContainer : Colors.transparent,
                    border: Border.all(color: showHighlightsOnly ? Theme.of(context).colorScheme.primary : Colors.grey.shade500, width: 2.0),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: showHighlightsOnly 
                        ? [
                            BoxShadow(
                              color: Theme.of(context).brightness == Brightness.light ? Colors.black87 : Colors.white54,
                              spreadRadius: 1.5,
                              blurRadius: 0,
                            )
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star, size: 16, color: showHighlightsOnly ? Theme.of(context).colorScheme.primary : Colors.grey),
                      const SizedBox(width: 2),
                      const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey),
                      const SizedBox(width: 2),
                      Icon(Icons.movie_creation_outlined, size: 16, color: showHighlightsOnly ? Theme.of(context).colorScheme.primary : Colors.grey),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: RichText(
                  text: TextSpan(
                    style: const TextStyle(fontSize: 18),
                    children: [
                      TextSpan(text: '${activePhaseIndex >= 0 ? activePhaseIndex + 1 : 0} ', style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.normal)),
                      const TextSpan(text: '/ ', style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                      TextSpan(text: '${phases.length}', style: TextStyle(color: showHighlightsOnly ? Colors.amber : const Color(0xFF900020), fontWeight: FontWeight.bold)),
                    ]
                  )
                ),
              ),
              const Spacer(),
              if (showHighlightsOnly)
                IconButton(
                  icon: const Icon(Icons.sort, size: 20),
                  onPressed: () {
                    setState(() {
                      widget.project.phases.sort((a, b) => a.timestamp.compareTo(b.timestamp));
                    });
                    state.saveProject(widget.project);
                  },
                  tooltip: 'Επαναφορά Σειράς',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                )
              else
                IconButton(
                  icon: const Icon(Icons.cleaning_services, size: 20),
                  onPressed: () async {
                    bool? confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Επαναφορά Φάσεων', style: TextStyle(fontWeight: FontWeight.bold)),
                        content: const Text('Είστε σίγουροι ότι θέλετε να μηδενίσετε το ιστορικό προβολής (Seen) για όλες τις φάσεις;'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(state.t('no'))),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
                            child: Text(state.t('yes')),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) _resetSeen();
                  },
                  tooltip: 'Reset Seen',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
        ),

        // --- UNIFIED LIST ---
        Expanded(
          child: isLoadingAnalysis
            ? const Center(child: CircularProgressIndicator())
            : phases.isEmpty 
              ? Center(child: Text('Δεν βρέθηκαν φάσεις', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5))))
              : ReorderableListView.builder(
                  scrollController: _listScrollController,
                  buildDefaultDragHandles: false,
                  onReorder: (oldIndex, newIndex) {
                    if (!showHighlightsOnly) return;
                    setState(() {
                      if (oldIndex < newIndex) newIndex -= 1;
                      final highlights = widget.project.phases.where((p) => p.isHighlight).toList();
                      final item = highlights.removeAt(oldIndex);
                      highlights.insert(newIndex, item);
                      
                      final nonHighlights = widget.project.phases.where((p) => !p.isHighlight).toList();
                      widget.project.phases = [...nonHighlights, ...highlights];
                    });
                    Provider.of<AppState>(context, listen: false).saveProject(widget.project);
                  },
                  itemCount: phases.length,
                  itemBuilder: (context, index) {
                    final phase = phases[index];
                    final m = (phase.timestamp ~/ 60).toString().padLeft(2, '0');
                    final s = (phase.timestamp % 60).toInt().toString().padLeft(2, '0');
                    
                    final isDark = Theme.of(context).brightness == Brightness.dark;
                    final isActive = (index == activePhaseIndex && currentPlayingPhase == phase && isTrackingPhase);
                    final isLastPlayed = (currentPlayingPhase == phase && !isTrackingPhase);
                    
                    Color bgColor;
                    if (phase.isHighlight) {
                      bgColor = isDark ? const Color(0xFF4A148C) : const Color(0xFFF3E5F5);
                    } else {
                      bgColor = isDark ? const Color(0xFF2C2C34) : Colors.white;
                    }

                    Color borderColor;
                    if (isActive || isLastPlayed) {
                      borderColor = const Color(0xFF900020);
                    } else if (phase.isHighlight) {
                      borderColor = Theme.of(context).colorScheme.primary;
                    } else {
                      borderColor = isDark ? Colors.grey.shade700 : Colors.grey.shade300;
                    }
                    
                    Widget card = Card(
                      key: GlobalObjectKey(phase),
                      elevation: 1,
                      color: bgColor,
                      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                        side: BorderSide(color: borderColor, width: isActive ? 2 : 1),
                      ),
                      child: ListTile(
                        dense: true,
                        visualDensity: const VisualDensity(horizontal: 0, vertical: -2),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                        minVerticalPadding: 0,
                        leading: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (showHighlightsOnly)
                              ReorderableDragStartListener(
                                index: index,
                                child: const Icon(Icons.drag_indicator, color: Colors.grey, size: 20),
                              ),
                            if (showHighlightsOnly && phase.isHighlight)
                              SizedBox(
                                width: 28,
                                child: Checkbox(
                                  visualDensity: VisualDensity.compact,
                                  value: phase.isSelected,
                                  onChanged: (v) {
                                    setState(() => phase.isSelected = v ?? true);
                                    state.saveProject(widget.project);
                                  },
                                ),
                              ),
                            SizedBox(
                              width: 32,
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                icon: Icon(
                                  phase.isHighlight ? Icons.star : Icons.star_border,
                                  color: phase.isHighlight ? Colors.amber : Colors.grey,
                                  size: 22,
                                ),
                                onPressed: () {
                                  setState(() {
                                    phase.isHighlight = !phase.isHighlight;
                                    if (!phase.isHighlight) {
                                      phase.customStartOffset = null;
                                      phase.customEndOffset = null;
                                    }
                                  });
                                  state.saveProject(widget.project);
                                },
                              ),
                            ),
                          ],
                        ),
                        title: Center(
                          child: phase.isHighlight ? SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(border: Border.all(color: Colors.grey.withOpacity(0.5)), borderRadius: BorderRadius.circular(4)),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      InkWell(onTap: () => _adjustOffset(phase, 'start', 1.0, state), child: const Icon(Icons.arrow_left, size: 18)),
                                      SizedBox(width: 20, child: Text('${(phase.customStartOffset ?? startOffset).toInt()}s', textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                                      InkWell(onTap: () => _adjustOffset(phase, 'start', -1.0, state), child: const Icon(Icons.arrow_right, size: 18)),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Container(
                                  padding: isActive ? const EdgeInsets.symmetric(horizontal: 4, vertical: 2) : null,
                                  decoration: isActive ? BoxDecoration(
                                    border: Border.all(color: const Color(0xFF900020), width: 1.0),
                                    borderRadius: BorderRadius.circular(4),
                                  ) : null,
                                  child: Text(
                                    '(${chronologicalPhases.indexOf(phase) + 1}) $m:$s', 
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: (isActive || isLastPlayed) ? FontWeight.bold : FontWeight.normal, 
                                      decoration: phase.isSeen && !isActive && !isLastPlayed ? TextDecoration.lineThrough : null,
                                      color: phase.isSeen && !isActive && !isLastPlayed ? Colors.grey : null,
                                    )
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(border: Border.all(color: Colors.grey.withOpacity(0.5)), borderRadius: BorderRadius.circular(4)),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      InkWell(onTap: () => _adjustOffset(phase, 'end', -1.0, state), child: const Icon(Icons.arrow_left, size: 18)),
                                      SizedBox(width: 20, child: Text('${(phase.customEndOffset ?? endOffset).toInt()}s', textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                                      InkWell(onTap: () => _adjustOffset(phase, 'end', 1.0, state), child: const Icon(Icons.arrow_right, size: 18)),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                InkWell(
                                  onTap: () {
                                    setState(() {
                                      phase.customStartOffset = null;
                                      phase.customEndOffset = null;
                                    });
                                    state.saveProject(widget.project);
                                  },
                                  child: const Icon(Icons.refresh, size: 16, color: Colors.grey),
                                ),
                              ],
                            ),
                          ) : Container(
                            padding: isActive ? const EdgeInsets.symmetric(horizontal: 4, vertical: 2) : null,
                            decoration: isActive ? BoxDecoration(
                              border: Border.all(color: const Color(0xFF900020), width: 1.0),
                              borderRadius: BorderRadius.circular(4),
                            ) : null,
                            child: Text(
                              '(${chronologicalPhases.indexOf(phase) + 1}) $m:$s', 
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: (isActive || isLastPlayed) ? FontWeight.bold : FontWeight.normal, 
                                decoration: phase.isSeen && !isActive && !isLastPlayed ? TextDecoration.lineThrough : null,
                                color: phase.isSeen && !isActive && !isLastPlayed ? Colors.grey : null,
                              )
                            ),
                          ),
                        ),
                        onTap: () => _playPhase(index, phases),
                      ),
                    );

                    return card;
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Divider(height: 1, thickness: 1, color: Theme.of(context).dividerColor),
              if (showHighlightsOnly)
                Container(
                  padding: const EdgeInsets.all(8.0),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2563EB), padding: const EdgeInsets.symmetric(vertical: 16)),
                          onPressed: () => _showExportDialog(context, 'join'),
                          child: const Text('Export Video', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0D9488), padding: const EdgeInsets.symmetric(vertical: 16)),
                          onPressed: () => _showExportDialog(context, 'separate'),
                          child: const Text('Export Clips', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                )
              else
                const SizedBox(height: 8),
            ],
          ),
        ),
      ],
    );
  }

  void _showExportDialog(BuildContext context, String mode) async {
    final highlights = widget.project.phases.where((p) => p.isHighlight && p.isSelected).toList();
    print('----------------------------------------------------');
    print('[USER ACTION] Άνοιγμα Export. Mode: $mode. Clips: ${highlights.length}');
    print('----------------------------------------------------');
    if (highlights.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Δεν υπάρχουν επιλεγμένα Highlights για εξαγωγή!')));
      return;
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => ExportSettingsDialog(mode: mode),
    );

    if (result != null) {
      _runExport(result, mode, highlights);
    }
  }

  Future<void> _runExport(Map<String, dynamic> config, String mode, List<HighlightPhase> highlights) async {
    final outDir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Επιλογή Φακέλου Αποθήκευσης');
    if (outDir == null) return;

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ExportProgressDialog(
        project: widget.project,
        highlights: highlights,
        config: config,
        mode: mode,
        outDir: outDir,
        startOffset: startOffset,
        endOffset: endOffset,
      ),
    );
  }

  void _showRenameDialog(BuildContext context, AppState state) {
    final TextEditingController controller = TextEditingController(text: widget.project.name);
    showDialog(
      context: context,
      builder: (ctx) {
        final isDesktop = MediaQuery.of(ctx).size.width > 600;
        return AlertDialog(
          insetPadding: EdgeInsets.symmetric(horizontal: isDesktop ? 24.0 : 12.0, vertical: 24.0),
          titlePadding: EdgeInsets.only(left: isDesktop ? 24.0 : 16.0, right: isDesktop ? 24.0 : 16.0, top: 16.0, bottom: 8.0),
          contentPadding: EdgeInsets.only(left: isDesktop ? 24.0 : 16.0, right: isDesktop ? 24.0 : 16.0, top: 8.0, bottom: 0.0),
          actionsPadding: EdgeInsets.only(bottom: 12.0, right: isDesktop ? 24.0 : 12.0, top: 12.0),
          title: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(state.t('rename_project'), style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(
                labelText: state.t('new_name'),
                border: const OutlineInputBorder(),
              ),
              autofocus: true,
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(state.t('cancel'))),
            FilledButton(
              onPressed: () {
                final newName = controller.text.trim();
                if (newName.isNotEmpty && newName != widget.project.name) {
                  state.renameProject(widget.project.id, newName);
                  setState(() {}); // Ανανέωση UI για να φανεί ο νέος τίτλος
                }
                Navigator.pop(ctx);
              },
              child: Text(state.t('save')),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppState>(context);
    final isDesktop = MediaQuery.of(context).size.width > 600;
    final iconSize = isDesktop ? 28.0 : 24.0;
    final topActionFontSize = isDesktop ? 18.0 : 15.0;
    final horizontalPadding = isDesktop ? 16.0 : 8.0;

    if (isFullscreen) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Center(
            child: _buildMobileVideoPlayer(context),
          ),
        ),
      );
    }
    
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Tooltip(
          message: widget.project.name,
          child: InkWell(
            onLongPress: () => _showRenameDialog(context, state),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
              child: Text(
                widget.project.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, height: 1.2),
              ),
            ),
          ),
        ),
        elevation: 2,
        actions: [
          IconButton(
            iconSize: iconSize,
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            constraints: const BoxConstraints(),
            icon: Icon(state.isDarkMode ? Icons.wb_sunny : Icons.nightlight_round),
            onPressed: state.toggleTheme,
          ),
          const SizedBox(width: 4),
          TextButton(
            onPressed: state.toggleLanguage,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(state.currentLang.toUpperCase(), style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold, fontSize: topActionFontSize)),
          ),
          SizedBox(width: horizontalPadding),
        ],
      ),
      body: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.space) {
              player.playOrPause();
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.keyH) {
              if (currentPlayingPhase != null) {
                setState(() {
                  currentPlayingPhase!.isHighlight = !currentPlayingPhase!.isHighlight;
                  if (!currentPlayingPhase!.isHighlight) {
                    currentPlayingPhase!.customStartOffset = null;
                    currentPlayingPhase!.customEndOffset = null;
                  }
                });
                state.saveProject(widget.project);
              }
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.keyN) {
              _navigate(1);
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.keyG) {
              _navigate(-1);
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 800;
            
            if (isWide) {
              return Row(
                children: [
                  Expanded(
                    child: _buildVideoPlayer(context),
                  ),
                  MouseRegion(
                    cursor: SystemMouseCursors.resizeLeftRight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanUpdate: (details) {
                        setState(() {
                          _sidebarWidth -= details.delta.dx;
                          _sidebarWidth = _sidebarWidth.clamp(250.0, constraints.maxWidth - 400.0);
                        });
                      },
                      onPanEnd: (details) async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setDouble('sidebar_width', _sidebarWidth);
                      },
                      child: Container(
                        width: 8,
                        color: Theme.of(context).dividerColor.withOpacity(0.5),
                        child: Center(
                          child: Container(
                            width: 2,
                            height: 30,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: _sidebarWidth,
                    child: _buildSidePanel(context, state),
                  ),
                ],
              );
            } else {
              return Column(
                children: [
                  _buildMobileVideoPlayer(context),
                  Expanded(
                    child: _buildSidePanel(context, state),
                  ),
                ],
              );
            }
          },
        ),
      ),
    );
  }
}