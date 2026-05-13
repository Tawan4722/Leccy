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
import 'package:intl/intl.dart' as intl;
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
    final accent = Color(app.accentColorValue);
    final base = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: isDark ? Brightness.dark : Brightness.light,
    ).copyWith(
      surface: isDark ? const Color(0xFF171A21) : const Color(0xFFF4F7FF),
      onSurface: isDark ? const Color(0xFFE8ECF5) : const Color(0xFF111318),
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
      theme: _buildTheme(base, false, app.fontPreset),
      darkTheme: _buildTheme(base, true, app.fontPreset),
      home: const LeccyHomePage(),
    );
  }

  ThemeData _buildTheme(
    ColorScheme scheme,
    bool isDark,
    AppFontPreset fontPreset,
  ) {
    final baseTextTheme = const TextTheme(
      headlineSmall: TextStyle(fontSize: 25, fontWeight: FontWeight.w600),
      titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      bodyMedium: TextStyle(fontSize: 13),
      bodySmall: TextStyle(fontSize: 12),
    );
    final textTheme = _textThemeForPreset(fontPreset, baseTextTheme);
    return ThemeData(
      useMaterial3: true,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
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

  TextTheme _textThemeForPreset(AppFontPreset preset, TextTheme base) {
    return switch (preset) {
      AppFontPreset.workSans => GoogleFonts.workSansTextTheme(base),
      AppFontPreset.nunito => GoogleFonts.nunitoSansTextTheme(base),
      AppFontPreset.sourceSerif => GoogleFonts.sourceSerif4TextTheme(base),
      AppFontPreset.lato => GoogleFonts.latoTextTheme(base),
    };
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

class _NoteEditorState extends State<NoteEditor>
    with WidgetsBindingObserver {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _quickNoteController = TextEditingController();
  final _searchController = TextEditingController();
  quill.QuillController? _quillController;
  StreamSubscription<dynamic>? _documentSubscription;
  Timer? _saveTimer;
  Timer? _autoSummaryTimer;
  int? _boundFileId;
  bool _isSaving = false;
  bool _hasPendingChanges = false;
  bool _isSummarizing = false;
  bool _showOutline = false;
  bool _showFlashAnswer = false;
  bool _showFormatToolbar = false;
  EditorSurface _surface = EditorSurface.note;
  List<int> _searchOffsets = const [];
  int _activeSearchMatch = 0;
  int _flashcardIndex = 0;
  final Set<int> _collapsedSectionOffsets = {};
  final List<_FlashCardItem> _flashcards = [];

  static const List<Color> _markerColors = [
    Color(0xFFFFF59D),
    Color(0xFFC8E6C9),
    Color(0xFFF8BBD0),
    Color(0xFFBBDEFB),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bindFile(widget.controller.selectedFile);
  }

  @override
  void didUpdateWidget(covariant NoteEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final file = widget.controller.selectedFile;
    if (file?.id != _boundFileId) {
      unawaited(_saveNow(silent: true));
      _bindFile(file);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_saveNow(silent: true));
    _saveTimer?.cancel();
    _autoSummaryTimer?.cancel();
    _documentSubscription?.cancel();
    _titleController.dispose();
    _descriptionController.dispose();
    _quickNoteController.dispose();
    _searchController.dispose();
    _quillController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_saveNow(silent: true));
    }
  }

  void _bindFile(LectureFile? file) {
    _saveTimer?.cancel();
    _autoSummaryTimer?.cancel();
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
      (_) {
        _scheduleSave();
        if (_searchController.text.trim().isNotEmpty) {
          _refreshSearch();
        }
      },
    );
    _hasPendingChanges = false;
    _surface = EditorSurface.note;
    _showOutline = false;
    _showFormatToolbar = false;
    _searchOffsets = const [];
    _activeSearchMatch = 0;
    _searchController.clear();
    _collapsedSectionOffsets.clear();
    _flashcards.clear();
    _flashcardIndex = 0;
    _showFlashAnswer = false;
  }

  void _scheduleSave() {
    if (_boundFileId == null) {
      return;
    }
    setState(() => _hasPendingChanges = true);
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 3), _saveNow);
    _scheduleAutoSummary();
  }

  void _scheduleAutoSummary() {
    _autoSummaryTimer?.cancel();
    _autoSummaryTimer = Timer(
      Duration(milliseconds: widget.controller.fastMode ? 1200 : 1800),
      _runAutoSummary,
    );
  }

  String _currentNotePlainText() {
    final quillController = _quillController;
    if (quillController == null) {
      return '';
    }
    final contentJson = jsonEncode(quillController.document.toDelta().toJson());
    return widget.controller.notePlainTextFromContent(contentJson);
  }

  void _applyHighlight(Color color) {
    final quillController = _quillController;
    if (quillController == null) {
      return;
    }
    final selection = quillController.selection;
    if (selection.start < 0 || selection.end <= selection.start) {
      return;
    }
    final rgb = color.toARGB32() & 0x00FFFFFF;
    final hex = '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
    quillController.formatSelection(quill.Attribute.fromKeyValue('background', hex));
  }

  void _clearHighlight() {
    final quillController = _quillController;
    if (quillController == null) {
      return;
    }
    final selection = quillController.selection;
    if (selection.start < 0 || selection.end <= selection.start) {
      return;
    }
    quillController.formatSelection(
      quill.Attribute.clone(quill.Attribute.background, null),
    );
  }

  void _applyHeading(int? level) {
    final quillController = _quillController;
    if (quillController == null) {
      return;
    }
    if (level == null) {
      quillController.formatSelection(
        quill.Attribute.clone(quill.Attribute.header, null),
      );
      return;
    }
    final attribute = switch (level) {
      1 => quill.Attribute.h1,
      2 => quill.Attribute.h2,
      _ => quill.Attribute.h3,
    };
    quillController.formatSelection(attribute);
  }

  void _refreshSearch() {
    final quillController = _quillController;
    final query = _searchController.text.trim();
    if (quillController == null || query.isEmpty) {
      setState(() {
        _searchOffsets = const [];
        _activeSearchMatch = 0;
      });
      return;
    }
    final offsets = quillController.document.search(query);
    setState(() {
      _searchOffsets = offsets;
      if (_activeSearchMatch >= offsets.length) {
        _activeSearchMatch = 0;
      }
    });
  }

  void _jumpToSearchMatch(int index) {
    final quillController = _quillController;
    final query = _searchController.text.trim();
    if (quillController == null ||
        query.isEmpty ||
        _searchOffsets.isEmpty ||
        index < 0 ||
        index >= _searchOffsets.length) {
      return;
    }
    final offset = _searchOffsets[index];
    quillController.updateSelection(
      TextSelection(baseOffset: offset, extentOffset: offset + query.length),
      quill.ChangeSource.local,
    );
    setState(() => _activeSearchMatch = index);
  }

  void _jumpToNextSearchMatch() {
    if (_searchOffsets.isEmpty) {
      return;
    }
    final next = (_activeSearchMatch + 1) % _searchOffsets.length;
    _jumpToSearchMatch(next);
  }

  void _jumpToPreviousSearchMatch() {
    if (_searchOffsets.isEmpty) {
      return;
    }
    final previous = (_activeSearchMatch - 1 + _searchOffsets.length) %
        _searchOffsets.length;
    _jumpToSearchMatch(previous);
  }

  void _jumpToOffset(int offset) {
    final quillController = _quillController;
    if (quillController == null) {
      return;
    }
    final safe = offset.clamp(0, quillController.document.length - 1);
    quillController.updateSelection(
      TextSelection.collapsed(offset: safe),
      quill.ChangeSource.local,
    );
  }

  List<_OutlineSection> _buildOutlineSections(
    quill.QuillController quillController,
  ) {
    final sections = <_OutlineSection>[];
    _OutlineSection? current;

    void ensureFallback() {
      current ??= _OutlineSection(
        title: 'General notes',
        level: 0,
        offset: 0,
        bodyLines: [],
      );
      if (!sections.contains(current)) {
        sections.add(current!);
      }
    }

    void addLine(quill.Line line) {
      final full = line.toPlainText();
      final text = full.endsWith('\n') ? full.substring(0, full.length - 1) : full;
      final trimmed = text.trim();
      final header = line.style.attributes[quill.Attribute.header.key];
      final level = header?.value is int ? header!.value as int : 0;
      if (level > 0 && trimmed.isNotEmpty) {
        current = _OutlineSection(
          title: trimmed,
          level: level,
          offset: line.documentOffset,
          bodyLines: [],
        );
        sections.add(current!);
        return;
      }
      if (trimmed.isEmpty) {
        return;
      }
      ensureFallback();
      current!.bodyLines.add(trimmed);
    }

    void walk(quill.Node node) {
      if (node is quill.Line) {
        addLine(node);
        return;
      }
      if (node is quill.Block) {
        for (final child in node.children.whereType<quill.Node>()) {
          walk(child);
        }
      }
    }

    for (final node in quillController.document.root.children.whereType<quill.Node>()) {
      walk(node);
    }
    if (sections.isEmpty) {
      return const [
        _OutlineSection(
          title: 'General notes',
          level: 0,
          offset: 0,
          bodyLines: <String>[],
        ),
      ];
    }
    return sections;
  }

  void _generateFlashcards() {
    if (!widget.controller.hasApiKey) {
      return;
    }
    final text = _currentNotePlainText().trim();
    if (text.isEmpty) {
      setState(() {
        _flashcards
          ..clear()
          ..add(
            const _FlashCardItem(
              question: 'No notes yet',
              answer: 'Write lecture notes first, then generate flashcards.',
            ),
          );
        _flashcardIndex = 0;
        _showFlashAnswer = false;
      });
      return;
    }

    final segments = text
        .split(RegExp(r'[\n\.!?]+'))
        .map((line) => line.trim())
        .where((line) => line.length >= 18)
        .take(20)
        .toList();

    final cards = <_FlashCardItem>[];
    for (final segment in segments.take(12)) {
      final words = segment.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      if (words.length < 3) {
        continue;
      }
      final topic = words.take(6).join(' ');
      cards.add(
        _FlashCardItem(
          question: 'What should you remember about "$topic"...?',
          answer: segment,
        ),
      );
    }

    if (cards.isEmpty) {
      cards.add(
        const _FlashCardItem(
          question: 'Not enough content',
          answer: 'Add a bit more detail in your note to build flashcards.',
        ),
      );
    }

    setState(() {
      _flashcards
        ..clear()
        ..addAll(cards);
      _flashcardIndex = 0;
      _showFlashAnswer = false;
    });
  }

  void _nextFlashcard() {
    if (_flashcards.isEmpty) {
      return;
    }
    setState(() {
      _flashcardIndex = (_flashcardIndex + 1) % _flashcards.length;
      _showFlashAnswer = false;
    });
  }

  void _previousFlashcard() {
    if (_flashcards.isEmpty) {
      return;
    }
    setState(() {
      _flashcardIndex = (_flashcardIndex - 1 + _flashcards.length) % _flashcards.length;
      _showFlashAnswer = false;
    });
  }

  Future<void> _runAutoSummary() async {
    final file = widget.controller.selectedFile;
    if (file == null || !file.autoSummaryEnabled || _isSummarizing) {
      return;
    }
    setState(() => _isSummarizing = true);
    await widget.controller.maybeAutoSummarizeSelectedFile(
      noteText: _currentNotePlainText(),
    );
    if (mounted) {
      final updated = widget.controller.selectedFile;
      if (updated != null && updated.id == _boundFileId) {
        _descriptionController.text = updated.description;
      }
      setState(() => _isSummarizing = false);
    }
  }

  Future<void> _generateSummaryNow() async {
    if (_isSummarizing) {
      return;
    }
    setState(() => _isSummarizing = true);
    await widget.controller.generateSummaryForSelectedFile(
      noteText: _currentNotePlainText(),
      manual: true,
    );
    if (mounted) {
      final updated = widget.controller.selectedFile;
      if (updated != null && updated.id == _boundFileId) {
        _descriptionController.text = updated.description;
      }
      setState(() => _isSummarizing = false);
    }
  }

  Future<void> _saveNow({bool silent = false}) async {
    _saveTimer?.cancel();
    final boundFileId = _boundFileId;
    final quillController = _quillController;
    if (boundFileId == null || quillController == null) {
      return;
    }

    final selected = widget.controller.selectedFile;
    final file = selected?.id == boundFileId
        ? selected
        : widget.controller.files
              .where((entry) => entry.id == boundFileId)
              .firstOrNull;
    if (file == null) {
      return;
    }

    if (!silent && mounted) {
      setState(() => _isSaving = true);
    }
    final contentJson = jsonEncode(quillController.document.toDelta().toJson());
    await widget.controller.saveFileDraft(
      file.copyWith(
        title: _titleController.text.trim().isEmpty
            ? 'Untitled lecture'
            : _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        quickNote: _quickNoteController.text.trim(),
        contentJson: contentJson,
      ),
    );

    if (!silent && mounted) {
      setState(() {
        _isSaving = false;
        _hasPendingChanges = false;
      });
      return;
    }

    _isSaving = false;
    _hasPendingChanges = false;
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
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
            child: Column(
              children: [
                TextField(
                  controller: _titleController,
                  onChanged: (_) => _scheduleSave(),
                  style: Theme.of(context).textTheme.titleLarge,
                  decoration: const InputDecoration(
                    hintText: 'Untitled lecture',
                    prefixIcon: Icon(Icons.title_rounded),
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _SaveState(
                        isSaving: _isSaving,
                        hasPendingChanges: _hasPendingChanges,
                      ),
                      if (_surface == EditorSurface.note) ...[
                        const SizedBox(width: 6),
                        IconButton.filledTonal(
                          tooltip: _showOutline
                              ? 'Hide accordion'
                              : 'Show accordion',
                          onPressed: () =>
                              setState(() => _showOutline = !_showOutline),
                          icon: Icon(
                            _showOutline
                                ? Icons.view_agenda_rounded
                                : Icons.view_agenda_outlined,
                          ),
                        ),
                      ],
                      const SizedBox(width: 6),
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
                          ButtonSegment(
                            value: EditorSurface.flashcards,
                            icon: Icon(Icons.style_rounded),
                          ),
                        ],
                        selected: {_surface},
                        onSelectionChanged: (value) {
                          setState(() => _surface = value.first);
                        },
                      ),
                    ],
                  ),
                ),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(top: 4, bottom: 4),
                  leading: const Icon(Icons.subject_rounded),
                  title: const Text('Details'),
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _descriptionController,
                            onChanged: (_) async {
                              final file = widget.controller.selectedFile;
                              if (file != null && file.autoSummaryEnabled) {
                                await widget.controller
                                    .setAutoSummaryEnabledForSelectedFile(false);
                              }
                              _scheduleSave();
                            },
                            minLines: 2,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              labelText: 'Description',
                              prefixIcon: Icon(Icons.notes_outlined),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 220,
                          child: TextField(
                            controller: _quickNoteController,
                            onChanged: (_) => _scheduleSave(),
                            minLines: 2,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              labelText: 'Doing now',
                              prefixIcon: Icon(Icons.sticky_note_2_outlined),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 190,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              FilledButton.tonalIcon(
                                onPressed: _isSummarizing
                                    ? null
                                    : _generateSummaryNow,
                                icon:
                                    const Icon(Icons.auto_awesome_rounded),
                                label: Text(
                                  _isSummarizing
                                      ? 'Summarizing'
                                      : 'Summary',
                                ),
                              ),
                              Row(
                                children: [
                                  const Expanded(child: Text('Auto summary')),
                                  Switch(
                                    value: file.autoSummaryEnabled,
                                    onChanged: (value) {
                                      widget.controller
                                          .setAutoSummaryEnabledForSelectedFile(
                                        value,
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_surface == EditorSurface.note)
            _NoteActionBar(
              controller: quillController,
              searchController: _searchController,
              markerColors: _markerColors,
              showFormatToolbar: _showFormatToolbar,
              searchLabel: _searchController.text.trim().isEmpty
                  ? ''
                  : '${_searchOffsets.isEmpty ? 0 : _activeSearchMatch + 1}/${_searchOffsets.length}',
              onHeadingSelected: _applyHeading,
              onHighlight: _applyHighlight,
              onClearHighlight: _clearHighlight,
              onToggleFormatToolbar: () => setState(
                () => _showFormatToolbar = !_showFormatToolbar,
              ),
              onSearchChanged: (_) => _refreshSearch(),
              onSearchSubmitted: (_) => _jumpToSearchMatch(0),
              onPreviousSearch: _searchOffsets.isEmpty
                  ? null
                  : _jumpToPreviousSearchMatch,
              onNextSearch: _searchOffsets.isEmpty
                  ? null
                  : _jumpToNextSearchMatch,
            ),
          const Divider(height: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: _surface == EditorSurface.note
                  ? Row(
                      children: [
                        Expanded(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Color(widget.controller.editorPaperColorValue),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Theme.of(context).colorScheme.outlineVariant,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(22),
                              child: quill.QuillEditor.basic(
                                controller: quillController,
                                config: const quill.QuillEditorConfig(
                                  placeholder: 'Write the lecture note here...',
                                  padding: EdgeInsets.zero,
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (_showOutline) const SizedBox(width: 12),
                        if (_showOutline)
                          SizedBox(
                            width: 280,
                            child: _DocumentOutlinePanel(
                              sections: _buildOutlineSections(quillController),
                              collapsedOffsets: _collapsedSectionOffsets,
                              onToggleSection: (offset, collapsed) {
                                setState(() {
                                  if (collapsed) {
                                    _collapsedSectionOffsets.add(offset);
                                  } else {
                                    _collapsedSectionOffsets.remove(offset);
                                  }
                                });
                              },
                              onJump: _jumpToOffset,
                            ),
                          ),
                      ],
                    )
                  : _surface == EditorSurface.flashcards
                  ? _FlashcardWorkspace(
                      hasApiKey: widget.controller.hasApiKey,
                      apiKey: widget.controller.apiKey,
                      cards: _flashcards,
                      index: _flashcardIndex,
                      showAnswer: _showFlashAnswer,
                      onApiKeyChanged: widget.controller.setApiKey,
                      onGenerate: _generateFlashcards,
                      onToggleAnswer: () =>
                          setState(() => _showFlashAnswer = !_showFlashAnswer),
                      onPrevious: _previousFlashcard,
                      onNext: _nextFlashcard,
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

class _NoteActionBar extends StatelessWidget {
  const _NoteActionBar({
    required this.controller,
    required this.searchController,
    required this.markerColors,
    required this.showFormatToolbar,
    required this.searchLabel,
    required this.onHeadingSelected,
    required this.onHighlight,
    required this.onClearHighlight,
    required this.onToggleFormatToolbar,
    required this.onSearchChanged,
    required this.onSearchSubmitted,
    required this.onPreviousSearch,
    required this.onNextSearch,
  });

  final quill.QuillController controller;
  final TextEditingController searchController;
  final List<Color> markerColors;
  final bool showFormatToolbar;
  final String searchLabel;
  final ValueChanged<int?> onHeadingSelected;
  final ValueChanged<Color> onHighlight;
  final VoidCallback onClearHighlight;
  final VoidCallback onToggleFormatToolbar;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onSearchSubmitted;
  final VoidCallback? onPreviousSearch;
  final VoidCallback? onNextSearch;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.58),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    SegmentedButton<int>(
                    style: SegmentedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    segments: const [
                      ButtonSegment(value: 1, label: Text('H1')),
                      ButtonSegment(value: 2, label: Text('H2')),
                      ButtonSegment(value: 0, label: Text('Body')),
                    ],
                    selected: const <int>{},
                    emptySelectionAllowed: true,
                    onSelectionChanged: (value) {
                      if (value.isEmpty) {
                        return;
                      }
                      final picked = value.first;
                      onHeadingSelected(picked == 0 ? null : picked);
                    },
                  ),
                    const SizedBox(width: 10),
                    for (var i = 0; i < markerColors.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: IconButton.filledTonal(
                          tooltip: 'Marker ${i + 1}',
                          onPressed: () => onHighlight(markerColors[i]),
                          style: IconButton.styleFrom(
                            backgroundColor:
                                markerColors[i].withValues(alpha: 0.55),
                            minimumSize: const Size(36, 36),
                          ),
                          icon: const Icon(Icons.draw_rounded, size: 18),
                        ),
                      ),
                    IconButton(
                      tooltip: 'Clear marker',
                      onPressed: onClearHighlight,
                      icon: const Icon(Icons.format_color_reset_rounded),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: showFormatToolbar
                          ? 'Hide formatting'
                          : 'Show formatting',
                      onPressed: onToggleFormatToolbar,
                      icon: Icon(
                        showFormatToolbar
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.tune_rounded,
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 260,
                      child: TextField(
                        controller: searchController,
                        onChanged: onSearchChanged,
                        onSubmitted: onSearchSubmitted,
                        decoration: InputDecoration(
                          hintText: 'Search',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixText: searchLabel,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Previous match',
                      onPressed: onPreviousSearch,
                      icon: const Icon(Icons.keyboard_arrow_up_rounded),
                    ),
                    IconButton(
                      tooltip: 'Next match',
                      onPressed: onNextSearch,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    ),
                  ],
                ),
              ),
              if (showFormatToolbar) ...[
                const SizedBox(height: 8),
                quill.QuillSimpleToolbar(
                  controller: controller,
                  config: const quill.QuillSimpleToolbarConfig(
                    showFontFamily: true,
                    showFontSize: true,
                    showInlineCode: false,
                    showCodeBlock: false,
                    showSearchButton: true,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _OutlineSection {
  const _OutlineSection({
    required this.title,
    required this.level,
    required this.offset,
    required this.bodyLines,
  });

  final String title;
  final int level;
  final int offset;
  final List<String> bodyLines;
}

class _DocumentOutlinePanel extends StatelessWidget {
  const _DocumentOutlinePanel({
    required this.sections,
    required this.collapsedOffsets,
    required this.onToggleSection,
    required this.onJump,
  });

  final List<_OutlineSection> sections;
  final Set<int> collapsedOffsets;
  final void Function(int offset, bool collapsed) onToggleSection;
  final ValueChanged<int> onJump;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: ListView(
          children: [
            Text(
              'Accordion',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            for (final section in sections)
              Card(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: ExpansionTile(
                  initiallyExpanded: !collapsedOffsets.contains(section.offset),
                  onExpansionChanged: (expanded) =>
                      onToggleSection(section.offset, !expanded),
                  title: Text(
                    section.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    section.level == 0
                        ? 'Text block'
                        : section.level == 1
                        ? 'Heading'
                        : 'Sub heading',
                  ),
                  trailing: IconButton(
                    tooltip: 'Jump to section',
                    onPressed: () => onJump(section.offset),
                    icon: const Icon(Icons.arrow_forward_rounded),
                  ),
                  children: [
                    if (section.bodyLines.isEmpty)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text('No text under this heading yet.'),
                        ),
                      ),
                    if (section.bodyLines.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            section.bodyLines.take(3).join('\n'),
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FlashCardItem {
  const _FlashCardItem({required this.question, required this.answer});

  final String question;
  final String answer;
}

class _FlashcardWorkspace extends StatelessWidget {
  const _FlashcardWorkspace({
    required this.hasApiKey,
    required this.apiKey,
    required this.cards,
    required this.index,
    required this.showAnswer,
    required this.onApiKeyChanged,
    required this.onGenerate,
    required this.onToggleAnswer,
    required this.onPrevious,
    required this.onNext,
  });

  final bool hasApiKey;
  final String apiKey;
  final List<_FlashCardItem> cards;
  final int index;
  final bool showAnswer;
  final ValueChanged<String> onApiKeyChanged;
  final VoidCallback onGenerate;
  final VoidCallback onToggleAnswer;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.style_rounded),
                const SizedBox(width: 8),
                Text('Flashcards', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (cards.isNotEmpty)
                  Chip(
                    label: Text('${index + 1}/${cards.length}'),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (!hasApiKey) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Flashcards are locked. Enter API key to enable this tab.',
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                initialValue: apiKey,
                obscureText: true,
                onChanged: onApiKeyChanged,
                decoration: const InputDecoration(
                  labelText: 'API key',
                  prefixIcon: Icon(Icons.key_rounded),
                ),
              ),
              const Spacer(),
            ] else ...[
              TextFormField(
                initialValue: apiKey,
                obscureText: true,
                onChanged: onApiKeyChanged,
                decoration: const InputDecoration(
                  labelText: 'API key',
                  prefixIcon: Icon(Icons.key_rounded),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: onGenerate,
                    icon: const Icon(Icons.auto_awesome_rounded),
                    label: const Text('Generate cards'),
                  ),
                  OutlinedButton.icon(
                    onPressed: cards.isEmpty ? null : onPrevious,
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: const Text('Previous'),
                  ),
                  OutlinedButton.icon(
                    onPressed: cards.isEmpty ? null : onNext,
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: const Text('Next'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: cards.isEmpty
                    ? const Center(
                        child: Text('Generate flashcards from your note content.'),
                      )
                    : InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: onToggleAnswer,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            color: Theme.of(context).colorScheme.surfaceContainer,
                            border: Border.all(
                              color: Theme.of(context).colorScheme.outlineVariant,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                showAnswer ? 'Answer' : 'Question',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                showAnswer
                                    ? cards[index].answer
                                    : cards[index].question,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const Spacer(),
                              Text(
                                'Tap card to flip',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum EditorSurface { note, table, graph, flashcards }

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
        Text(intl.DateFormat.yMMMd().format(set.createdAt)),
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
  static final Map<int, _GraphType> _graphTypeStore = {};
  List<_DataPoint> data = [];
  _GraphType graphType = _GraphType.bar;

  @override
  void initState() {
    super.initState();
    data = [
      ...(_store[widget.fileId] ?? [const _DataPoint('A', 20)]),
    ];
    graphType = _graphTypeStore[widget.fileId] ?? _GraphType.bar;
  }

  @override
  void didUpdateWidget(covariant _FileDataWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fileId != widget.fileId) {
      data = [
        ...(_store[widget.fileId] ?? [const _DataPoint('A', 20)]),
      ];
      graphType = _graphTypeStore[widget.fileId] ?? _GraphType.bar;
    }
  }

  void _persist() {
    _store[widget.fileId] = [...data];
    _graphTypeStore[widget.fileId] = graphType;
  }

  @override
  Widget build(BuildContext context) {
    final cleanData = data.where((point) => point.value > 0).toList();
    final maxY = math
        .max(
          10,
          cleanData.fold<double>(0, (max, point) => math.max(max, point.value)),
        )
        .toDouble();
    final total = cleanData.fold<double>(0, (sum, point) => sum + point.value);
    final avg = cleanData.isEmpty ? 0.0 : (total / cleanData.length).toDouble();
    final max = cleanData.isEmpty
        ? 0.0
        : cleanData.fold<double>(0, (m, point) => math.max(m, point.value));
    final min = cleanData.isEmpty
        ? 0.0
        : cleanData.fold<double>(
            cleanData.first.value,
            (m, point) => math.min(m, point.value),
          );
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
                      : 'Graph from file data',
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
                if (widget.mode == EditorSurface.graph)
                  SegmentedButton<_GraphType>(
                    style: SegmentedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    segments: const [
                      ButtonSegment(
                        value: _GraphType.bar,
                        icon: Icon(Icons.bar_chart_rounded),
                      ),
                      ButtonSegment(
                        value: _GraphType.line,
                        icon: Icon(Icons.show_chart_rounded),
                      ),
                      ButtonSegment(
                        value: _GraphType.pie,
                        icon: Icon(Icons.pie_chart_rounded),
                      ),
                    ],
                    selected: {graphType},
                    onSelectionChanged: (value) {
                      setState(() {
                        graphType = value.first;
                        _persist();
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: widget.mode == EditorSurface.table
                  ? ListView.separated(
                      itemCount: data.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
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
                      child: Column(
                        children: [
                          Row(
                            children: [
                              _MetricChip(label: 'Total', value: total),
                              const SizedBox(width: 8),
                              _MetricChip(label: 'Avg', value: avg),
                              const SizedBox(width: 8),
                              _MetricChip(label: 'Max', value: max),
                              const SizedBox(width: 8),
                              _MetricChip(label: 'Min', value: min),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Expanded(
                            child: SizedBox.expand(
                              child: CustomPaint(
                                painter: _GraphPainter(
                                  points: cleanData,
                                  maxY: maxY,
                                  color: Theme.of(context).colorScheme.primary,
                                  type: graphType,
                                  textColor: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                ),
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
  }
}

class _DataPoint {
  const _DataPoint(this.label, this.value);

  final String label;
  final double value;
}

enum _GraphType { bar, line, pie }

class _GraphPainter extends CustomPainter {
  const _GraphPainter({
    required this.points,
    required this.maxY,
    required this.color,
    required this.type,
    required this.textColor,
  });

  final List<_DataPoint> points;
  final double maxY;
  final Color color;
  final _GraphType type;
  final Color textColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) {
      final p = TextPainter(
        text: TextSpan(
          text: 'No data yet. Add values in Table mode.',
          style: TextStyle(
            color: textColor.withValues(alpha: 0.7),
            fontSize: 12,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width);
      p.paint(
        canvas,
        Offset((size.width - p.width) / 2, (size.height - p.height) / 2),
      );
      return;
    }
    if (type == _GraphType.pie) {
      _paintPie(canvas, size);
      return;
    }
    _paintCartesian(canvas, size);
  }

  void _paintCartesian(Canvas canvas, Size size) {
    final chartBottom = size.height - 28;
    final leftPad = 32.0;
    final rightPad = 8.0;
    final topPad = 10.0;
    final chartWidth = size.width - leftPad - rightPad;
    final chartHeight = chartBottom - topPad;
    final grid = Paint()
      ..color = color.withValues(alpha: 0.16)
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = topPad + (chartHeight / 4) * i;
      canvas.drawLine(
        Offset(leftPad, y),
        Offset(leftPad + chartWidth, y),
        grid,
      );
    }
    final axis = Paint()
      ..color = color.withValues(alpha: 0.28)
      ..strokeWidth = 1.6;
    canvas.drawLine(
      Offset(leftPad, chartBottom),
      Offset(leftPad + chartWidth, chartBottom),
      axis,
    );
    canvas.drawLine(
      Offset(leftPad, topPad),
      Offset(leftPad, chartBottom),
      axis,
    );

    final gap = 10.0;
    final barWidth = (chartWidth - gap * (points.length + 1)) / points.length;
    final path = Path();
    Offset? previous;
    for (var i = 0; i < points.length; i++) {
      final h = (points[i].value / maxY) * (chartHeight - 4);
      final left = leftPad + gap + i * (barWidth + gap);
      final top = chartBottom - h;
      final centerX = left + barWidth / 2;

      if (type == _GraphType.bar) {
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(left, top, barWidth, h),
          const Radius.circular(10),
        );
        canvas.drawRRect(rect, Paint()..color = color.withValues(alpha: 0.82));
      } else {
        final point = Offset(centerX, top);
        if (previous == null) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
        previous = point;
      }

      final labelPainter = TextPainter(
        text: TextSpan(
          text: points[i].label,
          style: TextStyle(
            color: textColor.withValues(alpha: 0.82),
            fontSize: 10,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: barWidth + gap);
      labelPainter.paint(
        canvas,
        Offset(centerX - labelPainter.width / 2, chartBottom + 6),
      );
    }

    if (type == _GraphType.line) {
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6,
      );
      for (var i = 0; i < points.length; i++) {
        final h = (points[i].value / maxY) * (chartHeight - 4);
        final x = leftPad + gap + i * (barWidth + gap) + barWidth / 2;
        final y = chartBottom - h;
        canvas.drawCircle(Offset(x, y), 3.5, Paint()..color = color);
      }
    }
  }

  void _paintPie(Canvas canvas, Size size) {
    final total = points.fold<double>(0, (sum, point) => sum + point.value);
    if (total <= 0) {
      return;
    }
    final center = Offset(size.width * 0.35, size.height * 0.5);
    final radius = math.min(size.width, size.height) * 0.28;
    final rect = Rect.fromCircle(center: center, radius: radius);
    var start = -math.pi / 2;
    for (var i = 0; i < points.length; i++) {
      final sweep = (points[i].value / total) * math.pi * 2;
      canvas.drawArc(rect, start, sweep, true, Paint()..color = _palette(i));
      start += sweep;
    }

    var legendY = size.height * 0.2;
    for (var i = 0; i < points.length; i++) {
      final pct = (points[i].value / total) * 100;
      final paint = Paint()..color = _palette(i);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(size.width * 0.64, legendY, 10, 10),
          const Radius.circular(3),
        ),
        paint,
      );
      final legend = TextPainter(
        text: TextSpan(
          text: '${points[i].label}  ${pct.toStringAsFixed(1)}%',
          style: TextStyle(
            color: textColor.withValues(alpha: 0.88),
            fontSize: 11,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width * 0.32);
      legend.paint(canvas, Offset(size.width * 0.68, legendY - 2));
      legendY += 16;
    }
  }

  Color _palette(int i) {
    const colors = [
      Color(0xFF4F87FF),
      Color(0xFF2DB3A3),
      Color(0xFFFFA940),
      Color(0xFFEF6A89),
      Color(0xFF8B7CFA),
      Color(0xFF59B76F),
      Color(0xFFE16666),
    ];
    return colors[i % colors.length];
  }

  @override
  bool shouldRepaint(covariant _GraphPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.maxY != maxY ||
        oldDelegate.color != color ||
        oldDelegate.type != type ||
        oldDelegate.textColor != textColor;
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$label: ${value.toStringAsFixed(1)}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
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

String _fontPresetLabel(AppFontPreset preset) {
  return switch (preset) {
    AppFontPreset.workSans => 'Work Sans',
    AppFontPreset.nunito => 'Nunito Sans',
    AppFontPreset.sourceSerif => 'Source Serif 4',
    AppFontPreset.lato => 'Lato',
  };
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
            child: SingleChildScrollView(
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
                  Row(
                    children: [
                      const Icon(Icons.font_download_outlined),
                      const SizedBox(width: 10),
                      const Expanded(child: Text('App font')),
                      DropdownButton<AppFontPreset>(
                        value: controller.fontPreset,
                        onChanged: (value) {
                          if (value != null) {
                            controller.setFontPreset(value);
                          }
                        },
                        items: AppFontPreset.values
                            .map(
                              (preset) => DropdownMenuItem(
                                value: preset,
                                child: Text(_fontPresetLabel(preset)),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ExpansionTile(
                    leading: const Icon(Icons.palette_outlined),
                    title: const Text('Accent color'),
                    subtitle: Text(
                      '#${(controller.accentColorValue & 0x00FFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                        child: _AnyColorPicker(
                          value: Color(controller.accentColorValue),
                          onChanged: (color) =>
                              controller.setAccentColorValue(color.toARGB32()),
                        ),
                      ),
                    ],
                  ),
                  ExpansionTile(
                    leading: const Icon(Icons.note_alt_outlined),
                    title: const Text('Editor paper color'),
                    subtitle: Text(
                      '#${(controller.editorPaperColorValue & 0x00FFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                        child: _AnyColorPicker(
                          value: Color(controller.editorPaperColorValue),
                          onChanged: (color) =>
                              controller.setEditorPaperColorValue(
                                color.toARGB32(),
                              ),
                        ),
                      ),
                    ],
                  ),
                  ExpansionTile(
                    leading: const Icon(Icons.key_rounded),
                    title: const Text('API key'),
                    subtitle: Text(
                      controller.hasApiKey ? 'Saved in this session' : 'Not set',
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                        child: TextFormField(
                          initialValue: controller.apiKey,
                          obscureText: true,
                          onChanged: controller.setApiKey,
                          decoration: const InputDecoration(
                            labelText: 'Enter API key',
                            prefixIcon: Icon(Icons.vpn_key_outlined),
                          ),
                        ),
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
