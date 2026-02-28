import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';

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

  Project({
    required this.id,
    required this.name,
    required this.videoPaths,
    List<HighlightPhase>? phases,
    DateTime? createdAt,
  })  : phases = phases ?? [],
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'videoPaths': videoPaths,
        'phases': phases.map((e) => e.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
      };

  factory Project.fromJson(Map<String, dynamic> json) => Project(
        id: json['id'],
        name: json['name'],
        videoPaths: List<String>.from(json['videoPaths']),
        phases: (json['phases'] as List)
            .map((e) => HighlightPhase.fromJson(e))
            .toList(),
        createdAt: DateTime.parse(json['createdAt']),
      );
}

// ==========================================
// 1.5 LOCALIZATION
// ==========================================
const Map<String, Map<String, String>> translations = {
  'el': {
    'title': '🎬 Highlight Manager!',
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
  },
  'en': {
    'title': '🎬 Highlight Manager!',
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
  }
};

// ==========================================
// 2. BACKEND / STATE MANAGEMENT
// ==========================================

class AppState extends ChangeNotifier {
  List<Project> projects = [];
  bool isLoading = true;
  String currentLang = 'en';

  String t(String key) => translations[currentLang]?[key] ?? key;

  void toggleLanguage() {
    currentLang = currentLang == 'el' ? 'en' : 'el';
    notifyListeners();
  }

  AppState() {
    loadAllProjects();
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

  // Δημιουργία Νέου Project μέσω File Picker
  Future<Project?> createNewProject(String name) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: true,
    );

    if (result != null && result.paths.isNotEmpty) {
      // Φιλτράρισμα null paths
      List<String> validPaths = result.paths.whereType<String>().toList();
      
      final newProject = Project(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        videoPaths: validPaths,
      );

      await saveProject(newProject);
      return newProject;
    }
    return null;
  }
}

// ==========================================
// 3. FRONTEND / UI
// ==========================================

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
    return MaterialApp(
      title: 'Highlight Manager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurpleAccent,
          brightness: Brightness.dark,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _showCreateProjectDialog(BuildContext context, AppState state) {
    final TextEditingController nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(state.t('new_project'), style: const TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: nameController,
          decoration: InputDecoration(
            hintText: state.t('example_hint'),
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(state.t('cancel')),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(context);
                await state.createNewProject(name);
              }
            },
            child: Text(state.t('select_video')),
          ),
        ],
      ),
    );
  }

  Widget _buildProjectCard(BuildContext context, Project project, AppState state) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                  color: Colors.deepPurpleAccent.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.video_library, size: 32, color: Colors.deepPurpleAccent),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(project.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 6),
                    Text('${project.videoPaths.length} ${state.t('video_files')}\n${state.t('updated')} ${project.createdAt.day}/${project.createdAt.month}/${project.createdAt.year}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                onPressed: () => state.deleteProject(project.id),
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
          TextButton(
            onPressed: state.toggleLanguage,
            child: Text(state.currentLang.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
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