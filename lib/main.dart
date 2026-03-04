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
import 'package:ffmpeg_kit_flutter_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_min_gpl/return_code.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import 'dart:typed_data';

// ==========================================
// 1. DATA MODELS (Τα δεδομένα μας)
// ==========================================

class HighlightPhase {
  double timestamp;
  bool isHighlight;
  bool isSeen;

  HighlightPhase({
    required this.timestamp,
    this.isHighlight = false,
    this.isSeen = false,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp,
        'isHighlight': isHighlight,
        'isSeen': isSeen,
      };

  factory HighlightPhase.fromJson(Map<String, dynamic> json) => HighlightPhase(
        timestamp: json['timestamp'].toDouble(),
        isHighlight: json['isHighlight'] ?? false,
        isSeen: json['isSeen'] ?? false,
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

  Project({
    required this.id,
    required this.name,
    required this.videoPaths,
    List<double>? videoDurations,
    List<HighlightPhase>? phases,
    DateTime? createdAt,
    this.totalDuration = 0.0,
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
  cardTheme: CardThemeData(
    elevation: 2,
    margin: const EdgeInsets.only(bottom: 12),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ),
);

final darkTheme = ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple, brightness: Brightness.dark),
  useMaterial3: true,
  cardTheme: CardThemeData(
    elevation: 2,
    margin: const EdgeInsets.only(bottom: 12),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ),
);

// ==========================================
// 2. BACKEND / STATE MANAGEMENT
// ==========================================

class AppState extends ChangeNotifier {
  List<Project> projects = [];
  bool isLoading = true;
  String currentLang = 'en';
  bool isDarkMode = false;

  String t(String key) => translations[currentLang]?[key] ?? key;

  void toggleLanguage() {
    currentLang = currentLang == 'el' ? 'en' : 'el';
    notifyListeners();
  }

  void toggleTheme() async {
    isDarkMode = !isDarkMode;
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
  Process? _activeFfmpegProcess;

  void cancelAnalysis() {
    _isAnalysisCancelled = true;
    if (Platform.isWindows || Platform.isLinux) {
      _activeFfmpegProcess?.kill();
    } else {
      FFmpegKit.cancel(); 
    }
  }

  Future<String> _getDesktopFFmpegPath() async {
    final supportDir = await getApplicationSupportDirectory();
    final ffmpegFile = File('${supportDir.path}/ffmpeg.exe');
    
    if (!await ffmpegFile.exists()) {
      final byteData = await rootBundle.load('assets/bin/ffmpeg.exe');
      await ffmpegFile.writeAsBytes(byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));
    }
    return ffmpegFile.path;
  }

  // Ανάλυση και δημιουργία Project με Progress Callback και Ακύρωση
  Future<Project?> analyzeAndCreateProject(String baseName, List<String> paths, Function(String) onStatusUpdate) async {
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
    final player = Player();
    
    List<double> allRms = [];
    List<double> allTimes = [];
    double cumulativeTime = 0.0;

    try {
      for (int i = 0; i < paths.length; i++) {
        if (_isAnalysisCancelled) throw Exception('Cancelled');
        
        String path = paths[i];
        onStatusUpdate("Υπολογισμός διάρκειας ${i + 1}/${paths.length}...");
        
        await player.open(Media(path), play: false);
        for (int j = 0; j < 20; j++) {
          if (player.state.duration != Duration.zero) break;
          await Future.delayed(const Duration(milliseconds: 100));
        }
        double dur = player.state.duration.inMilliseconds / 1000.0;
        totalDur += dur;
        videoDurations.add(dur);

        if (_isAnalysisCancelled) throw Exception('Cancelled');
        
        onStatusUpdate("Εξαγωγή ήχου ${i + 1}/${paths.length}...");
        final audioPath = '${projectDir.path}/temp_audio_$i.wav';
        
        if (Platform.isWindows || Platform.isLinux) {
          final ffmpegExe = await _getDesktopFFmpegPath();
          _activeFfmpegProcess = await Process.start(
            ffmpegExe,
            ['-y', '-i', path, '-vn', '-acodec', 'pcm_s16le', '-ar', '22050', '-ac', '1', audioPath],
          );
          
          // ΑΠΑΡΑΙΤΗΤΟ: Το FFmpeg παράγει πολύ output (logs). Αν δεν το "αδειάσουμε" (drain), 
          // ο buffer του OS γεμίζει και η διεργασία παγώνει για πάντα περιμένοντάς μας.
          _activeFfmpegProcess!.stdout.drain();
          _activeFfmpegProcess!.stderr.drain();

          final exitCode = await _activeFfmpegProcess!.exitCode;
          if (exitCode != 0 || _isAnalysisCancelled) throw Exception('Cancelled or failed');
        } else {
          final cmd = "-y -i \"$path\" -vn -acodec pcm_s16le -ar 22050 -ac 1 \"$audioPath\"";
          final session = await FFmpegKit.execute(cmd);
          final returnCode = await session.getReturnCode();
          if (ReturnCode.isCancel(returnCode) || _isAnalysisCancelled) throw Exception('Cancelled');
        }

        // --- ΠΡΑΓΜΑΤΙΚΗ ΑΝΑΛΥΣΗ RMS ---
        onStatusUpdate("Ανάλυση ήχου ${i + 1}/${paths.length} (0%)...");
        print('[FFMPEG] Εξαγωγή ολοκληρώθηκε. Ανάλυση RMS για το βίντεο ${i + 1}...');
        
        final audioFile = File(audioPath);
        final bytes = await audioFile.readAsBytes();
        final byteData = bytes.buffer.asByteData(bytes.offsetInBytes, bytes.lengthInBytes);
        
        // 44 bytes header, 2 bytes per sample
        final int numSamples = (bytes.length - 44) ~/ 2;
        final int frameLength = 2048;
        final int hopLength = 512;
        final double sr = 22050.0;
        
        int totalFrames = numSamples ~/ hopLength;
        int logStep = (totalFrames / 4).floor();
        if (logStep == 0) logStep = 1;
        int stepCount = 0;

        for (int k = 0; k <= numSamples - frameLength; k += hopLength) {
          if (_isAnalysisCancelled) throw Exception('Cancelled');
          
          double sumSq = 0.0;
          for (int j = 0; j < frameLength; j++) {
            int byteOffset = 44 + ((k + j) * 2);
            double sample = byteData.getInt16(byteOffset, Endian.little) / 32768.0;
            sumSq += sample * sample;
          }
          allRms.add(math.sqrt(sumSq / frameLength));
          allTimes.add((k / sr) + cumulativeTime);
          
          stepCount++;
          if (stepCount % logStep == 0 || stepCount == totalFrames) {
            int percent = (stepCount / totalFrames * 100).toInt().clamp(0, 100);
            print('[RMS Ανάλυση Βίντεο ${i+1}] $percent% ολοκληρώθηκε...');
            onStatusUpdate("Ανάλυση ήχου ${i + 1}/${paths.length} ($percent%)...");
            await Future.delayed(const Duration(milliseconds: 10)); // Επιτρέπει στο UI να ανανεωθεί
          }
        }
        
        cumulativeTime += numSamples / sr;
        
        if (await audioFile.exists()) {
          await audioFile.delete();
        }
      }

      if (_isAnalysisCancelled) throw Exception('Cancelled');

      onStatusUpdate("Αποθήκευση δεδομένων...");
      double maxRms = 0.0;
      double sumRms = 0.0;
      for (double r in allRms) {
        if (r > maxRms) maxRms = r;
        sumRms += r;
      }
      double avgRms = allRms.isEmpty ? 0.0 : sumRms / allRms.length;
      print('[ΑΝΑΛΥΣΗ ΟΛΟΚΛΗΡΩΘΗΚΕ] Max RMS: $maxRms, Avg RMS: $avgRms, Δείγματα: ${allRms.length}');

      // Αποθήκευση της ανάλυσης ΜΕΣΑ στον φάκελο του project
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
      // Cleanup: Διαγράφει ΟΛΟΚΛΗΡΟ τον φάκελο του project (και τα temp audio)
      if (await projectDir.exists()) {
        await projectDir.delete(recursive: true);
      }
      return null;
    } finally {
      await player.dispose();
    }
  }
}

// ==========================================
// 3. FRONTEND / UI
// ==========================================

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (context) => AppState(),
      child: const HighlightManagerApp(),
    ),
  );
}

class HighlightManagerApp extends StatelessWidget {
  const HighlightManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppState>(context);
    return MaterialApp(
      title: 'Highlight Manager',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: state.isDarkMode ? ThemeMode.dark : ThemeMode.light,
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
  bool isCancelled = false;

  @override
  void initState() {
    super.initState();
    _startProcess();
  }

  void _startProcess() async {
    final project = await widget.state.analyzeAndCreateProject(
      widget.baseName,
      widget.paths,
      (newStatus) {
        if (mounted) setState(() => status = newStatus);
      }
    );
    if (mounted) {
      Navigator.pop(context, project != null); // Επιστρέφει true αν πετύχει, false αν ακυρωθεί
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Επεξεργασία', style: TextStyle(fontWeight: FontWeight.bold)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(status, textAlign: TextAlign.center),
        ],
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
  bool _userEditedName = false;

  void _pickFiles() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: true,
    );

    if (result != null && result.paths.isNotEmpty) {
      setState(() {
        for (String? path in result.paths) {
          if (path != null && !_selectedPaths.contains(path)) {
            _selectedPaths.add(path);
          }
        }
        _updateAutoName();
      });
    }
  }

  void _updateAutoName() {
    if (_userEditedName || _selectedPaths.isEmpty) return;
    
    List<String> baseNames = _selectedPaths.map((path) {
      String fileName = path.split(RegExp(r'[\\/]')).last;
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
    return AlertDialog(
      title: Text(t('new_project'), style: const TextStyle(fontWeight: FontWeight.bold)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
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
                FilledButton.icon(
                  onPressed: _pickFiles,
                  icon: const Icon(Icons.folder_open),
                  label: Text(t('add_videos')),
                ),
                const Spacer(),
                if (_selectedPaths.isNotEmpty)
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _selectedPaths.clear();
                        _userEditedName = false;
                        _nameController.clear();
                      });
                    },
                    icon: const Icon(Icons.clear, color: Colors.red),
                    label: Text(t('clear_all'), style: const TextStyle(color: Colors.red)),
                  )
              ],
            ),
            const SizedBox(height: 16),
            if (_selectedPaths.isNotEmpty)
              Flexible(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.withOpacity(0.3)),
                    borderRadius: BorderRadius.circular(8),
                  ),
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
                      final fileName = path.split(RegExp(r'[\\/]')).last;
                      return ReorderableDelayedDragStartListener(
                        key: ValueKey(path),
                        index: index,
                        child: ListTile(
                          leading: CircleAvatar(
                            radius: 14,
                            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                            child: Text('${index + 1}', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onPrimaryContainer, fontWeight: FontWeight.bold)),
                          ),
                          title: Text(fileName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
                          trailing: IconButton(
                            icon: Icon(Icons.delete_outline, size: 20, color: Theme.of(context).colorScheme.error),
                            onPressed: () {
                              setState(() {
                                _selectedPaths.removeAt(index);
                                if (!_userEditedName) _updateAutoName();
                              });
                            },
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
      builder: (ctx) => AlertDialog(
        title: Text(state.t('rename_project'), style: const TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(
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
      ),
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

    return Scaffold(
      appBar: AppBar(
        title: Text(state.t('title'), style: const TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 2,
        actions: [
          IconButton(
            icon: Icon(state.isDarkMode ? Icons.wb_sunny : Icons.nightlight_round),
            onPressed: state.toggleTheme,
          ),
          TextButton(
            onPressed: state.toggleLanguage,
            child: Text(state.currentLang.toUpperCase(), style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
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
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            itemCount: state.projects.length,
                            itemBuilder: (context, index) => _buildProjectCard(context, state.projects[index], state),
                          ),
              ),
            ],
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
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
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
                      final res = await FilePicker.platform.pickFiles(type: FileType.media);
                      if (res != null && res.files.single.path != null) {
                        setState(() => transPath = res.files.single.path!);
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
    final supportDir = await getApplicationSupportDirectory();
    final ffmpegFile = File('${supportDir.path}/ffmpeg.exe');
    if (!await ffmpegFile.exists()) {
      final byteData = await rootBundle.load('assets/bin/ffmpeg.exe');
      await ffmpegFile.writeAsBytes(byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));
    }
    return ffmpegFile.path;
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
      final session = await FFmpegKit.executeWithArguments(args);
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
          final startGlobal = math.max(0.0, ts - widget.startOffset);
          final localData = _getLocalVideoData(startGlobal);
          final dur = widget.startOffset + widget.endOffset + 0.5;
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
          final startGlobal = math.max(0.0, ts - widget.startOffset);
          final localData = _getLocalVideoData(startGlobal);
          final dur = widget.startOffset + widget.endOffset + 0.5;
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
      title: Text(isFinished ? 'Ολοκληρώθηκε' : 'Επεξεργασία...', style: const TextStyle(fontWeight: FontWeight.bold)),
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

  // --- UI Settings State ---
  double sensitivity = 55.0;
  double grouping = 2.0;
  double startOffset = 2.0;
  double endOffset = 3.0;
  bool autoplay = false;
  bool skipSeen = false;
  
  // --- Filters ---
  bool showHighlightsOnly = false;
  bool hideSeenPhases = false;

  // --- Analysis Data ---
  List<double> rmsData = [];
  List<double> timesData = [];
  double maxRms = 0.0;
  double avgRms = 0.0;
  bool isLoadingAnalysis = true;

  @override
  void initState() {
    super.initState();
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

      if (!isPlaying || currentPlayingPhase == null) return;
      
      final targetEnd = currentPlayingPhase!.timestamp + endOffset;

      if (currentGlobalSec >= targetEnd) {
        if (autoplay) {
          _navigate(1);
        } else {
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

        _recalcPhases();
      }
    } catch (e) {
      debugPrint("Error loading analysis: $e");
    } finally {
      if (mounted) setState(() => isLoadingAnalysis = false);
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

    finalPhases.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    setState(() {
      widget.project.phases = finalPhases;
    });
  }

  List<HighlightPhase> get _filteredPhases {
    return widget.project.phases.where((p) {
      if (showHighlightsOnly && !p.isHighlight) return false;
      if (hideSeenPhases && p.isSeen) return false;
      return true;
    }).toList();
  }

  void _navigate(int direction) {
    final phases = _filteredPhases;
    if (phases.isEmpty) return;
    
    int newIndex = activePhaseIndex + direction;
    
    if (direction == 1 && skipSeen) {
      while (newIndex < phases.length && phases[newIndex].isSeen) {
        newIndex++;
      }
    }
    
    if (newIndex >= 0 && newIndex < phases.length) {
      _playPhase(newIndex, phases);
    } else {
      player.pause();
    }
  }

  Future<void> _seekGlobal(double targetSeconds) async {
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
        } else {
          await player.seek(Duration(milliseconds: (localSeconds * 1000).toInt()));
        }
        break;
      }
      accumulated += dur;
    }
  }

  Future<void> _playPhase(int index, List<HighlightPhase> phases) async {
    if (index < 0 || index >= phases.length) return;
    
    setState(() {
      activePhaseIndex = index;
      currentPlayingPhase = phases[index];
      currentPlayingPhase!.isSeen = true;
    });
    
    Provider.of<AppState>(context, listen: false).saveProject(widget.project);
    
    double startSeconds = math.max(0.0, currentPlayingPhase!.timestamp - startOffset);
    print('[PLAYBACK] Starting phase at ${startSeconds.toStringAsFixed(2)}s globally');
    await _seekGlobal(startSeconds);
    player.play();
  }

  @override
  void dispose() {
    playingSub?.cancel();
    durationSub?.cancel();
    positionSub?.cancel();
    player.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    int h = d.inHours;
    int m = d.inMinutes.remainder(60);
    int s = d.inSeconds.remainder(60);
    if (h > 0) return "${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
    return "${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
  }

  void _addManualHighlight() {
    final state = Provider.of<AppState>(context, listen: false);
    final currentPos = globalPositionSeconds;
    
    setState(() {
      widget.project.phases.add(HighlightPhase(
        timestamp: currentPos,
        isHighlight: true,
      ));
      widget.project.phases.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    });
    
    state.saveProject(widget.project);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Προστέθηκε highlight στο ${currentPos.toStringAsFixed(1)}s')),
    );
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
                iconSize: 42,
                color: Theme.of(context).colorScheme.primary,
                icon: Icon(isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill),
                onPressed: () => player.playOrPause(),
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
                    onChanged: (v) {
                      setState(() => globalPositionSeconds = v);
                      _seekGlobal(v);
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

  Widget _buildSidePanel(BuildContext context, AppState state) {
    final phases = _filteredPhases;

    return Column(
      children: [
        // --- SETTINGS AREA ---
        Container(
          padding: const EdgeInsets.all(8.0),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
            border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Ευαισθησία: ${sensitivity.toInt()}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        Slider(
                          value: sensitivity, max: 100,
                          onChanged: (v) => setState(() => sensitivity = v),
                          onChangeEnd: (v) {
                            _recalcPhases();
                            Provider.of<AppState>(context, listen: false).saveProject(widget.project);
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
                          onChanged: (v) => setState(() => grouping = v),
                          onChangeEnd: (v) {
                            _recalcPhases();
                            Provider.of<AppState>(context, listen: false).saveProject(widget.project);
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
                          onChanged: (v) => setState(() => startOffset = v),
                          onChangeEnd: (v) => Provider.of<AppState>(context, listen: false).saveProject(widget.project),
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
                          onChanged: (v) => setState(() => endOffset = v),
                          onChangeEnd: (v) => Provider.of<AppState>(context, listen: false).saveProject(widget.project),
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
                      Checkbox(value: autoplay, onChanged: (v) => setState(() => autoplay = v ?? false)),
                      const Text('Autoplay', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                  Row(
                    children: [
                      Checkbox(value: skipSeen, onChanged: (v) => setState(() => skipSeen = v ?? false)),
                      const Text('Skip Seen', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),

        // --- FILTERS & MANUAL ADD ---
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: showHighlightsOnly ? Theme.of(context).colorScheme.primaryContainer : null,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  onPressed: () => setState(() => showHighlightsOnly = !showHighlightsOnly),
                  child: Text('Highlights', style: TextStyle(fontSize: 11, fontWeight: showHighlightsOnly ? FontWeight.bold : FontWeight.normal)),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: hideSeenPhases ? Theme.of(context).colorScheme.primaryContainer : null,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  onPressed: () => setState(() => hideSeenPhases = !hideSeenPhases),
                  child: Text('Hide Seen', style: TextStyle(fontSize: 11, fontWeight: hideSeenPhases ? FontWeight.bold : FontWeight.normal)),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 8)),
                  onPressed: _addManualHighlight,
                  child: const Text('Add Manual', style: TextStyle(fontSize: 11)),
                ),
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
              : ListView.builder(
                  itemCount: phases.length,
                  itemBuilder: (context, index) {
                    final phase = phases[index];
                    final m = (phase.timestamp ~/ 60).toString().padLeft(2, '0');
                    final s = (phase.timestamp % 60).toInt().toString().padLeft(2, '0');
                    
                    final isDark = Theme.of(context).brightness == Brightness.dark;
                    final isActive = (index == activePhaseIndex && currentPlayingPhase == phase);
                    
                    Color bgColor;
                    if (isActive) {
                      bgColor = isDark ? const Color(0xFF7F1D1D) : const Color(0xFFFFE4E6);
                    } else if (phase.isHighlight) {
                      bgColor = isDark ? const Color(0xFF4A148C) : const Color(0xFFF3E5F5);
                    } else {
                      bgColor = isDark ? const Color(0xFF2C2C34) : Colors.white;
                    }

                    Color borderColor;
                    if (isActive) {
                      borderColor = isDark ? const Color(0xFFFCA5A5) : const Color(0xFFEF4444);
                    } else if (phase.isHighlight) {
                      borderColor = Theme.of(context).colorScheme.primary;
                    } else {
                      borderColor = isDark ? Colors.grey.shade700 : Colors.grey.shade300;
                    }
                    
                    return Card(
                      elevation: isDark ? 2 : 1,
                      color: bgColor,
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(color: borderColor, width: isActive ? 2 : 1),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                        leading: IconButton(
                          icon: Icon(
                            phase.isHighlight ? Icons.star : Icons.star_border,
                            color: phase.isHighlight ? Colors.amber : Colors.grey,
                          ),
                          onPressed: () {
                            setState(() => phase.isHighlight = !phase.isHighlight);
                            state.saveProject(widget.project);
                          },
                        ),
                        title: Text(
                          '$m:$s', 
                          style: TextStyle(
                            fontWeight: isActive ? FontWeight.bold : FontWeight.normal, 
                            decoration: phase.isSeen && !isActive ? TextDecoration.lineThrough : null,
                            color: phase.isSeen && !isActive ? Colors.grey : (isActive ? (isDark ? const Color(0xFFFCA5A5) : const Color(0xFFB91C1C)) : null)
                          )
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(phase.isSeen ? Icons.visibility_off : Icons.visibility, size: 20),
                              onPressed: () {
                                setState(() => phase.isSeen = !phase.isSeen);
                                state.saveProject(widget.project);
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                              onPressed: () {
                                setState(() {
                                  widget.project.phases.remove(phase);
                                  if (currentPlayingPhase == phase) {
                                    activePhaseIndex = -1;
                                    currentPlayingPhase = null;
                                  }
                                });
                                state.saveProject(widget.project);
                              },
                            ),
                          ],
                        ),
                        onTap: () => _playPhase(index, phases),
                      ),
                    );
                  },
                ),
        ),
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
    final highlights = widget.project.phases.where((p) => p.isHighlight).toList();
    if (highlights.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Δεν υπάρχουν Highlights για εξαγωγή!')));
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

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppState>(context);
    
    return Scaffold(
      appBar: AppBar(
        title: Text('${state.t('editor_title')}: ${widget.project.name}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        elevation: 2,
        actions: [
          IconButton(
            icon: Icon(state.isDarkMode ? Icons.wb_sunny : Icons.nightlight_round),
            onPressed: state.toggleTheme,
          ),
          TextButton(
            onPressed: state.toggleLanguage,
            child: Text(state.currentLang.toUpperCase(), style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          const SizedBox(width: 8),
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
                    flex: 3,
                    child: _buildVideoPlayer(context),
                  ),
                  Container(width: 1, color: Theme.of(context).dividerColor),
                  Expanded(
                    flex: 1,
                    child: _buildSidePanel(context, state),
                  ),
                ],
              );
            } else {
              return Column(
                children: [
                  Expanded(
                    flex: 4,
                    child: _buildVideoPlayer(context),
                  ),
                  Expanded(
                    flex: 5,
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