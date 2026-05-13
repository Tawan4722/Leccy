import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/models.dart';
import 'app_controller.dart';
import 'cover_image_provider.dart'
    if (dart.library.io) 'cover_image_provider_io.dart';

class LeccyApp extends ConsumerWidget {
  const LeccyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appControllerProvider);
    final isDark = app.themeMode == AppThemeMode.dark;
    final base = isDark
        ? const ColorScheme.dark(
            primary: Color(0xFF8BC7FF),
            secondary: Color(0xFFB4E7D2),
            surface: Color(0xFF171A21),
            onSurface: Color(0xFFE8ECF5),
          )
        : const ColorScheme.light(
            primary: Color(0xFF2457C5),
            secondary: Color(0xFF0F9D8F),
            surface: Color(0xFFF4F7FF),
            onSurface: Color(0xFF111318),
          );

    return MaterialApp(
      title: 'Leccy',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        quill.FlutterQuillLocalizations.delegate,
      ],
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      theme: _buildTheme(base, false),
      darkTheme: _buildTheme(base, true),
      home: const LeccyHomePage(),
    );
  }

  ThemeData _buildTheme(ColorScheme scheme, bool isDark) {
    final baseTextTheme = const TextTheme(
      headlineSmall: TextStyle(fontSize: 25, fontWeight: FontWeight.w600),
      titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      bodyMedium: TextStyle(fontSize: 13),
      bodySmall: TextStyle(fontSize: 12),
    );
    return ThemeData(
      useMaterial3: true,
      textTheme: GoogleFonts.workSansTextTheme(baseTextTheme),
      primaryTextTheme: GoogleFonts.workSansTextTheme(baseTextTheme),
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark
          ? const Color(0xFF0D1016)
          : const Color(0xFFECEFF8),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(20)),
          borderSide: BorderSide(
            color: isDark ? const Color(0x66FFFFFF) : const Color(0x55333B4F),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(20)),
          borderSide: BorderSide(
            color: isDark ? const Color(0x44FFFFFF) : const Color(0x33333B4F),
          ),
        ),
        filled: true,
        fillColor: isDark ? const Color(0x22FFFFFF) : const Color(0xAAFFFFFF),
        isDense: true,
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    );
  }
}

class LeccyHomePage extends ConsumerWidget {
  const LeccyHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appControllerProvider);
    if (app.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (app.errorMessage != null) {
      return Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Text(app.errorMessage!, textAlign: TextAlign.center),
          ),
        ),
      );
    }
    return Scaffold(
      body: Stack(
        children: [
          const _LiquidWallpaper(),
          SafeArea(
            child: Row(
              children: [
                SizedBox(width: 320, child: FolderLibrary(controller: app)),
                Expanded(child: LectureWorkspace(controller: app)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class FolderLibrary extends StatelessWidget {
  const FolderLibrary({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final folders = controller.visibleFolders;
    return _GlassPanel(
      fastMode: controller.fastMode,
      padding: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Leccy',
                      style: Theme.of(
                        context,
                      ).textTheme.headlineSmall?.copyWith(letterSpacing: 0),
                    ),
                    Text(
                      'Lecture workspace',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                IconButton.filledTonal(
                  tooltip: 'Settings',
                  onPressed: () => _showSettingsSheet(context, controller),
                  icon: const Icon(Icons.tune_rounded),
                ),
                if (!controller.showLeftPane)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: IconButton.filledTonal(
                      tooltip: 'Open left panel',
                      onPressed: () => controller.setLeftPaneVisible(true),
                      icon: const Icon(
                        Icons.keyboard_double_arrow_right_rounded,
                      ),
                    ),
                  ),
                if (!controller.showRightPane)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: IconButton.filledTonal(
                      tooltip: 'Open right panel',
                      onPressed: () => controller.setRightPaneVisible(true),
                      icon: const Icon(
                        Icons.keyboard_double_arrow_left_rounded,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'New folder',
                  onPressed: () => _showFolderDialog(context, controller),
                  icon: const Icon(Icons.create_new_folder_outlined),
                ),
              ],
            ),
            const SizedBox(height: 18),
            TextField(
              onChanged: controller.setSearchQuery,
              decoration: const InputDecoration(
                hintText: 'Search folders',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SegmentedButton<bool>(
                  style: SegmentedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  segments: const [
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.grid_view_rounded),
                    ),
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.view_list_rounded),
                    ),
                  ],
                  selected: {controller.isGrid},
                  onSelectionChanged: (value) =>
                      controller.setGrid(value.first),
                ),
                PopupMenuButton<FolderSortMode>(
                  tooltip: 'Sort folders',
                  initialValue: controller.sortMode,
                  onSelected: controller.setSortMode,
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: FolderSortMode.custom,
                      child: Text('Custom order'),
                    ),
                    PopupMenuItem(
                      value: FolderSortMode.name,
                      child: Text('Name'),
                    ),
                    PopupMenuItem(
                      value: FolderSortMode.progress,
                      child: Text('Progress'),
                    ),
                  ],
                  icon: const Icon(Icons.sort_rounded),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: folders.isEmpty
                  ? EmptyState(
                      icon: Icons.folder_open_rounded,
                      title: 'No folders yet',
                      actionLabel: 'Create folder',
                      onAction: () => _showFolderDialog(context, controller),
                    )
                  : controller.isGrid
                  ? GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            childAspectRatio: 0.95,
                          ),
                      itemCount: folders.length,
                      itemBuilder: (context, index) => FolderTile(
                        folder: folders[index],
                        isSelected:
                            folders[index].id == controller.selectedFolderId,
                        fileCount:
                            controller.fileCounts[folders[index].id] ?? 0,
                        progress:
                            controller.progressByFolder[folders[index].id] ?? 0,
                        onTap: () => controller.selectFolder(folders[index].id),
                        onEdit: () => _showFolderDialog(
                          context,
                          controller,
                          folder: folders[index],
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: folders.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 10),
                      itemBuilder: (context, index) => FolderTile(
                        folder: folders[index],
                        isSelected:
                            folders[index].id == controller.selectedFolderId,
                        fileCount:
                            controller.fileCounts[folders[index].id] ?? 0,
                        progress:
                            controller.progressByFolder[folders[index].id] ?? 0,
                        onTap: () => controller.selectFolder(folders[index].id),
                        onEdit: () => _showFolderDialog(
                          context,
                          controller,
                          folder: folders[index],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class FolderTile extends StatelessWidget {
  const FolderTile({
    super.key,
    required this.folder,
    required this.isSelected,
    required this.fileCount,
    required this.progress,
    required this.onTap,
    required this.onEdit,
  });

  final LectureFolder folder;
  final bool isSelected;
  final int fileCount;
  final int progress;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final color = Color(folder.colorValue);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      color: isSelected
          ? color.withValues(alpha: isDark ? 0.30 : 0.22)
          : (isDark ? const Color(0x332E3442) : const Color(0xEFFFFFFF)),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.78),
                          borderRadius: BorderRadius.circular(16),
                          image: folder.coverImagePath == null
                              ? null
                              : DecorationImage(
                                  image: coverImageProvider(
                                    folder.coverImagePath!,
                                  ),
                                  fit: BoxFit.cover,
                                ),
                        ),
                      ),
                    ),
                    Center(
                      child: Text(
                        folder.coverImagePath == null ? folder.badge : '',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: IconButton.filledTonal(
                        tooltip: 'Customize folder',
                        style: IconButton.styleFrom(
                          minimumSize: const Size(30, 30),
                          maximumSize: const Size(30, 30),
                          padding: EdgeInsets.zero,
                        ),
                        iconSize: 16,
                        onPressed: onEdit,
                        icon: const Icon(Icons.tune_rounded),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      folder.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  _ProgressChip(percent: progress),
                ],
              ),
              Text(
                '$fileCount files',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LectureWorkspace extends StatelessWidget {
  const LectureWorkspace({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final folder = controller.selectedFolder;
    if (folder == null) {
      return EmptyState(
        icon: Icons.dashboard_customize_outlined,
        title: 'Create a folder to start',
        actionLabel: 'New folder',
        onAction: () => _showFolderDialog(context, controller),
      );
    }
    return Row(
      children: [
        if (!controller.showLeftPane && !controller.editorFullscreen)
          IconButton.filledTonal(
            tooltip: 'Open left panel',
            onPressed: () => controller.setLeftPaneVisible(true),
            icon: const Icon(Icons.keyboard_double_arrow_right_rounded),
          ),
        if (controller.showLeftPane && !controller.editorFullscreen)
          SizedBox(
            width: controller.leftPaneWidth,
            child: FileListPanel(controller: controller, folder: folder),
          ),
        if (controller.showLeftPane && !controller.editorFullscreen)
          _PaneHandle(
            onDrag: controller.resizeLeftPane,
            tooltip: 'Resize left panel',
          ),
        Expanded(child: NoteEditor(controller: controller)),
        if (controller.showRightPane && !controller.editorFullscreen)
          _PaneHandle(
            onDrag: (delta) => controller.resizeRightPane(-delta),
            tooltip: 'Resize right panel',
          ),
        if (controller.showRightPane && !controller.editorFullscreen)
          SizedBox(
            width: controller.rightPaneWidth,
            child: ProgressPanel(controller: controller),
          ),
        if (!controller.showRightPane && !controller.editorFullscreen)
          IconButton.filledTonal(
            tooltip: 'Open right panel',
            onPressed: () => controller.setRightPaneVisible(true),
            icon: const Icon(Icons.keyboard_double_arrow_left_rounded),
          ),
      ],
    );
  }
}

class FileListPanel extends StatelessWidget {
  const FileListPanel({
    super.key,
    required this.controller,
    required this.folder,
  });

  final AppController controller;
  final LectureFolder folder;

  @override
  Widget build(BuildContext context) {
    final files = controller.files;
    return _GlassPanel(
      fastMode: controller.fastMode,
      padding: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    folder.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Close left panel',
                  onPressed: () => controller.setLeftPaneVisible(false),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 6),
            FolderProgressControl(
              progress: controller.selectedFolderProgress,
              onChanged: (value) =>
                  controller.setSelectedFolderProgress(value.round()),
            ),
            const SizedBox(height: 10),
            Text(
              'Lecture files',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: controller.createFile,
                    icon: const Icon(Icons.note_add_outlined),
                    label: const Text('New file'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Create progress set',
                  onPressed: controller.selectedFileIds.isEmpty
                      ? null
                      : controller.createStudySetFromSelection,
                  icon: const Icon(Icons.timeline_rounded),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: files.isEmpty
                  ? EmptyState(
                      icon: Icons.note_alt_outlined,
                      title: 'No files in this folder',
                      actionLabel: 'Create file',
                      onAction: controller.createFile,
                    )
                  : ListView.separated(
                      itemCount: files.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final file = files[index];
                        final selected = controller.selectedFileId == file.id;
                        return FileTile(
                          file: file,
                          isSelected: selected,
                          isChecked: controller.selectedFileIds.contains(
                            file.id,
                          ),
                          onTap: () => controller.selectFile(file.id),
                          onCheck: () =>
                              controller.toggleFileSelection(file.id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class FileTile extends StatelessWidget {
  const FileTile({
    super.key,
    required this.file,
    required this.isSelected,
    required this.isChecked,
    required this.onTap,
    required this.onCheck,
  });

  final LectureFile file;
  final bool isSelected;
  final bool isChecked;
  final VoidCallback onTap;
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      color: isSelected
          ? Theme.of(context).colorScheme.primaryContainer
          : (isDark ? const Color(0x292D3748) : Colors.white),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(value: isChecked, onChanged: (_) => onCheck()),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      file.description.isEmpty
                          ? 'No description'
                          : file.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: LinearProgressIndicator(
                        minHeight: 7,
                        value: file.progressPercent / 100,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text('${file.progressPercent}%'),
            ],
          ),
        ),
      ),
    );
  }
}

class NoteEditor extends StatefulWidget {
  const NoteEditor({super.key, required this.controller});

  final AppController controller;

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _quickNoteController = TextEditingController();
  quill.QuillController? _quillController;
  StreamSubscription<dynamic>? _documentSubscription;
  Timer? _saveTimer;
  int? _boundFileId;
  bool _isSaving = false;
  bool _hasPendingChanges = false;
  EditorSurface _surface = EditorSurface.note;

  @override
  void initState() {
    super.initState();
    _bindFile(widget.controller.selectedFile);
  }

  @override
  void didUpdateWidget(covariant NoteEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final file = widget.controller.selectedFile;
    if (file?.id != _boundFileId) {
      _bindFile(file);
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _documentSubscription?.cancel();
    _titleController.dispose();
    _descriptionController.dispose();
    _quickNoteController.dispose();
    _quillController?.dispose();
    super.dispose();
  }

  void _bindFile(LectureFile? file) {
    _saveTimer?.cancel();
    _documentSubscription?.cancel();
    _boundFileId = file?.id;
    _titleController.text = file?.title ?? '';
    _descriptionController.text = file?.description ?? '';
    _quickNoteController.text = file?.quickNote ?? '';
    _quillController?.dispose();
    final decoded =
        jsonDecode(widget.controller.documentJsonForFile(file)) as List;
    _quillController = quill.QuillController(
      document: quill.Document.fromJson(decoded.cast<Map<String, dynamic>>()),
      selection: const TextSelection.collapsed(offset: 0),
    );
    _documentSubscription = _quillController!.document.changes.listen(
      (_) => _scheduleSave(),
    );
    _hasPendingChanges = false;
    _surface = EditorSurface.note;
  }

  void _scheduleSave() {
    if (_boundFileId == null) {
      return;
    }
    setState(() => _hasPendingChanges = true);
    _saveTimer?.cancel();
    _saveTimer = Timer(
      Duration(milliseconds: widget.controller.fastMode ? 250 : 700),
      _saveNow,
    );
  }

  Future<void> _saveNow() async {
    final file = widget.controller.selectedFile;
    final quillController = _quillController;
    if (file == null || quillController == null || file.id != _boundFileId) {
      return;
    }
    setState(() => _isSaving = true);
    final contentJson = jsonEncode(quillController.document.toDelta().toJson());
    await widget.controller.updateFile(
      file.copyWith(
        title: _titleController.text.trim().isEmpty
            ? 'Untitled lecture'
            : _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        quickNote: _quickNoteController.text.trim(),
        contentJson: contentJson,
      ),
    );
    if (mounted) {
      setState(() {
        _isSaving = false;
        _hasPendingChanges = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.controller.selectedFile;
    final quillController = _quillController;
    if (file == null || quillController == null) {
      return EmptyState(
        icon: Icons.edit_note_rounded,
        title: 'Choose or create a lecture file',
        actionLabel: 'New file',
        onAction: widget.controller.createFile,
      );
    }
    return _GlassPanel(
      fastMode: widget.controller.fastMode,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      TextField(
                        controller: _titleController,
                        onChanged: (_) => _scheduleSave(),
                        style: Theme.of(context).textTheme.headlineSmall,
                        decoration: const InputDecoration(
                          labelText: 'Title',
                          prefixIcon: Icon(Icons.title_rounded),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _descriptionController,
                        onChanged: (_) => _scheduleSave(),
                        minLines: 1,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'File description',
                          prefixIcon: Icon(Icons.subject_rounded),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 220,
                  child: TextField(
                    controller: _quickNoteController,
                    onChanged: (_) => _scheduleSave(),
                    minLines: 3,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Doing now',
                      prefixIcon: Icon(Icons.sticky_note_2_outlined),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Expanded(
                  child: quill.QuillSimpleToolbar(
                    controller: quillController,
                    config: const quill.QuillSimpleToolbarConfig(
                      showFontFamily: false,
                      showFontSize: false,
                      showInlineCode: false,
                      showCodeBlock: false,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton.filledTonal(
                  tooltip: widget.controller.editorFullscreen
                      ? 'Exit fullscreen'
                      : 'Fullscreen editor',
                  onPressed: widget.controller.toggleEditorFullscreen,
                  icon: Icon(
                    widget.controller.editorFullscreen
                        ? Icons.fullscreen_exit_rounded
                        : Icons.fullscreen_rounded,
                  ),
                ),
                const SizedBox(width: 8),
                SegmentedButton<EditorSurface>(
                  style: SegmentedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  segments: const [
                    ButtonSegment(
                      value: EditorSurface.note,
                      icon: Icon(Icons.notes_rounded),
                    ),
                    ButtonSegment(
                      value: EditorSurface.table,
                      icon: Icon(Icons.table_chart_rounded),
                    ),
                    ButtonSegment(
                      value: EditorSurface.graph,
                      icon: Icon(Icons.bar_chart_rounded),
                    ),
                  ],
                  selected: {_surface},
                  onSelectionChanged: (value) {
                    setState(() => _surface = value.first);
                  },
                ),
                const SizedBox(width: 8),
                _SaveState(
                  isSaving: _isSaving,
                  hasPendingChanges: _hasPendingChanges,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: _surface == EditorSurface.note
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: quill.QuillEditor.basic(
                          controller: quillController,
                          config: const quill.QuillEditorConfig(
                            placeholder: 'Write the lecture note here...',
                            padding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    )
                  : _FileDataWorkspace(
                      fileId: file.id,
                      mode: _surface,
                      fastMode: widget.controller.fastMode,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

enum EditorSurface { note, table, graph }

class ProgressPanel extends StatelessWidget {
  const ProgressPanel({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final activeSet = controller.activeStudySet;
    return _GlassPanel(
      fastMode: controller.fastMode,
      padding: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Tools',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Close right panel',
                  onPressed: () => controller.setRightPaneVisible(false),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Study sets', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (controller.studySets.isEmpty)
              Text(
                'Select multiple files and press the progress button to link them.',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final set in controller.studySets)
                    ChoiceChip(
                      selected: set.id == controller.activeStudySetId,
                      label: Text(set.name),
                      onSelected: (_) => controller.selectStudySet(set.id),
                    ),
                ],
              ),
            const SizedBox(height: 18),
            Expanded(
              child: activeSet == null
                  ? const SizedBox.shrink()
                  : StudySetDetails(controller: controller, set: activeSet),
            ),
          ],
        ),
      ),
    );
  }
}

class StudySetDetails extends StatelessWidget {
  const StudySetDetails({
    super.key,
    required this.controller,
    required this.set,
  });

  final AppController controller;
  final StudySet set;

  @override
  Widget build(BuildContext context) {
    final itemFiles = {for (final file in controller.files) file.id: file};
    final total = controller.studySetProgress(set);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                set.name,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            _ProgressChip(percent: total),
          ],
        ),
        const SizedBox(height: 8),
        Text(DateFormat.yMMMd().format(set.createdAt)),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.separated(
            itemCount: controller.activeStudySetItems.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final item = controller.activeStudySetItems[index];
              final file = itemFiles[item.fileId];
              if (file == null) {
                return const SizedBox.shrink();
              }
              return Card(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          IconButton.filledTonal(
                            tooltip: 'Open file',
                            iconSize: 18,
                            onPressed: () => controller.selectFile(file.id),
                            icon: const Icon(Icons.arrow_forward_rounded),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              file.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text('${item.markerPercent}%'),
                        ],
                      ),
                      Slider(
                        value: item.markerPercent.toDouble(),
                        min: 0,
                        max: 100,
                        divisions: 20,
                        label: '${item.markerPercent}%',
                        onChanged: (value) => controller.updateStudySetMarker(
                          item,
                          value.round(),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class FolderProgressControl extends StatelessWidget {
  const FolderProgressControl({
    super.key,
    required this.progress,
    required this.onChanged,
  });

  final int progress;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).brightness == Brightness.dark
          ? const Color(0x262D3748)
          : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Folder progress',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Spacer(),
                _ProgressChip(percent: progress),
              ],
            ),
            Slider(
              value: progress.toDouble(),
              min: 0,
              max: 100,
              divisions: 20,
              label: '$progress%',
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.add_rounded),
            label: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

class _PaneHandle extends StatelessWidget {
  const _PaneHandle({required this.onDrag, required this.tooltip});

  final ValueChanged<double> onDrag;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
        child: Container(
          width: 12,
          margin: const EdgeInsets.symmetric(vertical: 20),
          alignment: Alignment.center,
          child: Container(
            width: 4,
            height: 72,
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
      ),
    );
  }
}

class _FileDataWorkspace extends StatefulWidget {
  const _FileDataWorkspace({
    required this.fileId,
    required this.fastMode,
    required this.mode,
  });

  final int fileId;
  final bool fastMode;
  final EditorSurface mode;

  @override
  State<_FileDataWorkspace> createState() => _FileDataWorkspaceState();
}

class _FileDataWorkspaceState extends State<_FileDataWorkspace> {
  static final Map<int, List<_DataPoint>> _store = {};
  List<_DataPoint> data = [];

  @override
  void initState() {
    super.initState();
    data = [
      ...(_store[widget.fileId] ?? [const _DataPoint('A', 20)]),
    ];
  }

  @override
  void didUpdateWidget(covariant _FileDataWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fileId != widget.fileId) {
      data = [
        ...(_store[widget.fileId] ?? [const _DataPoint('A', 20)]),
      ];
    }
  }

  void _persist() {
    _store[widget.fileId] = [...data];
  }

  @override
  Widget build(BuildContext context) {
    final maxY = math
        .max(
          10,
          data.fold<double>(0, (max, point) => math.max(max, point.value)),
        )
        .toDouble();
    return _GlassPanel(
      fastMode: widget.fastMode,
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Text(
                  widget.mode == EditorSurface.table
                      ? 'Table data'
                      : 'Graph from table',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Spacer(),
                if (widget.mode == EditorSurface.table)
                  IconButton(
                    tooltip: 'Add row',
                    onPressed: () {
                      setState(() {
                        data.add(_DataPoint('Item ${data.length + 1}', 0));
                        _persist();
                      });
                    },
                    icon: const Icon(Icons.add_rounded),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: widget.mode == EditorSurface.table
                  ? ListView.separated(
                      itemCount: data.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final point = data[index];
                        return Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                initialValue: point.label,
                                decoration: const InputDecoration(
                                  hintText: 'Label',
                                ),
                                onChanged: (value) {
                                  data[index] = _DataPoint(
                                    value.trim().isEmpty
                                        ? 'Item'
                                        : value.trim(),
                                    point.value,
                                  );
                                  _persist();
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 96,
                              child: TextFormField(
                                initialValue: point.value.toStringAsFixed(0),
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  hintText: 'Value',
                                ),
                                onChanged: (value) {
                                  final parsed = double.tryParse(value) ?? 0;
                                  data[index] = _DataPoint(
                                    point.label,
                                    parsed.clamp(0, 9999),
                                  );
                                  _persist();
                                  setState(() {});
                                },
                              ),
                            ),
                            IconButton(
                              tooltip: 'Delete row',
                              onPressed: data.length == 1
                                  ? null
                                  : () {
                                      setState(() {
                                        data.removeAt(index);
                                        _persist();
                                      });
                                    },
                              icon: const Icon(Icons.delete_outline_rounded),
                            ),
                          ],
                        );
                      },
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: SizedBox.expand(
                        child: CustomPaint(
                          painter: _BarGraphPainter(
                            points: data,
                            maxY: maxY,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DataPoint {
  const _DataPoint(this.label, this.value);

  final String label;
  final double value;
}

class _BarGraphPainter extends CustomPainter {
  const _BarGraphPainter({
    required this.points,
    required this.maxY,
    required this.color,
  });

  final List<_DataPoint> points;
  final double maxY;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final axis = Paint()
      ..color = color.withValues(alpha: 0.28)
      ..strokeWidth = 1.5;
    canvas.drawLine(
      Offset(0, size.height - 16),
      Offset(size.width, size.height - 16),
      axis,
    );
    if (points.isEmpty) {
      return;
    }
    final gap = 10.0;
    final barWidth = (size.width - gap * (points.length + 1)) / points.length;
    for (var i = 0; i < points.length; i++) {
      final h = (points[i].value / maxY) * (size.height - 40);
      final left = gap + i * (barWidth + gap);
      final top = size.height - 16 - h;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, barWidth, h),
        const Radius.circular(12),
      );
      canvas.drawRRect(rect, Paint()..color = color.withValues(alpha: 0.8));
    }
  }

  @override
  bool shouldRepaint(covariant _BarGraphPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.maxY != maxY ||
        oldDelegate.color != color;
  }
}

class _LiquidWallpaper extends StatelessWidget {
  const _LiquidWallpaper();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0xFF070A13), Color(0xFF101A2E), Color(0xFF202844)]
              : const [Color(0xFFE8EEFF), Color(0xFFD6ECFA), Color(0xFFF2EEFF)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: -120,
            top: -140,
            child: _Blob(
              size: 360,
              color: isDark ? const Color(0x3347B8FF) : const Color(0x66A0C8FF),
            ),
          ),
          Positioned(
            right: -80,
            top: 120,
            child: _Blob(
              size: 310,
              color: isDark ? const Color(0x3367E5D6) : const Color(0x66C2F5EA),
            ),
          ),
          Positioned(
            left: 220,
            bottom: -130,
            child: _Blob(
              size: 340,
              color: isDark ? const Color(0x335894FF) : const Color(0x66E2D4FF),
            ),
          ),
          Positioned(
            right: 120,
            bottom: 120,
            child: _Blob(
              size: 220,
              color: isDark ? const Color(0x224A6EFF) : const Color(0x55C9D9FF),
            ),
          ),
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withValues(alpha: 0.05)],
        ),
      ),
    );
  }
}

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({
    required this.child,
    required this.padding,
    this.fastMode = false,
  });

  final Widget child;
  final EdgeInsets padding;
  final bool fastMode;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: padding,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: fastMode ? 1 : 8,
            sigmaY: fastMode ? 1 : 8,
          ),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? const [Color(0x3AFFFFFF), Color(0x1AFFFFFF)]
                    : const [Color(0xE8FFFFFF), Color(0xAFFFFFFF)],
              ),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(
                color: isDark
                    ? const Color(0x44FFFFFF)
                    : const Color(0x66FFFFFF),
              ),
              boxShadow: [
                BoxShadow(
                  color: isDark
                      ? const Color(0x66000000)
                      : const Color(0x220E1933),
                  blurRadius: fastMode ? 4 : 16,
                  spreadRadius: -6,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

void _showSettingsSheet(BuildContext context, AppController controller) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return ListenableBuilder(
        listenable: controller,
        builder: (context, child) => _GlassPanel(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          fastMode: controller.fastMode,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.bolt_rounded),
                    const SizedBox(width: 10),
                    const Expanded(child: Text('Fast mode')),
                    Switch(
                      value: controller.fastMode,
                      onChanged: controller.setFastMode,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.dark_mode_outlined),
                    const SizedBox(width: 10),
                    const Expanded(child: Text('Theme')),
                    SegmentedButton<AppThemeMode>(
                      segments: const [
                        ButtonSegment(
                          value: AppThemeMode.light,
                          icon: Icon(Icons.light_mode_rounded),
                        ),
                        ButtonSegment(
                          value: AppThemeMode.dark,
                          icon: Icon(Icons.dark_mode_rounded),
                        ),
                      ],
                      selected: {controller.themeMode},
                      onSelectionChanged: (value) =>
                          controller.setThemeMode(value.first),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surface.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.link_rounded),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text('Want more customization? Go here'),
                      ),
                      TextButton(
                        onPressed: () async {
                          final uri = Uri.parse(
                            'https://github.com/Tawan4722/Leccy',
                          );
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        },
                        child: const Text('Open'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _AnyColorPicker extends StatefulWidget {
  const _AnyColorPicker({required this.value, required this.onChanged});

  final Color value;
  final ValueChanged<Color> onChanged;

  @override
  State<_AnyColorPicker> createState() => _AnyColorPickerState();
}

class _AnyColorPickerState extends State<_AnyColorPicker> {
  late HSVColor hsv;

  @override
  void initState() {
    super.initState();
    hsv = HSVColor.fromColor(widget.value);
  }

  @override
  void didUpdateWidget(covariant _AnyColorPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      hsv = HSVColor.fromColor(widget.value);
    }
  }

  void _update(HSVColor next) {
    setState(() => hsv = next);
    widget.onChanged(next.toColor());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          height: 40,
          decoration: BoxDecoration(
            color: hsv.toColor(),
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        Slider(
          value: hsv.hue,
          min: 0,
          max: 360,
          label: 'Hue',
          onChanged: (value) => _update(hsv.withHue(value)),
        ),
        Slider(
          value: hsv.saturation,
          min: 0,
          max: 1,
          label: 'Saturation',
          onChanged: (value) => _update(hsv.withSaturation(value)),
        ),
        Slider(
          value: hsv.value,
          min: 0,
          max: 1,
          label: 'Brightness',
          onChanged: (value) => _update(hsv.withValue(value)),
        ),
      ],
    );
  }
}

class _ProgressChip extends StatelessWidget {
  const _ProgressChip({required this.percent});

  final int percent;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Progress $percent%',
      child: Chip(
        visualDensity: VisualDensity.compact,
        label: Text('$percent%'),
        avatar: const Icon(Icons.flag_rounded, size: 16),
      ),
    );
  }
}

class _SaveState extends StatelessWidget {
  const _SaveState({required this.isSaving, required this.hasPendingChanges});

  final bool isSaving;
  final bool hasPendingChanges;

  @override
  Widget build(BuildContext context) {
    final text = isSaving
        ? 'Saving'
        : hasPendingChanges
        ? 'Unsaved'
        : 'Saved';
    final icon = isSaving
        ? Icons.sync_rounded
        : hasPendingChanges
        ? Icons.pending_outlined
        : Icons.check_circle_outline_rounded;
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(text),
      visualDensity: VisualDensity.compact,
    );
  }
}

Future<void> _showFolderDialog(
  BuildContext context,
  AppController controller, {
  LectureFolder? folder,
}) async {
  await showDialog<void>(
    context: context,
    builder: (context) => FolderDialog(controller: controller, folder: folder),
  );
}

class FolderDialog extends StatefulWidget {
  const FolderDialog({super.key, required this.controller, this.folder});

  final AppController controller;
  final LectureFolder? folder;

  @override
  State<FolderDialog> createState() => _FolderDialogState();
}

class _FolderDialogState extends State<FolderDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _badgeController;
  late int _colorValue;
  String? _coverPath;
  bool _isSavingImage = false;

  @override
  void initState() {
    super.initState();
    final folder = widget.folder;
    _nameController = TextEditingController(text: folder?.name ?? '');
    _badgeController = TextEditingController(text: folder?.badge ?? 'L');
    _colorValue = folder?.colorValue ?? const Color(0xFF2B8C7E).toARGB32();
    _coverPath = folder?.coverImagePath;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _badgeController.dispose();
    super.dispose();
  }

  Future<void> _pickCover() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null) {
      return;
    }
    setState(() => _isSavingImage = true);
    final path = await widget.controller.repository.saveCoverImage(
      bytes: bytes,
      extension: file.extension ?? 'png',
    );
    if (mounted) {
      setState(() {
        _coverPath = path;
        _isSavingImage = false;
      });
    }
  }

  Future<void> _save() async {
    final folder = widget.folder;
    if (folder == null) {
      await widget.controller.createFolder(
        name: _nameController.text,
        colorValue: _colorValue,
        badge: _badgeController.text,
        coverImagePath: _coverPath,
      );
    } else {
      await widget.controller.updateFolder(
        folder.copyWith(
          name: _nameController.text.trim().isEmpty
              ? 'New folder'
              : _nameController.text.trim(),
          colorValue: _colorValue,
          badge: _badgeController.text,
          coverImagePath: _coverPath,
          clearCoverImagePath: _coverPath == null,
        ),
      );
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = Color(_colorValue);
    return AlertDialog(
      title: Text(widget.folder == null ? 'New folder' : 'Customize folder'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Folder name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _badgeController,
              maxLength: 3,
              decoration: const InputDecoration(
                labelText: 'Emoji or letters',
                counterText: '',
              ),
            ),
            const SizedBox(height: 14),
            _AnyColorPicker(
              value: color,
              onChanged: (newColor) =>
                  setState(() => _colorValue = newColor.toARGB32()),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 86,
                  height: 58,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(18),
                    image: _coverPath == null
                        ? null
                        : DecorationImage(
                            image: coverImageProvider(_coverPath!),
                            fit: BoxFit.cover,
                          ),
                  ),
                  alignment: Alignment.center,
                  child: _coverPath == null
                      ? Text(
                          _badgeController.text.isEmpty
                              ? 'L'
                              : _badgeController.text,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                FilledButton.tonalIcon(
                  onPressed: _isSavingImage ? null : _pickCover,
                  icon: const Icon(Icons.image_outlined),
                  label: Text(_isSavingImage ? 'Saving' : 'Cover image'),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Remove cover image',
                  onPressed: _coverPath == null
                      ? null
                      : () => setState(() => _coverPath = null),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
