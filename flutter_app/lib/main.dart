import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/notes_provider.dart';
import 'services/note_service.dart';
import 'screens/notes_list_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Object? startupError;

  try {
    await NoteService.init();
  } catch (error) {
    startupError = error;
  }

  runApp(
    ChangeNotifierProvider(
      create: (_) {
        final provider = NotesProvider();
        if (startupError == null) {
          provider.loadNotes();
        }
        return provider;
      },
      child: MiniNoteApp(startupError: startupError),
    ),
  );
}

class MiniNoteApp extends StatelessWidget {
  const MiniNoteApp({super.key, this.startupError});

  final Object? startupError;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MiniNote',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.deepPurple,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.deepPurple,
        brightness: Brightness.dark,
      ),
      home: startupError == null
          ? const NotesListScreen()
          : Scaffold(
              appBar: AppBar(title: const Text('MiniNote')),
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Text(
                    'Failed to initialize native core:\n$startupError',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
    );
  }
}
