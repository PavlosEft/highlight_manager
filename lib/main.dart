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
// 2. BACKEND / STATE MANAGEMENT
// ==========================================

class AppState extends ChangeNotifier {
  List<Project> projects = [];
  bool isLoading = true;

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
      debugPrint("Σφάλμα φόρτωσης projects: $e");
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
      debugPrint("Σφάλμα αποθήκευσης project: $e");
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
      debugPrint("Σφάλμα διαγραφής project: $e");
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

  void _showCreateProjectDialog(BuildContext context) {
    final TextEditingController nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Νέο Project', style: TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            hintText: "π.χ. Αγώνας Κυριακής",
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Ακύρωση'),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(context); // Κλείνουμε το dialog
                final state = Provider.of<AppState>(context, listen: false);
                await state.createNewProject(name);
              }
            },
            child: const Text('Επιλογή Βίντεο'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppState>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('🎬 Highlight Manager!', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 2,
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.projects.isEmpty
              ? const Center(
                  child: Text(
                    "Δεν υπάρχουν projects ακόμα.\nΠάτα το '+' για να ξεκινήσεις!",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: state.projects.length,
                  itemBuilder: (context, index) {
                    final project = state.projects[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.deepPurpleAccent.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.video_library, size: 28, color: Colors.deepPurpleAccent),
                        ),
                        title: Text(project.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text('${project.videoPaths.length} αρχεία βίντεο\nΑνανεώθηκε: ${project.createdAt.day}/${project.createdAt.month}/${project.createdAt.year}'),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                          onPressed: () {
                            state.deleteProject(project.id);
                          },
                        ),
                        onTap: () {
                          // Εδώ θα κάνουμε Navigate στην οθόνη του Editor στη Φάση 2
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Άνοιγμα Editor για: ${project.name}...')),
                          );
                        },
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateProjectDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Νέο Project', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}