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
  },
  'en': {
    'title': 'Highlight Manager (Test)',
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
  bool isDarkMode = false;

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
      isDarkMode = prefs.getBool('isDarkMode') ?? false;
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
    
    final totalStopwatch = Stopwatch()..start();

    try {
      // 1ο Πέρασμα: Υπολογισμός Συνολικής Διάρκειας (Απαραίτητο για το συνολικό ποσοστό % progress)
      for (int i = 0; i < paths.length; i++) {
        if (_isAnalysisCancelled) throw Exception('Cancelled');
        
        String path = paths[i];
        onStatusUpdate("Υπολογισμός διάρκειας ${i + 1}/${paths.length}...", 0.0);
        
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

      // 2ο Πέρασμα: Ανάλυση Ήχου
      for (int i = 0; i < paths.length; i++) {
        if (_isAnalysisCancelled) throw Exception('Cancelled');
        
        String path = paths[i];
        double dur = videoDurations[i];
        
        _activeFfmpegProcesses.clear();
        
        List<double> currentRms = [];
        List<double> currentTimes = [];
        double currentTime = 0.0;
        
        final afFilter = "aformat=channel_layouts=mono,aresample=22050,asetnsamples=512,astats=metadata=1:reset=1,ametadata=print:key=lavfi.astats.Overall.RMS_level";

        void processRmsLine(String line) {
          if (line.contains('lavfi.astats.Overall.RMS_level=')) {
            final strVal = line.split('=').last.trim();
            double? db = strVal == '-inf' ? -100.0 : double.tryParse(strVal);
            if (db != null) {
              double linear = db <= -100.0 ? 0.0 : math.pow(10, db / 20.0).toDouble();
              currentRms.add(linear);
              currentTimes.add(currentTime + cumulativeTime);
              currentTime += (512.0 / 22050.0);
              
              if (currentRms.length % 50 == 0) {
                double globalProgress = (cumulativeTime + currentTime) / totalDur;
                onStatusUpdate("Ανάλυση Ήχου ${i + 1}/${paths.length}...", globalProgress.clamp(0.0, 0.99));
              }
            }
          }
        }

        if (Platform.isWindows || Platform.isLinux) {
          final ffmpegExe = await _getDesktopFFmpegPath();
          final p = await Process.start(
            ffmpegExe,
            ['-y', '-i', path, '-vn', '-af', afFilter, '-f', 'null', '-'],
          );
          _activeFfmpegProcesses.add(p);
          
          p.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen(processRmsLine);
          
          final exitCode = await p.exitCode;
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

          final cmd = "-y -i \"$ffmpegPath\" -vn -af \"$afFilter\" -f null -";
          
          final completer = Completer<void>();
          FFmpegKit.executeAsync(
            cmd,
            (session) async {
              final returnCode = await session.getReturnCode();
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

      onStatusUpdate("Αποθήκευση δεδομένων...", 1.0);
      
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

      final newProject = Project(
        id: projectId,
        name: finalName,
        videoPaths: paths,
        videoDurations: videoDurations,
        totalDuration: totalDur,
      );

      await saveProject(newProject);
      return newProject;

    } catch (e) {
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
  String status = "Προετοιμασία...";
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
      Navigator.pop(context, project != null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 600;
    return AlertDialog(
      insetPadding: isDesktop ? const EdgeInsets.symmetric(horizontal: 40.0, vertical: 24.0) : EdgeInsets.zero,
      shape: isDesktop ? null : const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      title: const FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text('Επεξεργασία', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      content: SizedBox(
        width: isDesktop ? 400 : MediaQuery.of(context).size.width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(value: progress > 0 ? progress : null),
            const SizedBox(height: 16),
            Text(status, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Column(
                  children: [
                    const Text('Χρόνος', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    Text(elapsedTimeStr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
                Column(
                  children: [
                    const Text('Πρόοδος', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    Text('${(progress * 100).toStringAsFixed(1)}%', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
                Column(
                  children: [
                    const Text('Εκτίμηση', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    Text(etaStr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: isCancelled ? null : () {
            setState(() {
              isCancelled = true;
              status = "Ακύρωση... παρακαλώ περιμένετε";
            });
            widget.state.cancelAnalysis();
          },
          child: Text(isCancelled ? 'ΑΚΥΡΩΝΕΤΑΙ...' : 'ΑΚΥΡΩΣΗ', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
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

    bool success = await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ProcessingDialog(
        state: state,
        baseName: name,
        paths: _selectedPaths,
      ),
    ) ?? false;

    if (mounted && success) {
      Navigator.pop(context);
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
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              // Πλαίσιο Thumbnail
              Container(
                width: 100,
                height: 64,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      Icons.movie_creation_outlined, 
                      size: 32, 
                      color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5)
                    ),
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          formatDuration(project.totalDuration),
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(project.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(
                      '${project.videoPaths.length} ${state.t('video_files')}\n${state.t('updated')} ${project.createdAt.day}/${project.createdAt.month}/${project.createdAt.year}',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), fontSize: 13, height: 1.4),
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
                      if (analysisFile.existsSync() && projectFile.existsSync()) {
                        String pName = entity.path.split(Platform.pathSeparator).last;
                        try {
                          final pData = jsonDecode(projectFile.readAsStringSync());
                          pName = pData['name'] ?? pName;
                        } catch(_) {}
                        final safeName = pName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
                        analysisFile.copySync('$exportPath/analysis_$safeName.json');
                        count++;
                      }
                    }
                  }
                }
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✅ Εξήχθησαν $count JSON!\nΒρίσκονται στο:\n$exportPath (Δες μέσω USB)'),
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
                    icon: const Icon(Icons.add, size: 28),
                    label: Text(state.t('new_project'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    style: FilledButton.styleFrom(
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
      return returnCode?.isValueSuccess() == true ? 0 : 1;
    }
  }

  Future<void> _startExport() async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final tempDir = Directory('${widget.outDir}/temp_$timestamp');
      if (widget.mode == 'join') await tempDir.create();

      final isCompress = widget.config['compress'] as bool;
      
      List<String> videoParams = isCompress 
          ? ['-c:v', 'libx265', '-crf', '26', '-preset', 'medium', '-tag:v', 'hvc1']
          : ['-c:v', 'libx264', '-preset', 'ultrafast', '-crf', '23'];

      if (widget.mode == 'separate') {
        final clipsDir = Directory('${widget.outDir}/${widget.project.name}_clips_$timestamp');
        await clipsDir.create();

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
          final outPath = '${clipsDir.path}/clip_${i + 1}.mp4';

          final args = [
            '-y', '-ss', localData.localSeconds.toStringAsFixed(3), '-i', localData.path, '-t', dur.toString(),
            ...videoParams, '-c:a', 'aac', outPath
          ];
          
          final code = await _runFFmpeg(args);
          if (code != 0 && !isCancelled) throw Exception('FFmpeg error');
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
            '-vf', 'scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2',
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
          listContent += "file '${processedClips[i].replaceAll('\\', '/')}'\n";
          if (transTemp.isNotEmpty && i < processedClips.length - 1) {
            listContent += "file '${transTemp.replaceAll('\\', '/')}'\n";
          }
        }
        await listFile.writeAsString(listContent);

        final mergedOut = '${widget.outDir}/${widget.project.name}_merged_$timestamp.mp4';
        final catArgs = [
          '-y', '-f', 'concat', '-safe', '0', '-i', listFile.path, '-c', 'copy', mergedOut
        ];
        final code = await _runFFmpeg(catArgs);
        if (code != 0 && !isCancelled) throw Exception('FFmpeg error concat');
        
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
  
  int activePhaseIndex = -1;
  HighlightPhase? currentPlayingPhase;
  bool isTrackingPhase = false;
  bool isAutoplaySuspended = false;
  bool isSeeking = false;
  
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
      setState(() {
        globalPositionSeconds = currentGlobalSec;
      });

      if (!isPlaying || currentPlayingPhase == null || !isTrackingPhase || isSeeking) return;
      
      final targetEnd = currentPlayingPhase!.timestamp + (currentPlayingPhase!.customEndOffset ?? endOffset);

      if (currentGlobalSec >= targetEnd) {
        if (currentGlobalSec > targetEnd + 2.0) return; // Αποτροπή skip από stream delay glitches (media_kit)
        
        if (autoplay && !isAutoplaySuspended) {
          _navigate(1, isAuto: true);
        } else if (currentPlayingPhase!.isHighlight && isTrackingPhase) {
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
            activePhaseIndex = widget.project.lastActivePhaseIndex;
            currentPlayingPhase = widget.project.phases[activePhaseIndex];
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
      if (!_listScrollController.hasClients || currentPlayingPhase == null) return;
      
      final phases = _filteredPhases;
      final int index = phases.indexOf(currentPlayingPhase!);
      if (index < 0) return;
      
      // Το πραγματικό ύψος κάθε στοιχείου μετά τη συμπίεση
      const double itemHeight = 52.0; 
      final double viewportHeight = _listScrollController.position.viewportDimension;
      
      // Στοχεύουμε στο κέντρο της οθόνης
      double targetOffset = (index * itemHeight) - (viewportHeight / 2) + (itemHeight / 2);
      
      targetOffset = math.max(0.0, targetOffset);
      // Αφαιρέθηκε ο αυστηρός περιορισμός maxScrollExtent, 
      // γιατί κατά το build δεν έχει προλάβει πάντα να ενημερωθεί σωστά το μέγεθος.
      
      _listScrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
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
    _seekTimer?.cancel();
    playingSub?.cancel();
    durationSub?.cancel();
    positionSub?.cancel();
    player.dispose();
    _listScrollController.dispose();
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Προστέθηκε highlight στο ${currentPos.toStringAsFixed(1)}s')),
    );
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
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 6.0,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8.0),
                    inactiveTrackColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
                    activeTrackColor: Theme.of(context).colorScheme.primary,
                  ),
                  child: Slider(
                    value: globalPositionSeconds.clamp(0.0, widget.project.totalDuration > 0 ? widget.project.totalDuration : 1.0),
                    max: widget.project.totalDuration > 0 ? widget.project.totalDuration : 1.0,
                    onChangeStart: (v) {
                      setState(() {
                        isTrackingPhase = false;
                        isAutoplaySuspended = true;
                      });
                    },
                    onChanged: (v) {
                      setState(() {
                        globalPositionSeconds = v;
                        isTrackingPhase = false;
                        isAutoplaySuspended = true;
                      });
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
                ),
              ),
              const SizedBox(width: 8),
              Builder(
                builder: (context) {
                  final posDuration = Duration(milliseconds: (globalPositionSeconds * 1000).toInt());
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

  void _startSeeking(bool forward) {
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
    _seekTimer?.cancel();
  }

  bool _showStarFeedback = false;

  void _triggerStarFeedback() {
    _addManualHighlight();
    setState(() => _showStarFeedback = true);
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _showStarFeedback = false);
    });
  }

  Widget _buildMobileVideoPlayer(BuildContext context) {
    final posDuration = Duration(milliseconds: (globalPositionSeconds * 1000).toInt());
    final totalDur = Duration(milliseconds: (widget.project.totalDuration * 1000).toInt());

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
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
            if (details.velocity.pixelsPerSecond.dx > 300) {
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
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Video(
                    controller: controller,
                    controls: NoVideoControls,
                  ),
                ),
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Text(
                    '${_formatDuration(posDuration)} / ${_formatDuration(totalDur)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      shadows: [
                        Shadow(offset: Offset(1, 1), blurRadius: 2, color: Colors.black),
                        Shadow(offset: Offset(-1, -1), blurRadius: 2, color: Colors.black),
                      ],
                    ),
                  ),
                ),
                if (_showStarFeedback)
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0.5, end: 1.5),
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.elasticOut,
                    builder: (context, scale, child) {
                      return Transform.scale(
                        scale: scale,
                        child: Opacity(
                          opacity: 0.8,
                          child: const Icon(Icons.star, color: Colors.amber, size: 100),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
        // Γραμμή 1: Slider
        SizedBox(
          height: 12,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3.0,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12.0),
              trackShape: const RectangularSliderTrackShape(), 
            ),
            child: Slider(
              value: globalPositionSeconds.clamp(0.0, widget.project.totalDuration > 0 ? widget.project.totalDuration : 1.0),
              max: widget.project.totalDuration > 0 ? widget.project.totalDuration : 1.0,
              onChangeStart: (v) {
                setState(() {
                  isTrackingPhase = false;
                  isAutoplaySuspended = true;
                });
              },
              onChanged: (v) {
                setState(() {
                  globalPositionSeconds = v;
                  isTrackingPhase = false;
                  isAutoplaySuspended = true;
                });
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
          ),
        ),
        // Γραμμή 2: Κουμπιά (Συμπαγή & Οβάλ Play)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.star_border, color: Colors.amber, size: 24),
                onPressed: _triggerStarFeedback,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(Icons.skip_previous, color: Theme.of(context).colorScheme.primary, size: 28),
                        onPressed: () => _navigate(-1),
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        constraints: const BoxConstraints(),
                      ),
                      InkWell(
                        onTap: () => player.playOrPause(),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(isPlaying ? Icons.pause : Icons.play_arrow, color: Theme.of(context).colorScheme.onPrimaryContainer, size: 28),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.skip_next, color: Theme.of(context).colorScheme.primary, size: 28),
                        onPressed: () => _navigate(1),
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ],
              ),
              IconButton(
                icon: Icon(Icons.settings, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 24),
                onPressed: () => _showSettingsSheet(context, Provider.of<AppState>(context, listen: false)),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showSettingsSheet(BuildContext context, AppState state) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16.0, right: 16.0, top: 16.0,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16.0
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Center(child: Text('Ρυθμίσεις', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                  const Divider(),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Ευαισθησία: ${sensitivity.toInt()}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            Slider(
                              value: sensitivity, max: 100,
                              onChanged: (v) {
                                setModalState(() => sensitivity = v);
                                setState(() => sensitivity = v);
                                widget.project.sensitivity = v;
                              },
                              onChangeEnd: (v) {
                                print('----------------------------------------------------');
                                print('[USER ACTION] Αλλαγή Sensitivity: ${v.toInt()}');
                                print('----------------------------------------------------');
                                _recalcPhases();
                                state.saveProject(widget.project);
                              },
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Ομαδοποίηση: ${grouping.toStringAsFixed(1)}s', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            Slider(
                              value: grouping, max: 10,
                              onChanged: (v) {
                                setModalState(() => grouping = v);
                                setState(() => grouping = v);
                                widget.project.grouping = v;
                              },
                              onChangeEnd: (v) {
                                print('----------------------------------------------------');
                                print('[USER ACTION] Αλλαγή Grouping: ${v.toStringAsFixed(1)}s');
                                print('----------------------------------------------------');
                                _recalcPhases();
                                state.saveProject(widget.project);
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Start Offset: ${startOffset.toStringAsFixed(1)}s', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            Slider(
                              value: startOffset, max: 10,
                              onChanged: (v) {
                                setModalState(() => startOffset = v);
                                setState(() => startOffset = v);
                                widget.project.startOffset = v;
                              },
                              onChangeEnd: (v) => state.saveProject(widget.project),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('End Offset: ${endOffset.toStringAsFixed(1)}s', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            Slider(
                              value: endOffset, max: 10,
                              onChanged: (v) {
                                setModalState(() => endOffset = v);
                                setState(() => endOffset = v);
                                widget.project.endOffset = v;
                              },
                              onChangeEnd: (v) => state.saveProject(widget.project),
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
                          Checkbox(value: autoplay, onChanged: (v) {
                            setModalState(() => autoplay = v ?? false);
                            setState(() => autoplay = v ?? false);
                            widget.project.autoplay = autoplay;
                            state.saveProject(widget.project);
                          }),
                          const Text('Autoplay', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                      Row(
                        children: [
                          Checkbox(value: skipSeen, onChanged: (v) {
                            setModalState(() => skipSeen = v ?? false);
                            setState(() => skipSeen = v ?? false);
                            widget.project.skipSeen = skipSeen;
                            state.saveProject(widget.project);
                          }),
                          const Text('Skip Seen', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Εντάξει'),
                    ),
                  ),
                ],
              ),
            );
          }
        );
      }
    );
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
                  setState(() => showHighlightsOnly = !showHighlightsOnly);
                  widget.project.showHighlightsOnly = showHighlightsOnly;
                  state.saveProject(widget.project);
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: showHighlightsOnly ? Theme.of(context).colorScheme.primaryContainer : Colors.transparent,
                    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(8),
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
                  onPressed: _resetSeen,
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
                    if (isActive) {
                      bgColor = isDark ? const Color(0xFF7F1D1D) : const Color(0xFFFFE4E6);
                    } else if (isLastPlayed) {
                      bgColor = isDark ? const Color(0xFF78350F) : const Color(0xFFFEF3C7);
                    } else if (phase.isHighlight) {
                      bgColor = isDark ? const Color(0xFF4A148C) : const Color(0xFFF3E5F5);
                    } else {
                      bgColor = isDark ? const Color(0xFF2C2C34) : Colors.white;
                    }

                    Color borderColor;
                    if (isActive) {
                      borderColor = isDark ? const Color(0xFFFCA5A5) : const Color(0xFFEF4444);
                    } else if (isLastPlayed) {
                      borderColor = isDark ? const Color(0xFFFBBF24) : const Color(0xFFF59E0B);
                    } else if (phase.isHighlight) {
                      borderColor = Theme.of(context).colorScheme.primary;
                    } else {
                      borderColor = isDark ? Colors.grey.shade700 : Colors.grey.shade300;
                    }
                    
                    Widget card = Card(
                      key: ObjectKey(phase),
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
                                Text(
                                  '(${chronologicalPhases.indexOf(phase) + 1}) $m:$s', 
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: (isActive || isLastPlayed) ? FontWeight.bold : FontWeight.normal, 
                                    decoration: phase.isSeen && !isActive && !isLastPlayed ? TextDecoration.lineThrough : null,
                                    color: (isActive || isLastPlayed) 
                                      ? (isActive ? (isDark ? const Color(0xFFFCA5A5) : const Color(0xFFB91C1C)) : (isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706)))
                                      : (phase.isSeen ? Colors.grey : null)
                                  )
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
                          ) : Text(
                            '(${chronologicalPhases.indexOf(phase) + 1}) $m:$s', 
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: (isActive || isLastPlayed) ? FontWeight.bold : FontWeight.normal, 
                              decoration: phase.isSeen && !isActive && !isLastPlayed ? TextDecoration.lineThrough : null,
                              color: (isActive || isLastPlayed) 
                                  ? (isActive ? (isDark ? const Color(0xFFFCA5A5) : const Color(0xFFB91C1C)) : (isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706)))
                                  : (phase.isSeen ? Colors.grey : null)
                            )
                          ),
                        ),
                        onTap: () => _playPhase(index, phases),
                      ),
                    );

                    return card;
                  },
                ),
        ),
        if (showHighlightsOnly)
          Container(
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
              border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
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