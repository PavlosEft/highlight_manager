import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:media_kit/media_kit.dart';

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
  List<HighlightPhase> phases;
  DateTime createdAt;
  double totalDuration;

  Project({
    required this.id,
    required this.name,
    required this.videoPaths,
    List<HighlightPhase>? phases,
    DateTime? createdAt,
    this.totalDuration = 0.0,
  })  : phases = phases ?? [],
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'videoPaths': videoPaths,
        'phases': phases.map((e) => e.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'totalDuration': totalDuration,
      };

  factory Project.fromJson(Map<String, dynamic> json) => Project(
        id: json['id'],
        name: json['name'],
        videoPaths: List<String>.from(json['videoPaths']),
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

  // Φορτώνει όλα τα JSON αρχεία κατά την εκκίνηση
  Future<void> loadAllProjects() async {
    isLoading = true;
    notifyListeners();

    try {
      final dir = await _localPath;
      final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json'));
      
      projects.clear();
      for (var file in files) {
        final content = await file.readAsString();
        final jsonMap = jsonDecode(content);
        projects.add(Project.fromJson(jsonMap));
      }
      
      // Ταξινόμηση από το πιο πρόσφατο στο παλαιότερο
      projects.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (e) {
      debugPrint("${t('err_load')} $e");
    }

    isLoading = false;
    notifyListeners();
  }

  // Αποθηκεύει ακαριαία ένα Project σε JSON
  Future<void> saveProject(Project project) async {
    try {
      final dir = await _localPath;
      final file = File('${dir.path}/${project.id}.json');
      await file.writeAsString(jsonEncode(project.toJson()));
      
      if (!projects.any((p) => p.id == project.id)) {
        projects.insert(0, project);
      }
      notifyListeners();
    } catch (e) {
      debugPrint("${t('err_save')} $e");
    }
  }

  // Διαγραφή Project
  Future<void> deleteProject(String id) async {
    try {
      final dir = await _localPath;
      final file = File('${dir.path}/$id.json');
      if (await file.exists()) {
        await file.delete();
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

  // Απευθείας δημιουργία Project μετά το Dialog
  Future<Project> createProjectDirectly(String baseName, List<String> paths) async {
    String finalName = baseName;
    int counter = 1;
    
    // Στυλ Windows: Προσθήκη (1), (2) κλπ. αν το όνομα υπάρχει ήδη
    while (projects.any((p) => p.name == finalName)) {
      finalName = '$baseName ($counter)';
      counter++;
    }

    double totalDur = 0.0;
    final player = Player();
    
    for (String path in paths) {
      try {
        await player.open(Media(path), play: false);
        // Περιμένουμε μέχρι να διαβαστεί η διάρκεια του βίντεο μέσω native API (κινητό ή υπολογιστής)
        for (int i = 0; i < 20; i++) {
          if (player.state.duration != Duration.zero) break;
          await Future.delayed(const Duration(milliseconds: 100));
        }
        totalDur += player.state.duration.inMilliseconds / 1000.0;
      } catch (e) {
        debugPrint("Error reading duration for $path: $e");
      }
    }
    await player.dispose();

    final newProject = Project(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: finalName,
      videoPaths: paths,
      totalDuration: totalDur,
    );

    await saveProject(newProject);
    return newProject;
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

    await state.createProjectDirectly(name, _selectedPaths);
    if (mounted) Navigator.pop(context);
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
                      return ReorderableDragStartListener(
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

  Widget _buildProjectCard(BuildContext context, Project project, AppState state) {
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
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${state.t('open_editor')} ${project.name}...')),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.4),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.video_library, size: 32, color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(project.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 6),
                    Text(
                      '${project.videoPaths.length} ${state.t('video_files')} • ${state.t('duration')} ${formatDuration(project.totalDuration)}\n${state.t('updated')} ${project.createdAt.day}/${project.createdAt.month}/${project.createdAt.year}',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), fontSize: 13, height: 1.4),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                onPressed: () async {
                  bool? confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(state.t('delete_confirm_title'), style: const TextStyle(fontWeight: FontWeight.bold)),
                      content: Text(state.t('delete_confirm_msg')),
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
    final isDesktop = MediaQuery.of(context).size.width > 600;

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
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.projects.isEmpty
              ? Center(
                  child: Text(
                    state.t('no_projects'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                )
              : isDesktop
                  ? GridView.builder(
                      padding: const EdgeInsets.all(24),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 400,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: 2.5,
                      ),
                      itemCount: state.projects.length,
                      itemBuilder: (context, index) => _buildProjectCard(context, state.projects[index], state),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: state.projects.length,
                      itemBuilder: (context, index) => _buildProjectCard(context, state.projects[index], state),
                    ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateProjectDialog(context, state),
        icon: const Icon(Icons.add),
        label: Text(state.t('new_project'), style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}