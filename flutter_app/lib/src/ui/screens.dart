import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

import '../domain/note.dart';
import 'specular_app.dart';

class NoteListScreen extends ConsumerWidget {
  const NoteListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(
          title: const Text('Specular'),
          actions: [
            IconButton(onPressed: () => context.push('/search'), icon: const Icon(Icons.search)),
            IconButton(onPressed: () => context.push('/todos'), icon: const Icon(Icons.checklist)),
            IconButton(onPressed: () => context.push('/voice'), icon: const Icon(Icons.mic)),
            IconButton(onPressed: () => context.push('/settings'), icon: const Icon(Icons.settings)),
          ],
        ),
        body: ref.watch(notesProvider).when(
              data: (notes) => notes.isEmpty
                  ? const Center(child: Text('No notes yet. Create one to get started.'))
                  : ListView.separated(
                      itemCount: notes.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, index) => _NoteTile(note: notes[index]),
                    ),
              error: (error, _) => Center(child: Text('Unable to load notes: $error')),
              loading: () => const Center(child: CircularProgressIndicator()),
            ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => context.push('/editor/new'),
          child: const Icon(Icons.add),
        ),
      );
}

class _NoteTile extends StatelessWidget {
  const _NoteTile({required this.note});
  final Note note;

  @override
  Widget build(BuildContext context) => ListTile(
        title: Row(children: [
          if (note.isPinned) const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.push_pin, size: 16)),
          Expanded(child: Text(note.title.isEmpty ? 'Untitled' : note.title)),
        ]),
        subtitle: Text(note.body.replaceAll(RegExp(r'^#.+$', multiLine: true), '').trim(), maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: note.isConflict ? const Icon(Icons.warning_amber_rounded, color: Colors.orange) : null,
        onTap: () => context.push('/note/${Uri.encodeComponent(note.id)}'),
      );
}

class NoteDetailScreen extends ConsumerWidget {
  const NoteDetailScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) => FutureBuilder<Note?>(
        future: ref.read(noteRepositoryProvider).get(id),
        builder: (context, snapshot) {
          final note = snapshot.data;
          if (!snapshot.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
          if (note == null) return const Scaffold(body: Center(child: Text('Note not found')));
          return Scaffold(
            appBar: AppBar(
              title: Text(note.title),
              actions: [IconButton(onPressed: () => context.push('/editor/${Uri.encodeComponent(note.id)}'), icon: const Icon(Icons.edit))],
            ),
            body: Markdown(data: note.body, padding: const EdgeInsets.all(16)),
          );
        },
      );
}

class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key, this.id});
  final String? id;

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  Note? _note;
  var _loading = true;
  var _saving = false;
  final _images = ImagePicker();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.id != null) {
      _note = await ref.read(noteRepositoryProvider).get(widget.id!);
      _title.text = _note?.title ?? '';
      _body.text = _note?.body ?? '';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final repo = ref.read(noteRepositoryProvider);
    final saved = _note == null
        ? await repo.create(title: _title.text, body: _body.text)
        : await repo.save(_note!, title: _title.text, body: _body.text);
    if (mounted) context.go('/note/${Uri.encodeComponent(saved.id)}');
  }

  Future<void> _addImage(ImageSource source) async {
    if (_note == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Save the note before adding an image.')));
      return;
    }
    final image = await _images.pickImage(source: source, imageQuality: 90);
    if (image == null) return;
    final saved = await ref.read(noteRepositoryProvider).importImage(_note!, File(image.path));
    _note = saved;
    _body.text = saved.body;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(_note == null ? 'New note' : 'Edit note'),
          actions: [
            IconButton(onPressed: () => _addImage(ImageSource.camera), icon: const Icon(Icons.photo_camera)),
            IconButton(onPressed: () => _addImage(ImageSource.gallery), icon: const Icon(Icons.photo_library)),
            IconButton(onPressed: _saving ? null : _save, icon: _saving ? const CircularProgressIndicator() : const Icon(Icons.done)),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  TextField(controller: _title, decoration: const InputDecoration(labelText: 'Title')),
                  const SizedBox(height: 12),
                  Expanded(
                    child: TextField(
                      controller: _body,
                      expands: true,
                      maxLines: null,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: const InputDecoration(labelText: 'Markdown', alignLabelWithHint: true, border: OutlineInputBorder()),
                    ),
                  ),
                ]),
              ),
      );
}

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  var _query = '';
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: TextField(autofocus: true, onChanged: (value) => setState(() => _query = value), decoration: const InputDecoration(hintText: 'Search notes'))),
        body: StreamBuilder<List<Note>>(
          stream: ref.read(noteRepositoryProvider).search(_query),
          builder: (_, snapshot) => ListView(children: [for (final note in snapshot.data ?? const <Note>[]) _NoteTile(note: note)]),
        ),
      );
}

class TodoScreen extends ConsumerWidget {
  const TodoScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(title: const Text('To-dos')),
        body: ref.watch(todosProvider).when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('$error')),
              data: (todos) => ListView(
                children: [
                  for (final todo in todos)
                    CheckboxListTile(
                      value: todo.isCompleted,
                      title: Text(todo.text),
                      subtitle: Text(todo.noteTitle),
                      onChanged: (_) => ref.read(noteRepositoryProvider).toggleTodo(todo),
                    ),
                ],
              ),
            ),
      );
}

class VoiceCaptureScreen extends ConsumerStatefulWidget {
  const VoiceCaptureScreen({super.key});
  @override
  ConsumerState<VoiceCaptureScreen> createState() => _VoiceCaptureScreenState();
}

class _VoiceCaptureScreenState extends ConsumerState<VoiceCaptureScreen> {
  final _transcript = TextEditingController();
  var _recording = false;
  var _busy = false;
  var _asTodo = false;
  String? _error;

  Future<void> _start() async {
    try {
      await ref.read(voiceServiceProvider).start();
      if (mounted) setState(() => _recording = true);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _stop() async {
    setState(() => _busy = true);
    try {
      final transcript = await ref.read(voiceServiceProvider).stopAndTranscribe();
      if (mounted) setState(() { _transcript.text = transcript; _recording = false; });
    } catch (error) {
      if (mounted) setState(() { _recording = false; _error = '$error'; });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_transcript.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final note = await ref.read(noteRepositoryProvider).appendToToday(_asTodo ? '- [ ] ${_transcript.text.trim()}' : _transcript.text);
      if (mounted) context.go('/note/${Uri.encodeComponent(note.id)}');
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _transcript.dispose();
    ref.read(voiceServiceProvider).cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Voice capture')),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Record a thought or to-do, then review its transcript before adding it to today.'),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
            const SizedBox(height: 20),
            if (_transcript.text.isNotEmpty)
              Expanded(child: TextField(controller: _transcript, maxLines: null, expands: true, decoration: const InputDecoration(labelText: 'Transcript', border: OutlineInputBorder()))),
            if (_transcript.text.isEmpty) const Spacer(),
            SwitchListTile(value: _asTodo, onChanged: _busy ? null : (value) => setState(() => _asTodo = value), title: const Text('Save as to-do')),
            if (_transcript.text.isNotEmpty)
              FilledButton(onPressed: _busy ? null : _save, child: Text(_asTodo ? 'Add to-do to today' : 'Add thought to today'))
            else
              FilledButton.icon(
                onPressed: _busy ? null : (_recording ? _stop : _start),
                icon: Icon(_recording ? Icons.stop : Icons.mic),
                label: Text(_busy ? 'Transcribing…' : (_recording ? 'Stop and transcribe' : 'Start recording')),
              ),
          ]),
        ),
      );
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _token = TextEditingController();
  final _owner = TextEditingController();
  final _repo = TextEditingController();
  final _aiUrl = TextEditingController();
  final _aiKey = TextEditingController();
  final _aiModel = TextEditingController();
  final _voiceModel = TextEditingController();
  final _voiceEndpoint = TextEditingController();
  final _voiceKey = TextEditingController();
  var _voiceProvider = 'OPENAI';
  var _usePreviewKey = true;
  var _loaded = false;

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    final storage = ref.read(secureStorageProvider);
    _token.text = await storage.read(key: 'github_token') ?? '';
    _owner.text = await storage.read(key: 'repo_owner') ?? '';
    _repo.text = await storage.read(key: 'repo_name') ?? '';
    _aiUrl.text = await storage.read(key: 'ai_provider_url') ?? '';
    _aiKey.text = await storage.read(key: 'ai_provider_api_key') ?? '';
    _aiModel.text = await storage.read(key: 'ai_provider_model_id') ?? '';
    _voiceProvider = await storage.read(key: 'voice_provider') ?? 'OPENAI';
    _voiceModel.text = await storage.read(key: 'voice_model_id') ?? '';
    _voiceEndpoint.text = await storage.read(key: 'voice_endpoint') ?? '';
    _voiceKey.text = await storage.read(key: 'voice_api_key') ?? '';
    _usePreviewKey = await storage.read(key: 'voice_use_preview_key') != 'false';
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    final storage = ref.read(secureStorageProvider);
    await storage.write(key: 'github_token', value: _token.text.trim());
    await storage.write(key: 'repo_owner', value: _owner.text.trim());
    await storage.write(key: 'repo_name', value: _repo.text.trim());
    await storage.write(key: 'ai_provider_url', value: _aiUrl.text.trim());
    await storage.write(key: 'ai_provider_api_key', value: _aiKey.text.trim());
    await storage.write(key: 'ai_provider_model_id', value: _aiModel.text.trim());
    await storage.write(key: 'voice_provider', value: _voiceProvider);
    await storage.write(key: 'voice_model_id', value: _voiceModel.text.trim());
    await storage.write(key: 'voice_endpoint', value: _voiceEndpoint.text.trim());
    await storage.write(key: 'voice_api_key', value: _voiceKey.text.trim());
    await storage.write(key: 'voice_use_preview_key', value: _usePreviewKey.toString());
    final sync = await ref.read(syncEngineProvider).sync();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(sync.message)));
  }

  @override
  void dispose() {
    _token.dispose();
    _owner.dispose();
    _repo.dispose();
    _aiUrl.dispose();
    _aiKey.dispose();
    _aiModel.dispose();
    _voiceModel.dispose();
    _voiceEndpoint.dispose();
    _voiceKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _load();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(children: [
          TextField(controller: _token, obscureText: true, decoration: const InputDecoration(labelText: 'GitHub personal access token')),
          TextField(controller: _owner, decoration: const InputDecoration(labelText: 'Repository owner')),
          TextField(controller: _repo, decoration: const InputDecoration(labelText: 'Repository name')),
          ExpansionTile(
            title: const Text('AI snippet provider'),
            children: [
              TextField(controller: _aiUrl, decoration: const InputDecoration(labelText: 'OpenAI-compatible endpoint')),
              TextField(controller: _aiKey, obscureText: true, decoration: const InputDecoration(labelText: 'API key')),
              TextField(controller: _aiModel, decoration: const InputDecoration(labelText: 'Model')),
            ],
          ),
          ExpansionTile(
            title: const Text('Voice transcription'),
            children: [
              DropdownButtonFormField<String>(initialValue: _voiceProvider, items: const [
                DropdownMenuItem(value: 'OPENAI', child: Text('OpenAI')),
                DropdownMenuItem(value: 'OPENROUTER', child: Text('OpenRouter')),
                DropdownMenuItem(value: 'CUSTOM_OPENAI_COMPATIBLE', child: Text('Custom OpenAI-compatible')),
              ], onChanged: (value) => setState(() => _voiceProvider = value!)),
              TextField(controller: _voiceModel, decoration: const InputDecoration(labelText: 'Voice model')),
              TextField(controller: _voiceEndpoint, decoration: const InputDecoration(labelText: 'Custom endpoint (only for custom)')),
              SwitchListTile(value: _usePreviewKey, onChanged: (value) => setState(() => _usePreviewKey = value), title: const Text('Use AI snippet API key')),
              if (!_usePreviewKey) TextField(controller: _voiceKey, obscureText: true, decoration: const InputDecoration(labelText: 'Voice API key')),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: const Text('Save and sync')),
        ]),
      ),
    );
  }
}
