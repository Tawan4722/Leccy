import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_drawing_board/flutter_drawing_board.dart' as drawing;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill_extensions/flutter_quill_extensions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' as intl;
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/leccy_store.dart';
import '../domain/backup_models.dart';
import '../domain/gemini_service.dart';
import '../domain/models.dart';
import '../domain/pptx_export_service.dart';
import 'app_controller.dart';
import 'app_localizations.dart';
import 'cover_image_provider.dart'
    if (dart.library.io) 'cover_image_provider_io.dart';
import 'voice_recording_target.dart'
    if (dart.library.io) 'voice_recording_target_io.dart';

const String leccyFoldHiddenAttributeKey = 'leccy-fold-hidden';
const String leccyAudioEmbedType = 'leccy-audio';
const String _foldHeadingLevelAttributeKey = 'leccy-fold-heading-level';
const String _quillListAttributeKey = 'list';
const String _foldLeadingListValue = 'leccy-fold-leading';
const quill.Attribute<bool> _foldHiddenAttribute = quill.Attribute<bool>(
  leccyFoldHiddenAttributeKey,
  quill.AttributeScope.block,
  true,
);
const quill.Attribute<String> _foldLeadingAttribute = quill.Attribute<String>(
  _quillListAttributeKey,
  quill.AttributeScope.block,
  _foldLeadingListValue,
);
quill.Attribute<int> _foldHeadingLevelAttribute(int level) =>
    quill.Attribute<int>(
      _foldHeadingLevelAttributeKey,
      quill.AttributeScope.block,
      level,
    );
const quill.Attribute<Object?> _clearFoldHiddenAttribute =
    quill.Attribute<Object?>(
      leccyFoldHiddenAttributeKey,
      quill.AttributeScope.block,
      null,
    );
const quill.Attribute<Object?> _clearFoldLeadingAttribute =
    quill.Attribute<Object?>(
      _quillListAttributeKey,
      quill.AttributeScope.block,
      null,
    );
const quill.Attribute<Object?> _clearFoldHeadingLevelAttribute =
    quill.Attribute<Object?>(
      _foldHeadingLevelAttributeKey,
      quill.AttributeScope.block,
      null,
    );

class LeccyHeadingFoldRange {
  const LeccyHeadingFoldRange({
    required this.headingOffset,
    required this.headingLevel,
    required this.childLineOffsets,
  });

  final int headingOffset;
  final int headingLevel;
  final List<int> childLineOffsets;

  bool get canFold => childLineOffsets.isNotEmpty;
}

List<LeccyHeadingFoldRange> computeLeccyHeadingFoldRanges(
  quill.Document document,
) {
  final lines = _documentLines(document);
  final ranges = <LeccyHeadingFoldRange>[];
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    final level = _headingLevelForLine(line);
    if (level == null) {
      continue;
    }
    final childOffsets = <int>[];
    for (var childIndex = index + 1; childIndex < lines.length; childIndex++) {
      final childLine = lines[childIndex];
      final childLevel = _headingLevelForLine(childLine);
      if (childLevel != null && childLevel <= level) {
        break;
      }
      childOffsets.add(childLine.documentOffset);
    }
    ranges.add(
      LeccyHeadingFoldRange(
        headingOffset: line.documentOffset,
        headingLevel: level,
        childLineOffsets: childOffsets,
      ),
    );
  }
  return ranges;
}

List<quill.Line> _documentLines(quill.Document document) {
  final lines = <quill.Line>[];

  void walk(quill.Node node) {
    if (node is quill.Line) {
      lines.add(node);
      return;
    }
    if (node is quill.Block) {
      for (final child in node.children.whereType<quill.Node>()) {
        walk(child);
      }
    }
  }

  for (final node in document.root.children.whereType<quill.Node>()) {
    walk(node);
  }
  return lines;
}

int? _headingLevelForLine(quill.Line line) {
  final header = line.style.attributes[quill.Attribute.header.key];
  final value = header?.value;
  if (value is int) {
    return value;
  }
  final temporaryHeader =
      line.style.attributes[_foldHeadingLevelAttributeKey]?.value;
  return temporaryHeader is int ? temporaryHeader : null;
}

dynamic _stripFoldHiddenFromDeltaJson(dynamic json) {
  if (json is List) {
    return json.map<dynamic>(_stripFoldHiddenFromDeltaJson).toList();
  }
  if (json is Map) {
    final cleaned = Map<String, Object?>.from(json);
    final attributes = cleaned['attributes'];
    if (attributes is Map) {
      final cleanedAttributes = Map<String, Object?>.from(attributes);
      final temporaryHeadingLevel =
          cleanedAttributes[_foldHeadingLevelAttributeKey];
      if (temporaryHeadingLevel is int) {
        cleanedAttributes[quill.Attribute.header.key] = temporaryHeadingLevel;
      }
      cleanedAttributes.remove(leccyFoldHiddenAttributeKey);
      cleanedAttributes.remove(_foldHeadingLevelAttributeKey);
      if (cleanedAttributes[quill.Attribute.list.key] ==
          _foldLeadingListValue) {
        cleanedAttributes.remove(quill.Attribute.list.key);
      }
      if (cleanedAttributes.isEmpty) {
        cleaned.remove('attributes');
      } else {
        cleaned['attributes'] = cleanedAttributes;
      }
    }
    return cleaned;
  }
  return json;
}

String stripLeccyFoldHiddenFromContentJson(String contentJson) {
  return jsonEncode(_stripFoldHiddenFromDeltaJson(jsonDecode(contentJson)));
}

String _fontPresetLabel(AppFontPreset preset) {
  return switch (preset) {
    AppFontPreset.workSans => 'Work Sans',
    AppFontPreset.nunito => 'Nunito Sans',
    AppFontPreset.sourceSerif => 'Source Serif 4',
    AppFontPreset.lato => 'Lato',
  };
}

String _displayLectureTitle(BuildContext context, String title) {
  final trimmed = title.trim();
  return trimmed.isEmpty ? context.t('Untitled lecture') : trimmed;
}

class LeccyApp extends ConsumerWidget {
  const LeccyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appControllerProvider);
    final isDark = app.themeMode == AppThemeMode.dark;
    final accent = Color(app.accentColorValue);
    final base =
        ColorScheme.fromSeed(
          seedColor: accent,
          brightness: isDark ? Brightness.dark : Brightness.light,
        ).copyWith(
          surface: isDark ? const Color(0xFF282522) : const Color(0xFFF4EEDD),
          onSurface: isDark ? const Color(0xFFD4C8C0) : const Color(0xFF4C3E36),
          primary: isDark ? const Color(0xFFD4A373) : const Color(0xFF967259),
          primaryContainer: isDark
              ? const Color(0xFF5C4736)
              : const Color(0xFFE6D0C0),
        );

    return MaterialApp(
      title: 'Leccy',
      debugShowCheckedModeBanner: false,
      locale: Locale(app.language.name),
      supportedLocales: const [Locale('en'), Locale('th')],
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
          ? const Color(0xFF1E1B19)
          : const Color(0xFFEDE0D4),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(32)),
          borderSide: BorderSide(
            color: isDark ? const Color(0x33D4C8C0) : const Color(0x334C3E36),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(32)),
          borderSide: BorderSide(
            color: isDark ? const Color(0x22D4C8C0) : const Color(0x224C3E36),
          ),
        ),
        filled: true,
        fillColor: isDark ? const Color(0x11D4C8C0) : const Color(0x88F4EEDD),
        isDense: true,
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(32)),
        ),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(32),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(32),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(32),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
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

class _OpenCommandPaletteIntent extends Intent {
  const _OpenCommandPaletteIntent();
}

class _CreateNewFileIntent extends Intent {
  const _CreateNewFileIntent();
}

class _DeleteSelectedFileIntent extends Intent {
  const _DeleteSelectedFileIntent();
}

class _ToggleImportantIntent extends Intent {
  const _ToggleImportantIntent();
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
    return Actions(
      actions: {
        _OpenCommandPaletteIntent: CallbackAction<_OpenCommandPaletteIntent>(
          onInvoke: (_) => _showCommandPalette(context, app),
        ),
        _CreateNewFileIntent: CallbackAction<_CreateNewFileIntent>(
          onInvoke: (_) => app.createFile(),
        ),
        _DeleteSelectedFileIntent: CallbackAction<_DeleteSelectedFileIntent>(
          onInvoke: (_) => app.moveSelectedFileToTrash(),
        ),
        _ToggleImportantIntent: CallbackAction<_ToggleImportantIntent>(
          onInvoke: (_) {
            final fileId = app.selectedFileId;
            if (fileId != null) {
              return app.toggleFileImportant(fileId);
            }
            return null;
          },
        ),
      },
      child: Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.keyK, control: true):
              _OpenCommandPaletteIntent(),
          SingleActivator(LogicalKeyboardKey.keyN, control: true):
              _CreateNewFileIntent(),
          SingleActivator(LogicalKeyboardKey.delete):
              _DeleteSelectedFileIntent(),
          SingleActivator(LogicalKeyboardKey.keyI, control: true, shift: true):
              _ToggleImportantIntent(),
        },
        child: Scaffold(
          body: _FastModeScope(
            enabled: app.fastMode,
            child: Stack(
              children: [
                const _LiquidWallpaper(),
                SafeArea(
                  child: Row(
                    children: [
                      if (app.selectedFileId == null)
                        SizedBox(
                          width: 320,
                          child: FolderLibrary(controller: app),
                        ),
                      Expanded(child: LectureWorkspace(controller: app)),
                    ],
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

class _FastModeScope extends InheritedWidget {
  const _FastModeScope({required this.enabled, required super.child});

  final bool enabled;

  static bool of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<_FastModeScope>()
            ?.enabled ??
        false;
  }

  @override
  bool updateShouldNotify(_FastModeScope oldWidget) =>
      oldWidget.enabled != enabled;
}

Duration _motionDuration(BuildContext context, int normalMs) {
  return _FastModeScope.of(context)
      ? Duration.zero
      : Duration(milliseconds: normalMs);
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
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
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
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            letterSpacing: -0.5,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    Text(
                      context.t('Workspace'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                IconButton.filledTonal(
                  tooltip: context.t('Search commands'),
                  style: IconButton.styleFrom(
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHigh,
                  ),
                  onPressed: () => _showCommandPalette(context, controller),
                  icon: const Icon(Icons.search_rounded),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: context.t('Settings'),
                  style: IconButton.styleFrom(
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHigh,
                  ),
                  onPressed: () => _showSettingsSheet(context, controller),
                  icon: const Icon(Icons.tune_rounded),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: context.t('New folder'),
                  style: IconButton.styleFrom(
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primaryContainer,
                  ),
                  onPressed: () => _showFolderDialog(context, controller),
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: controller.setSearchQuery,
                    decoration: InputDecoration(
                      hintText: context.t('Search...'),
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      filled: true,
                      fillColor: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 0,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(32),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton.filledTonal(
                  tooltip: context.t('Sort/View'),
                  onPressed: () => _showViewOptions(context, controller),
                  icon: const Icon(Icons.filter_list_rounded),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Expanded(
              child: folders.isEmpty
                  ? EmptyState(
                      icon: Icons.folder_open_rounded,
                      title: context.t('No folders yet'),
                      actionLabel: context.t('Create folder'),
                      onAction: () => _showFolderDialog(context, controller),
                    )
                  : controller.isGrid
                  ? GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                            childAspectRatio: 0.85,
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
                          const SizedBox(height: 12),
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
    return _LiquidGlass(
      borderRadius: 22,
      selected: isSelected,
      tint: color,
      padding: EdgeInsets.zero,
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
                      child: _GlassIconButton(
                        tooltip: context.t('Customize folder'),
                        icon: Icons.tune_rounded,
                        onPressed: onEdit,
                        size: 30,
                        iconSize: 16,
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
                context.filesCount(fileCount),
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
        title: context.t('Create a folder to start'),
        actionLabel: context.t('New folder'),
        onAction: () => _showFolderDialog(context, controller),
      );
    }
    final hasActiveFile = controller.selectedFileId != null;
    return Row(
      children: [
        if (!controller.showLeftPane && !controller.editorFullscreen && !hasActiveFile)
          IconButton.filledTonal(
            tooltip: context.t('Open left panel'),
            onPressed: () => controller.setLeftPaneVisible(true),
            icon: const Icon(Icons.keyboard_double_arrow_right_rounded),
          ),
        if (controller.showLeftPane && !controller.editorFullscreen && !hasActiveFile)
          SizedBox(
            width: controller.leftPaneWidth,
            child: FileListPanel(controller: controller, folder: folder),
          ),
        if (controller.showLeftPane && !controller.editorFullscreen && !hasActiveFile)
          _PaneHandle(
            onDrag: controller.resizeLeftPane,
            tooltip: context.t('Resize left panel'),
          ),
        Expanded(child: NoteEditor(controller: controller)),
        if (controller.showRightPane && !controller.editorFullscreen && !hasActiveFile)
          _PaneHandle(
            onDrag: (delta) => controller.resizeRightPane(-delta),
            tooltip: context.t('Resize right panel'),
          ),
        if (controller.showRightPane && !controller.editorFullscreen && !hasActiveFile)
          SizedBox(
            width: controller.rightPaneWidth,
            child: ProgressPanel(controller: controller),
          ),
        if (!controller.showRightPane && !controller.editorFullscreen && !hasActiveFile)
          IconButton.filledTonal(
            tooltip: context.t('Open right panel'),
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
                  tooltip: context.t('Close left panel'),
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
              context.t('Lecture files'),
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
                    label: Text(context.t('New file')),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: controller.fileSelectionMode
                      ? context.t('Exit selection mode')
                      : context.t('Select lectures'),
                  onPressed: () => controller.setFileSelectionMode(
                    !controller.fileSelectionMode,
                  ),
                  icon: Icon(
                    controller.fileSelectionMode
                        ? Icons.close_rounded
                        : Icons.checklist_rounded,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: context.t('Create progress set'),
                  onPressed:
                      !controller.fileSelectionMode ||
                          controller.selectedFileIds.isEmpty
                      ? null
                      : controller.createStudySetFromSelection,
                  icon: const Icon(Icons.timeline_rounded),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: context.t('Trash'),
                  onPressed: () => _showTrashSheet(context, controller),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: files.isEmpty
                  ? EmptyState(
                      icon: Icons.note_alt_outlined,
                      title: context.t('No files in this folder'),
                      actionLabel: context.t('Create file'),
                      onAction: controller.createFile,
                    )
                  : AnimatedSwitcher(
                      duration: _motionDuration(context, 260),
                      child: ListView.separated(
                        key: ValueKey(
                          '${folder.id}-${files.length}-${controller.fileSelectionMode}',
                        ),
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
                            selectionMode: controller.fileSelectionMode,
                            onTap: () => controller.selectFile(file.id),
                            onCheck: () =>
                                controller.toggleFileSelection(file.id),
                            onToggleImportant: () =>
                                controller.toggleFileImportant(file.id),
                            onMoveToTrash: () =>
                                controller.moveFileToTrash(file.id),
                          );
                        },
                      ),
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
    required this.selectionMode,
    required this.onTap,
    required this.onCheck,
    required this.onToggleImportant,
    required this.onMoveToTrash,
  });

  final LectureFile file;
  final bool isSelected;
  final bool isChecked;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback onCheck;
  final VoidCallback onToggleImportant;
  final VoidCallback onMoveToTrash;

  @override
  Widget build(BuildContext context) {
    final importantColor = const Color(0xFFD32F2F);
    final importantTint = const Color(0xFFE57373);
    return _LiquidGlass(
      borderRadius: 20,
      selected: isSelected,
      tint: file.isImportant
          ? importantTint
          : Theme.of(context).colorScheme.primary,
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        onLongPress: onCheck,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedSwitcher(
                duration: _motionDuration(context, 160),
                child: selectionMode
                    ? Checkbox(
                        key: const ValueKey('checkbox'),
                        value: isChecked,
                        onChanged: (_) => onCheck(),
                      )
                    : Icon(
                        key: const ValueKey('lecture-icon'),
                        isSelected
                            ? Icons.radio_button_checked_rounded
                            : Icons.article_outlined,
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _displayLectureTitle(context, file.title),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: file.isImportant ? importantColor : null,
                        fontWeight: file.isImportant
                            ? FontWeight.w700
                            : FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      file.description.isEmpty
                          ? context.t('No description')
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
                        valueColor: AlwaysStoppedAnimation<Color>(
                          file.isImportant
                              ? importantColor
                              : Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                children: [
                  IconButton(
                    tooltip: file.isImportant
                        ? context.t('Marked important')
                        : context.t('Mark important'),
                    onPressed: onToggleImportant,
                    icon: Icon(
                      file.isImportant
                          ? Icons.flag_rounded
                          : Icons.outlined_flag_rounded,
                      color: file.isImportant ? importantColor : null,
                    ),
                  ),
                  IconButton(
                    tooltip: context.t('Move to trash'),
                    onPressed: onMoveToTrash,
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                  Text('${file.progressPercent}%'),
                ],
              ),
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

class _NoteEditorState extends State<NoteEditor> with WidgetsBindingObserver {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _quickNoteController = TextEditingController();
  final _searchController = TextEditingController();
  quill.QuillController? _quillController;
  StreamSubscription<dynamic>? _documentSubscription;
  Timer? _saveTimer;
  Timer? _autoSummaryTimer;
  Timer? _foldVisibilityTimer;
  int? _boundFileId;
  final _geminiService = GeminiService();
  final _pptxExportService = PptxExportService();
  final ValueNotifier<bool> _isSaving = ValueNotifier(false);
  final ValueNotifier<bool> _hasPendingChanges = ValueNotifier(false);
  bool _isSummarizing = false;
  bool _isGeneratingWorkspace = false;
  bool _isRestructuring = false;
  bool _showOutline = false;
  bool _showFlashAnswer = false;
  bool _showFormatToolbar = false;
  EditorSurface _surface = EditorSurface.note;
  List<int> _searchOffsets = const [];
  int _activeSearchMatch = 0;
  int _flashcardIndex = 0;
  final Set<int> _collapsedSectionOffsets = {};
  final List<GeneratedFlashcard> _flashcards = [];
  _RestructureBackup? _lastRestructureBackup;
  bool _isApplyingFoldVisibility = false;
  Color _activeMarkerColor = _markerColors.first;

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
    _foldVisibilityTimer?.cancel();
    _documentSubscription?.cancel();
    _titleController.dispose();
    _descriptionController.dispose();
    _quickNoteController.dispose();
    _searchController.dispose();
    _quillController?.dispose();
    _geminiService.close();
    _isSaving.dispose();
    _hasPendingChanges.dispose();
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
    _foldVisibilityTimer?.cancel();
    _documentSubscription?.cancel();
    _boundFileId = file?.id;
    _titleController.text = file?.title ?? '';
    _descriptionController.text = file?.description ?? '';
    _quickNoteController.text = file?.quickNote ?? '';
    _quillController?.dispose();
    final decoded =
        _stripFoldHiddenFromDeltaJson(
              jsonDecode(widget.controller.documentJsonForFile(file)),
            )
            as List;
    _quillController = quill.QuillController(
      document: quill.Document.fromJson(decoded.cast<Map<String, dynamic>>()),
      selection: const TextSelection.collapsed(offset: 0),
    );
    _documentSubscription = _quillController!.document.changes.listen((_) {
      if (_isApplyingFoldVisibility) {
        return;
      }
      _syncCollapsedHeadingOffsets();
      _applyFoldVisibility();
      _scheduleSave();
      if (_searchController.text.trim().isNotEmpty) {
        _refreshSearch();
      }
    });
    _hasPendingChanges.value = false;
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
    _applyFoldVisibility();
  }

  void _scheduleSave() {
    if (_boundFileId == null) {
      return;
    }
    _hasPendingChanges.value = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 3), _saveNow);
    _scheduleAutoSummary();
  }

  void _scheduleAutoSummary() {
    final file = widget.controller.selectedFile;
    if (file == null || !file.autoSummaryEnabled) {
      _autoSummaryTimer?.cancel();
      return;
    }
    _autoSummaryTimer?.cancel();
    _autoSummaryTimer = Timer(
      Duration(milliseconds: widget.controller.fastMode ? 4500 : 6000),
      _runAutoSummary,
    );
  }

  String _currentNotePlainText() {
    final quillController = _quillController;
    if (quillController == null) {
      return '';
    }
    final contentJson = _contentJsonForPersistence(quillController);
    return widget.controller.notePlainTextFromContent(contentJson);
  }

  String _contentJsonForPersistence(quill.QuillController quillController) {
    final json = quillController.document.toDelta().toJson();
    return jsonEncode(_stripFoldHiddenFromDeltaJson(json));
  }

  Map<int, LeccyHeadingFoldRange> _foldRangesByHeadingOffset() {
    final quillController = _quillController;
    if (quillController == null) {
      return const {};
    }
    return {
      for (final range in computeLeccyHeadingFoldRanges(
        quillController.document,
      ))
        range.headingOffset: range,
    };
  }

  bool _isFoldHiddenLine(quill.Line line) {
    return line.style.attributes[leccyFoldHiddenAttributeKey]?.value == true;
  }

  bool _hasFoldLeadingMarker(quill.Line line) {
    return line.style.attributes[quill.Attribute.list.key]?.value ==
        _foldLeadingListValue;
  }

  int? _temporaryHeadingLevelForLine(quill.Line line) {
    final value = line.style.attributes[_foldHeadingLevelAttributeKey]?.value;
    return value is int ? value : null;
  }

  quill.Attribute<int?> _headerAttributeForLevel(int level) {
    return switch (level) {
      1 => quill.Attribute.h1,
      2 => quill.Attribute.h2,
      3 => quill.Attribute.h3,
      4 => quill.Attribute.h4,
      5 => quill.Attribute.h5,
      _ => quill.Attribute.h6,
    };
  }

  void _syncCollapsedHeadingOffsets() {
    final ranges = _foldRangesByHeadingOffset();
    _collapsedSectionOffsets.removeWhere(
      (offset) => ranges[offset]?.canFold != true,
    );
  }

  void _toggleHeadingFold(int headingOffset) {
    setState(() {
      if (_collapsedSectionOffsets.contains(headingOffset)) {
        _collapsedSectionOffsets.remove(headingOffset);
      } else {
        _collapsedSectionOffsets.add(headingOffset);
      }
    });
    _applyFoldVisibility();
  }

  Widget? _buildFoldLeading(quill.Node node, dynamic _) {
    if (node is! quill.Line) {
      return null;
    }
    if (_isFoldHiddenLine(node)) {
      return const SizedBox.shrink();
    }
    final level = _headingLevelForLine(node);
    if (level == null) {
      return null;
    }
    final range = _foldRangesByHeadingOffset()[node.documentOffset];
    if (range?.canFold != true) {
      return const SizedBox(width: 32);
    }
    final isCollapsed = _collapsedSectionOffsets.contains(node.documentOffset);
    return SizedBox(
      width: 32,
      child: IconButton(
        tooltip: isCollapsed
            ? context.t('Expand section')
            : context.t('Collapse section'),
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        iconSize: 20,
        onPressed: () => _toggleHeadingFold(node.documentOffset),
        icon: Icon(
          isCollapsed
              ? Icons.keyboard_arrow_right_rounded
              : Icons.keyboard_arrow_down_rounded,
        ),
      ),
    );
  }

  TextStyle _foldStyle(quill.Attribute attribute) {
    if (attribute.key == _foldHeadingLevelAttributeKey) {
      return switch (attribute.value) {
        1 => const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
        2 => const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        3 => const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
        _ => const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      };
    }
    if (attribute.key != leccyFoldHiddenAttributeKey ||
        attribute.value != true) {
      return const TextStyle();
    }
    return const TextStyle(
      color: Colors.transparent,
      backgroundColor: Colors.transparent,
      fontSize: 0.1,
      height: 0.01,
    );
  }

  void _applyFoldVisibility() {
    final quillController = _quillController;
    if (quillController == null) {
      return;
    }
    final ranges = _foldRangesByHeadingOffset();
    final hiddenOffsets = <int>{};
    for (final headingOffset in _collapsedSectionOffsets) {
      final range = ranges[headingOffset];
      if (range != null) {
        hiddenOffsets.addAll(range.childLineOffsets);
      }
    }
    final leadingOffsets = {
      for (final range in ranges.values)
        if (range.canFold) range.headingOffset,
    };

    _isApplyingFoldVisibility = true;
    try {
      for (final line in _documentLines(quillController.document)) {
        final shouldHaveLeading = leadingOffsets.contains(line.documentOffset);
        final hasLeading = _hasFoldLeadingMarker(line);
        final temporaryHeadingLevel = _temporaryHeadingLevelForLine(line);
        final range = ranges[line.documentOffset];
        if (shouldHaveLeading && range != null) {
          if (temporaryHeadingLevel != range.headingLevel) {
            quillController.formatText(
              line.documentOffset,
              line.length,
              _foldHeadingLevelAttribute(range.headingLevel),
              // ignore: experimental_member_use
              shouldNotifyListeners: false,
            );
          }
          if (!hasLeading) {
            quillController.formatText(
              line.documentOffset,
              line.length,
              _foldLeadingAttribute,
              // ignore: experimental_member_use
              shouldNotifyListeners: false,
            );
          }
        } else if (hasLeading || temporaryHeadingLevel != null) {
          if (temporaryHeadingLevel != null) {
            quillController.formatText(
              line.documentOffset,
              line.length,
              _headerAttributeForLevel(temporaryHeadingLevel),
              // ignore: experimental_member_use
              shouldNotifyListeners: false,
            );
          }
          quillController.formatText(
            line.documentOffset,
            line.length,
            _clearFoldLeadingAttribute,
            // ignore: experimental_member_use
            shouldNotifyListeners: false,
          );
          quillController.formatText(
            line.documentOffset,
            line.length,
            _clearFoldHeadingLevelAttribute,
            // ignore: experimental_member_use
            shouldNotifyListeners: false,
          );
        }

        final shouldHide = hiddenOffsets.contains(line.documentOffset);
        final isHidden = _isFoldHiddenLine(line);
        if (shouldHide == isHidden) {
          continue;
        }
        quillController.formatText(
          line.documentOffset,
          line.length,
          shouldHide ? _foldHiddenAttribute : _clearFoldHiddenAttribute,
          // ignore: experimental_member_use
          shouldNotifyListeners: false,
        );
      }
    } finally {
      _foldVisibilityTimer?.cancel();
      _foldVisibilityTimer = Timer(
        const Duration(milliseconds: 250),
        () => _isApplyingFoldVisibility = false,
      );
    }
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
    quillController.formatSelection(
      quill.Attribute.fromKeyValue('background', hex),
    );
  }

  void _applyActiveMarker() {
    _applyHighlight(_activeMarkerColor);
  }

  void _setActiveMarkerColor(Color color) {
    setState(() => _activeMarkerColor = color);
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

  quill.Line? _currentSelectionLine(
    quill.Node? node, {
    bool preferNextLineWhenOnLineBreak = false,
  }) {
    final quillController = _quillController;
    if (quillController == null) {
      return null;
    }
    final selectionOffset = quillController.selection.baseOffset;
    if (selectionOffset >= 0) {
      final query = quillController.document.queryChild(selectionOffset);
      final queriedNode = query.node;
      quill.Line? line;
      if (queriedNode is quill.Line) {
        line = queriedNode;
      } else if (queriedNode?.parent is quill.Line) {
        line = queriedNode!.parent as quill.Line;
      }
      if (line != null) {
        final isOnLineBreak = query.offset == line.length - 1;
        if (preferNextLineWhenOnLineBreak &&
            isOnLineBreak &&
            line.nextLine != null) {
          return line.nextLine;
        }
        return line;
      }
    }
    if (node is quill.Line) {
      return node;
    }
    if (node?.parent is quill.Line) {
      return node!.parent as quill.Line;
    }
    return null;
  }

  String _lineTextWithoutTrailingBreak(quill.Line line) {
    final full = line.toPlainText();
    return full.endsWith('\n') ? full.substring(0, full.length - 1) : full;
  }

  bool _isAtStartOfLine(quill.Line line, TextSelection selection) {
    return selection.baseOffset == line.documentOffset;
  }

  void _applyHeadingLevelToLine(quill.Line line, int level) {
    final quillController = _quillController;
    if (quillController == null) {
      return;
    }
    final attribute = switch (level) {
      1 => quill.Attribute.h1,
      2 => quill.Attribute.h2,
      _ => quill.Attribute.h3,
    };
    quillController.formatText(line.documentOffset, line.length, attribute);
  }

  KeyEventResult? _handleOutlineKeyPressed(KeyEvent event, quill.Node? node) {
    final quillController = _quillController;
    if (quillController == null ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return null;
    }
    if (HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      return null;
    }
    final selection = quillController.selection;
    if (!selection.isCollapsed || selection.baseOffset < 0) {
      return null;
    }
    final line = _currentSelectionLine(
      node,
      preferNextLineWhenOnLineBreak:
          event.logicalKey == LogicalKeyboardKey.tab &&
          !HardwareKeyboard.instance.isShiftPressed,
    );
    if (line == null) {
      return null;
    }
    final headingLevel = _headingLevelForLine(line);
    if (event.logicalKey == LogicalKeyboardKey.tab &&
        !HardwareKeyboard.instance.isShiftPressed) {
      // When caret sits on a line boundary, some platforms report the prior
      // line offset. Retry against the next offset for Tab outline behavior.
      if (headingLevel == null &&
          _lineTextWithoutTrailingBreak(line).trim().isEmpty &&
          selection.baseOffset + 1 < quillController.document.length) {
        final retryNode = quillController.document
            .queryChild(selection.baseOffset + 1)
            .node;
        final retryLine = _currentSelectionLine(retryNode);
        if (retryLine != null) {
          final retryHeading = _headingLevelForLine(retryLine);
          if (retryHeading != null) {
            final retryLevel = switch (retryHeading) {
              1 => 2,
              2 => 3,
              _ => 3,
            };
            _applyHeadingLevelToLine(retryLine, retryLevel);
            return KeyEventResult.handled;
          }
        }
      }
      if (headingLevel == null) {
        if (_lineTextWithoutTrailingBreak(line).trim().isEmpty) {
          return null;
        }
        _applyHeadingLevelToLine(line, 2);
        return KeyEventResult.handled;
      }
      final nextLevel = switch (headingLevel) {
        1 => 2,
        2 => 3,
        _ => 3,
      };
      _applyHeadingLevelToLine(line, nextLevel);
      return KeyEventResult.handled;
    }
    final promotedLevel = switch (headingLevel) {
      3 => 2,
      2 => 1,
      _ => null,
    };
    if (event.logicalKey == LogicalKeyboardKey.backspace &&
        _isAtStartOfLine(line, selection) &&
        promotedLevel != null) {
      _applyHeadingLevelToLine(line, promotedLevel);
      return KeyEventResult.handled;
    }
    return null;
  }

  static const List<String> _fontSizeOrder = [
    'small',
    'normal',
    'large',
    'huge',
  ];

  String _activeFontSize() {
    final quillController = _quillController;
    if (quillController == null) {
      return 'normal';
    }
    final raw = quillController
        .getSelectionStyle()
        .attributes[quill.Attribute.size.key]
        ?.value;
    final size = raw?.toString();
    if (size == null || size.isEmpty || size == 'normal') {
      return 'normal';
    }
    return _fontSizeOrder.contains(size) ? size : 'normal';
  }

  void _applyFontSize(String value) {
    final quillController = _quillController;
    if (quillController == null) {
      return;
    }
    if (value == 'normal') {
      quillController.formatSelection(
        quill.Attribute.clone(quill.Attribute.size, null),
      );
    } else {
      quillController.formatSelection(quill.SizeAttribute(value));
    }
    _scheduleSave();
  }

  void _stepFontSize(bool increase) {
    final current = _activeFontSize();
    final index = _fontSizeOrder.indexOf(current);
    final safeIndex = index == -1 ? 1 : index;
    final next = (safeIndex + (increase ? 1 : -1)).clamp(
      0,
      _fontSizeOrder.length - 1,
    );
    _applyFontSize(_fontSizeOrder[next]);
  }

  void _insertEmbed(quill.BlockEmbed embed) {
    final quillController = _quillController;
    if (quillController == null) {
      return;
    }
    final selection = quillController.selection;
    final index = selection.baseOffset < 0 ? 0 : selection.baseOffset;
    final length = selection.extentOffset > selection.baseOffset
        ? selection.extentOffset - selection.baseOffset
        : 0;
    quillController
      ..skipRequestKeyboard = true
      ..replaceText(index, length, embed, null)
      ..moveCursorToPosition(index + 1);
    _scheduleSave();
  }

  Future<void> _insertPickedMedia({
    required FileType type,
    required String mediaType,
    required quill.BlockEmbed Function(String path) embedBuilder,
  }) async {
    final result = await FilePicker.pickFiles(type: type, withData: true);
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null) {
      return;
    }
    final path = await widget.controller.repository.saveAttachment(
      bytes: bytes,
      extension: file.extension ?? (mediaType == 'videos' ? 'mp4' : 'png'),
      mediaType: mediaType,
    );
    _insertEmbed(embedBuilder(path));
  }

  Future<void> _insertImage() async {
    await _insertPickedMedia(
      type: FileType.image,
      mediaType: 'images',
      embedBuilder: quill.BlockEmbed.image,
    );
  }

  Future<void> _insertVideo() async {
    await _insertPickedMedia(
      type: FileType.video,
      mediaType: 'videos',
      embedBuilder: quill.BlockEmbed.video,
    );
  }

  Future<void> _insertLink() async {
    final link = await showDialog<_LinkDraft>(
      context: context,
      builder: (context) => const _LinkDialog(),
    );
    if (link == null || link.url.trim().isEmpty) {
      return;
    }
    final quillController = _quillController;
    if (quillController == null) {
      return;
    }
    final selection = quillController.selection;
    if (selection.start >= 0 && selection.end > selection.start) {
      quillController.formatSelection(quill.LinkAttribute(link.url.trim()));
    } else {
      final text = link.label.trim().isEmpty
          ? link.url.trim()
          : link.label.trim();
      final index = selection.baseOffset < 0 ? 0 : selection.baseOffset;
      quillController.replaceText(index, 0, text, null);
      quillController.formatText(
        index,
        text.length,
        quill.LinkAttribute(link.url.trim()),
      );
      quillController.moveCursorToPosition(index + text.length);
    }
    _scheduleSave();
  }

  Future<void> _insertDrawing() async {
    final drawingData = await showDialog<_DrawingResult>(
      context: context,
      builder: (context) => const _DrawingDialog(),
    );
    if (drawingData == null) {
      return;
    }
    final imagePath = await widget.controller.repository.saveAttachment(
      bytes: drawingData.pngBytes,
      extension: 'png',
      mediaType: 'drawings',
    );
    await widget.controller.repository.saveAttachment(
      bytes: Uint8List.fromList(utf8.encode(jsonEncode(drawingData.json))),
      extension: 'json',
      mediaType: 'drawings',
    );
    _insertEmbed(quill.BlockEmbed.image(imagePath));
  }

  Future<void> _recordVoiceNote() async {
    final path = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          _VoiceRecorderDialog(repository: widget.controller.repository),
    );
    if (path == null || path.trim().isEmpty) {
      return;
    }
    final label = intl.DateFormat('MMM d, HH:mm').format(DateTime.now());
    _insertEmbed(
      quill.BlockEmbed.custom(
        quill.CustomBlockEmbed(
          leccyAudioEmbedType,
          jsonEncode({'source': path, 'label': 'Voice note $label'}),
        ),
      ),
    );
    _showMessage('Inserted voice note.');
  }

  Future<void> _importLectureFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'md', 'json', 'leccy'],
      withData: true,
    );
    final picked = result?.files.single;
    final bytes = picked?.bytes;
    if (picked == null || bytes == null) {
      return;
    }
    final text = utf8.decode(bytes, allowMalformed: true);
    final extension = (picked.extension ?? '').toLowerCase();
    try {
      if (extension == 'json' || extension == 'leccy') {
        await _importStructuredLecture(text, picked.name);
      } else {
        await _replaceNoteWithPlainText(text, picked.name);
      }
      _showMessage('Imported ${picked.name}.');
    } catch (error) {
      _showMessage('Could not import ${picked.name}: $error');
    }
  }

  Future<void> _importStructuredLecture(String text, String fileName) async {
    final decoded = jsonDecode(text);
    if (decoded is List) {
      _replaceDocumentJson(decoded.cast<Map<String, dynamic>>());
      _scheduleSave();
      return;
    }
    if (decoded is! Map) {
      throw const FormatException('Unsupported JSON shape.');
    }
    final map = decoded.cast<String, Object?>();
    final content = map['contentJson'] ?? map['content_json'] ?? map['delta'];
    if (content is String) {
      final decodedContent = jsonDecode(content);
      if (decodedContent is! List) {
        throw const FormatException('contentJson must be a Quill delta list.');
      }
      _replaceDocumentJson(decodedContent.cast<Map<String, dynamic>>());
    } else if (content is List) {
      _replaceDocumentJson(content.cast<Map<String, dynamic>>());
    } else if (map['text'] is String) {
      await _replaceNoteWithPlainText(map['text']! as String, fileName);
    } else {
      throw const FormatException('Missing contentJson or text.');
    }

    _titleController.text =
        (map['title']?.toString().trim().isNotEmpty ?? false)
        ? map['title'].toString()
        : _titleFromFileName(fileName);
    _descriptionController.text = map['description']?.toString() ?? '';
    _quickNoteController.text =
        (map['quickNote'] ?? map['quick_note'])?.toString() ?? '';

    final file = widget.controller.selectedFile;
    if (file != null) {
      await widget.controller.updateSelectedFile(
        title: _titleController.text,
        description: _descriptionController.text,
        quickNote: _quickNoteController.text,
        contentJson: _contentJsonForPersistence(_quillController!),
        sheetJson: map['sheetJson']?.toString() ?? file.sheetJson,
        slidesJson: map['slidesJson']?.toString() ?? file.slidesJson,
        flashcardsJson:
            map['flashcardsJson']?.toString() ?? file.flashcardsJson,
      );
    }
  }

  Future<void> _replaceNoteWithPlainText(String text, String fileName) async {
    final normalized = text.replaceAll('\r\n', '\n');
    _replaceDocumentJson([
      {'insert': normalized.endsWith('\n') ? normalized : '$normalized\n'},
    ]);
    _titleController.text = _titleFromFileName(fileName);
    await _saveNow();
  }

  void _replaceDocumentJson(List<Map<String, dynamic>> json) {
    final quillController = _quillController;
    if (quillController == null) {
      return;
    }
    quillController.document = quill.Document.fromJson(json);
    quillController.updateSelection(
      const TextSelection.collapsed(offset: 0),
      quill.ChangeSource.local,
    );
    _syncCollapsedHeadingOffsets();
    _applyFoldVisibility();
  }

  Future<void> _exportLectureFile() async {
    final file = widget.controller.selectedFile;
    final quillController = _quillController;
    if (file == null || quillController == null) {
      return;
    }
    await _saveNow();
    if (!mounted) {
      return;
    }
    final export = await showDialog<_ExportFormat>(
      context: context,
      builder: (context) => const _ExportDialog(),
    );
    if (export == null) {
      return;
    }
    final latest = widget.controller.selectedFile ?? file;
    final fileName = _safeFileName(latest.title);
    final bytes = switch (export) {
      _ExportFormat.text => utf8.encode(_currentNotePlainText()),
      _ExportFormat.markdown => utf8.encode(_currentNotePlainText()),
      _ExportFormat.leccy => utf8.encode(
        const JsonEncoder.withIndent('  ').convert({
          'title': latest.title,
          'description': latest.description,
          'quickNote': latest.quickNote,
          'contentJson': _contentJsonForPersistence(quillController),
          'sheetJson': latest.sheetJson,
          'slidesJson': latest.slidesJson,
          'flashcardsJson': latest.flashcardsJson,
        }),
      ),
    };
    final extension = switch (export) {
      _ExportFormat.text => 'txt',
      _ExportFormat.markdown => 'md',
      _ExportFormat.leccy => 'leccy',
    };
    final path = await FilePicker.saveFile(
      dialogTitle: 'Export lecture',
      fileName: '$fileName.$extension',
      type: FileType.custom,
      allowedExtensions: [extension],
      bytes: Uint8List.fromList(bytes),
    );
    if (path != null) {
      _showMessage('Exported $path');
    }
  }

  String _titleFromFileName(String fileName) {
    final withoutExtension = fileName.replaceFirst(RegExp(r'\.[^.]+$'), '');
    return withoutExtension.trim().isEmpty
        ? 'Imported lecture'
        : withoutExtension;
  }

  String _safeFileName(String title) {
    final cleaned = title
        .trim()
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '-')
        .replaceAll(RegExp(r'\s+'), ' ');
    return cleaned.isEmpty ? 'lecture' : cleaned;
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
    final previous =
        (_activeSearchMatch - 1 + _searchOffsets.length) %
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

  Future<void> _addMindMapBranch(_MindMapNode parent) async {
    final quillController = _quillController;
    if (quillController == null) {
      return;
    }
    final title = await _showMindMapBranchDialog(context);
    if (title == null || title.trim().isEmpty || !mounted) {
      return;
    }
    final childLevel = parent.level <= 0 ? 1 : (parent.level + 1).clamp(1, 6);
    final index = _mindMapInsertOffset(
      quillController.document,
      parentOffset: parent.offset,
      parentLevel: parent.level,
    );
    final plainText = quillController.document.toPlainText();
    final needsPrefix =
        index > 0 && index <= plainText.length && plainText[index - 1] != '\n';
    final prefix = needsPrefix ? '\n' : '';
    final cleanTitle = title.trim();
    final headingStart = index + prefix.length;
    quillController.replaceText(index, 0, '$prefix$cleanTitle\n', null);
    quillController.formatText(
      headingStart,
      cleanTitle.length + 1,
      _headerAttributeForLevel(childLevel),
    );
    quillController.moveCursorToPosition(headingStart + cleanTitle.length + 1);
    _scheduleSave();
    setState(() {});
  }

  int _mindMapInsertOffset(
    quill.Document document, {
    required int parentOffset,
    required int parentLevel,
  }) {
    if (parentLevel <= 0) {
      return math.max(0, document.length - 1);
    }
    final lines = _documentLines(document);
    var foundParent = false;
    for (final line in lines) {
      if (!foundParent) {
        foundParent = line.documentOffset == parentOffset;
        continue;
      }
      final level = _headingLevelForLine(line);
      if (level != null && level <= parentLevel) {
        return line.documentOffset;
      }
    }
    return math.max(0, document.length - 1);
  }

  List<_OutlineSection> _buildOutlineSections(
    quill.QuillController quillController,
  ) {
    final sections = <_OutlineSection>[];
    _OutlineSection? current;

    void ensureFallback() {
      current ??= _OutlineSection(
        title: context.t('General notes'),
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
      final text = full.endsWith('\n')
          ? full.substring(0, full.length - 1)
          : full;
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

    for (final node
        in quillController.document.root.children.whereType<quill.Node>()) {
      walk(node);
    }
    if (sections.isEmpty) {
      return [
        _OutlineSection(
          title: context.t('General notes'),
          level: 0,
          offset: 0,
          bodyLines: const <String>[],
        ),
      ];
    }
    return sections;
  }

  List<GeneratedFlashcard> _flashcardsFromFile(LectureFile file) {
    try {
      final decoded = jsonDecode(file.flashcardsJson);
      final cards = decoded is Map ? decoded['cards'] : null;
      if (cards is! List) {
        return const [];
      }
      return cards
          .whereType<Map>()
          .map(
            (item) => GeneratedFlashcard.fromJson(item.cast<String, Object?>()),
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _generateSlides() async {
    final file = widget.controller.selectedFile;
    if (file == null || _isGeneratingWorkspace) {
      return;
    }
    final text = _currentNotePlainText().trim();
    if (text.isEmpty) {
      _showMessage('Write notes first, then generate slides.');
      return;
    }
    setState(() => _isGeneratingWorkspace = true);
    try {
      final slides = await _geminiService.generateSlides(
        apiKey: widget.controller.apiKey,
        title: file.title,
        noteText: text,
        provider: widget.controller.aiProvider,
        baseUrl: widget.controller.aiBaseUrl,
        model: widget.controller.aiModel,
      );
      await widget.controller.updateSelectedFile(
        slidesJson: _pptxExportService.slidesToJson(slides),
      );
      _showMessage('Generated ${slides.length} slides.');
    } catch (error) {
      _showMessage(error.toString());
    } finally {
      if (mounted) {
        setState(() => _isGeneratingWorkspace = false);
      }
    }
  }

  Future<void> _exportSlides() async {
    final file = widget.controller.selectedFile;
    if (file == null) {
      return;
    }
    final slides = _pptxExportService.slidesFromJson(file.slidesJson);
    if (slides.isEmpty) {
      _showMessage('Generate or add slides before exporting.');
      return;
    }
    final bytes = _pptxExportService.buildDeck(
      title: file.title,
      slides: slides,
    );
    final path = await widget.controller.repository.saveAttachment(
      bytes: bytes,
      extension: 'pptx',
      mediaType: 'exports',
    );
    _showMessage('Exported PowerPoint: $path');
  }

  Future<void> _generateFlashcards() async {
    final file = widget.controller.selectedFile;
    if (file == null || _isGeneratingWorkspace) {
      return;
    }
    final text = _currentNotePlainText().trim();
    if (text.isEmpty) {
      _showMessage('Write notes first, then generate flashcards.');
      return;
    }
    setState(() => _isGeneratingWorkspace = true);
    try {
      final cards = await _geminiService.generateFlashcards(
        apiKey: widget.controller.apiKey,
        title: file.title,
        noteText: text,
        provider: widget.controller.aiProvider,
        baseUrl: widget.controller.aiBaseUrl,
        model: widget.controller.aiModel,
      );
      await widget.controller.updateSelectedFile(
        flashcardsJson: jsonEncode({
          'cards': cards.map((card) => card.toJson()).toList(),
        }),
      );
      setState(() {
        _flashcardIndex = 0;
        _showFlashAnswer = false;
      });
      _showMessage('Generated ${cards.length} flashcards.');
    } catch (error) {
      _showMessage(error.toString());
    } finally {
      if (mounted) {
        setState(() => _isGeneratingWorkspace = false);
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  void _showAiConfigBottomSheet(VoidCallback onConfiguredAndGenerate) {
    String provider = widget.controller.aiProvider;
    String baseUrl = widget.controller.aiBaseUrl;
    String model = widget.controller.aiModel;
    String apiKey = widget.controller.apiKey;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final requiresKey =
                provider == 'gemini' ||
                provider == 'openai' ||
                provider == 'anthropic' ||
                provider == 'deepseek';
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface.withOpacity(0.92),
                      border: Border(
                        top: BorderSide(
                          color: Colors.white.withOpacity(0.2),
                          width: 1.5,
                        ),
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.4),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Icon(
                              Icons.auto_awesome_rounded,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              context.t('Configure Universal AI'),
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          context.t('Set up any AI provider to generate flashcards and slides instantly.'),
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 20),
                        DropdownButtonFormField<String>(
                          value: provider,
                          decoration: InputDecoration(
                            labelText: context.t('AI Provider'),
                            prefixIcon: const Icon(Icons.hub_outlined),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'gemini', child: Text('Google Gemini')),
                            DropdownMenuItem(value: 'openai', child: Text('OpenAI')),
                            DropdownMenuItem(value: 'deepseek', child: Text('DeepSeek')),
                            DropdownMenuItem(value: 'anthropic', child: Text('Anthropic Claude')),
                            DropdownMenuItem(value: 'ollama_custom', child: Text('Ollama / Custom (OpenAI-compatible)')),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setModalState(() {
                                provider = val;
                              });
                            }
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          initialValue: model,
                          decoration: InputDecoration(
                            labelText: context.t('Model ID'),
                            hintText: widget.controller.defaultModelForProvider(provider),
                            prefixIcon: const Icon(Icons.memory_rounded),
                          ),
                          onChanged: (val) => model = val,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          initialValue: baseUrl,
                          decoration: InputDecoration(
                            labelText: context.t('Base URL (optional override)'),
                            hintText: widget.controller.defaultBaseUrlForProvider(provider),
                            prefixIcon: const Icon(Icons.link_rounded),
                          ),
                          onChanged: (val) => baseUrl = val,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          initialValue: apiKey,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: context.t('API Key / Token'),
                            prefixIcon: const Icon(Icons.key_rounded),
                            helperText: requiresKey
                                ? context.t('Required for this provider')
                                : context.t('Optional for local/custom providers'),
                          ),
                          onChanged: (val) => apiKey = val,
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text(context.t('Cancel')),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  gradient: LinearGradient(
                                    colors: [
                                      Theme.of(context).colorScheme.primary,
                                      Theme.of(context).colorScheme.primary.withOpacity(0.85),
                                    ],
                                  ),
                                ),
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    foregroundColor: Colors.white,
                                    shadowColor: Colors.transparent,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: () {
                                    widget.controller.setAiProvider(provider);
                                    widget.controller.setAiBaseUrl(baseUrl);
                                    widget.controller.setAiModel(model);
                                    widget.controller.setApiKey(apiKey);
                                    Navigator.pop(context);
                                    onConfiguredAndGenerate();
                                  },
                                  child: Text(context.t('Save & Generate')),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _nextFlashcard() {
    final file = widget.controller.selectedFile;
    final cards = file == null
        ? const <GeneratedFlashcard>[]
        : _flashcardsFromFile(file);
    if (cards.isEmpty) {
      return;
    }
    setState(() {
      _flashcardIndex = (_flashcardIndex + 1) % cards.length;
      _showFlashAnswer = false;
    });
  }

  void _previousFlashcard() {
    final file = widget.controller.selectedFile;
    final cards = file == null
        ? const <GeneratedFlashcard>[]
        : _flashcardsFromFile(file);
    if (cards.isEmpty) {
      return;
    }
    setState(() {
      _flashcardIndex = (_flashcardIndex - 1 + cards.length) % cards.length;
      _showFlashAnswer = false;
    });
  }

  Future<void> _runAutoSummary() async {
    final file = widget.controller.selectedFile;
    if (file == null || !file.autoSummaryEnabled || _isSummarizing) {
      return;
    }
    if (_hasPendingChanges.value || _isSaving.value) {
      _scheduleAutoSummary();
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

  Future<void> _restructureWithGemini() async {
    final file = widget.controller.selectedFile;
    final quillController = _quillController;
    if (file == null || quillController == null || _isRestructuring) {
      return;
    }
    final noteText = _currentNotePlainText().trim();
    if (noteText.isEmpty) {
      _showMessage('Write notes first, then restructure.');
      return;
    }
    if (widget.controller.selectedAiProviderNeedsApiKey) {
      _showAiConfigBottomSheet(_restructureWithGemini);
      return;
    }
    final backup = _RestructureBackup(
      title: _titleController.text,
      description: _descriptionController.text,
      quickNote: _quickNoteController.text,
      contentJson: _contentJsonForPersistence(quillController),
    );
    setState(() => _isRestructuring = true);
    try {
      final structured = await _geminiService.restructureNote(
        apiKey: widget.controller.apiKey,
        title: file.title,
        noteText: noteText,
        provider: widget.controller.aiProvider,
        baseUrl: widget.controller.aiBaseUrl,
        model: widget.controller.aiModel,
      );
      final nextDelta = _deltaFromStructuredNote(structured);
      if (nextDelta.isEmpty) {
        throw const GeminiException('Gemini returned an empty structure.');
      }
      _lastRestructureBackup = backup;
      _titleController.text = structured.title.trim().isEmpty
          ? _titleController.text
          : structured.title.trim();
      _replaceDocumentJson(nextDelta);
      await _saveNow();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Restructured note. Original is kept for restore.',
          ),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Restore',
            onPressed: _restoreRestructureBackup,
          ),
        ),
      );
    } catch (error) {
      _titleController.text = backup.title;
      _descriptionController.text = backup.description;
      _quickNoteController.text = backup.quickNote;
      final decoded = jsonDecode(backup.contentJson);
      if (decoded is List) {
        _replaceDocumentJson(decoded.cast<Map<String, dynamic>>());
      }
      _showMessage('Restructure failed. Original note was kept. $error');
    } finally {
      if (mounted) {
        setState(() => _isRestructuring = false);
      }
    }
  }

  Future<void> _restoreRestructureBackup() async {
    final backup = _lastRestructureBackup;
    if (backup == null) {
      _showMessage('No restructure backup available.');
      return;
    }
    _titleController.text = backup.title;
    _descriptionController.text = backup.description;
    _quickNoteController.text = backup.quickNote;
    final decoded = jsonDecode(backup.contentJson);
    if (decoded is List) {
      _replaceDocumentJson(decoded.cast<Map<String, dynamic>>());
      await _saveNow();
      _showMessage('Restored original note.');
    }
  }

  List<Map<String, dynamic>> _deltaFromStructuredNote(StructuredNote note) {
    final ops = <Map<String, dynamic>>[];

    void addText(String text) {
      final clean = text.trim();
      if (clean.isNotEmpty) {
        ops.add({'insert': '$clean\n'});
      }
    }

    void addHeading(String text, int level) {
      final clean = text.trim();
      if (clean.isNotEmpty) {
        ops.add({'insert': clean});
        ops.add({
          'insert': '\n',
          'attributes': {'header': level},
        });
      }
    }

    void addSection(StructuredSection section, int level) {
      addHeading(section.heading, level);
      for (final line in section.body) {
        addText(line);
      }
      for (final subsection in section.subsections) {
        addSection(subsection, math.min(level + 1, 3));
      }
    }

    for (final section in note.sections) {
      addSection(section, 1);
    }
    if (ops.isEmpty || ops.last['insert'] != '\n') {
      ops.add({'insert': '\n'});
    }
    return ops;
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
      _isSaving.value = true;
    }
    final contentJson = _contentJsonForPersistence(quillController);
    await widget.controller.saveFileDraft(
      file.copyWith(
        title: _titleController.text.trim().isEmpty
            ? 'Untitled lecture'
            : _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        quickNote: _quickNoteController.text.trim(),
        contentJson: contentJson,
      ),
      notify: false,
    );

    if (!silent && mounted) {
      _isSaving.value = false;
      _hasPendingChanges.value = false;
      return;
    }

    _isSaving.value = false;
    _hasPendingChanges.value = false;
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.controller.selectedFile;
    final quillController = _quillController;
    if (file == null || quillController == null) {
      return EmptyState(
        icon: Icons.edit_note_rounded,
        title: context.t('Choose or create a lecture file'),
        actionLabel: context.t('New file'),
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
                Row(
                  children: [
                    if (widget.controller.selectedFileId != null) ...[
                      Tooltip(
                        message: context.t('Back to Library'),
                        child: _LiquidGlass(
                          borderRadius: 12,
                          padding: EdgeInsets.zero,
                          blur: 8,
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              iconSize: 22,
                              onPressed: widget.controller.deselectFile,
                              icon: const Icon(Icons.arrow_back_ios_new_rounded),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: TextField(
                        controller: _titleController,
                        onChanged: (_) => _scheduleSave(),
                        style: Theme.of(context).textTheme.titleLarge,
                        decoration: InputDecoration(
                          hintText: context.t('Untitled lecture'),
                          prefixIcon: const Icon(Icons.title_rounded),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ValueListenableBuilder<bool>(
                        valueListenable: _isSaving,
                        builder: (context, isSavingValue, child) {
                          return ValueListenableBuilder<bool>(
                            valueListenable: _hasPendingChanges,
                            builder: (context, hasPendingChangesValue, child) {
                              return _SaveState(
                                isSaving: isSavingValue,
                                hasPendingChanges: hasPendingChangesValue,
                              );
                            },
                          );
                        },
                      ),
                      const SizedBox(width: 6),
                      _GlassIconButton(
                        tooltip: widget.controller.editorFullscreen
                            ? context.t('Exit fullscreen')
                            : context.t('Fullscreen editor'),
                        selected: widget.controller.editorFullscreen,
                        onPressed: widget.controller.toggleEditorFullscreen,
                        icon: widget.controller.editorFullscreen
                            ? Icons.fullscreen_exit_rounded
                            : Icons.fullscreen_rounded,
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
                            value: EditorSurface.mindMap,
                            icon: Icon(Icons.hub_rounded),
                          ),
                          ButtonSegment(
                            value: EditorSurface.sheet,
                            icon: Icon(Icons.table_chart_rounded),
                          ),
                          ButtonSegment(
                            value: EditorSurface.slides,
                            icon: Icon(Icons.slideshow_rounded),
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
                  title: Text(context.t('Details')),
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
                                    .setAutoSummaryEnabledForSelectedFile(
                                      false,
                                    );
                              }
                              _scheduleSave();
                            },
                            minLines: 2,
                            maxLines: 3,
                            decoration: InputDecoration(
                              labelText: context.t('Description'),
                              prefixIcon: const Icon(Icons.notes_outlined),
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
                            decoration: InputDecoration(
                              labelText: context.t('Doing now'),
                              prefixIcon: const Icon(
                                Icons.sticky_note_2_outlined,
                              ),
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
                                icon: const Icon(Icons.auto_awesome_rounded),
                                label: Text(
                                  _isSummarizing
                                      ? context.t('Summarizing')
                                      : context.t('Summary'),
                                ),
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(context.t('Auto summary')),
                                  ),
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
              showAdvancedTools: widget.controller.showAdvancedTools,
              controller: quillController,
              searchController: _searchController,
              markerColors: _markerColors,
              activeMarkerColor: _activeMarkerColor,
              activeFontSize: _activeFontSize(),
              showFormatToolbar: _showFormatToolbar,
              isRestructuring: _isRestructuring,
              showOutline: _showOutline,
              searchLabel: _searchController.text.trim().isEmpty
                  ? ''
                  : '${_searchOffsets.isEmpty ? 0 : _activeSearchMatch + 1}/${_searchOffsets.length}',
              onHeadingSelected: _applyHeading,
              onHighlight: (_) => _applyActiveMarker(),
              onMarkerColorSelected: _setActiveMarkerColor,
              onFontSizeSelected: _applyFontSize,
              onIncreaseFontSize: () => _stepFontSize(true),
              onDecreaseFontSize: () => _stepFontSize(false),
              onClearHighlight: _clearHighlight,
              onInsertImage: _insertImage,
              onInsertVideo: _insertVideo,
              onInsertDrawing: _insertDrawing,
              onInsertLink: _insertLink,
              onRecordVoice: _recordVoiceNote,
              onImportFile: _importLectureFile,
              onExportFile: _exportLectureFile,
              onRestructure: _restructureWithGemini,
              onRestoreRestructure: _lastRestructureBackup == null
                  ? null
                  : _restoreRestructureBackup,
              onToggleOutline: () =>
                  setState(() => _showOutline = !_showOutline),
              onToggleFormatToolbar: () =>
                  setState(() => _showFormatToolbar = !_showFormatToolbar),
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
                              color: Color(
                                widget.controller.editorPaperColorValue,
                              ),
                              borderRadius: BorderRadius.circular(6),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(
                                    alpha: Theme.of(context).brightness == Brightness.dark ? 0.35 : 0.06,
                                  ),
                                  blurRadius: 24,
                                  spreadRadius: 0,
                                  offset: const Offset(0, 8),
                                ),
                                BoxShadow(
                                  color: Colors.black.withValues(
                                    alpha: Theme.of(context).brightness == Brightness.dark ? 0.20 : 0.03,
                                  ),
                                  blurRadius: 8,
                                  spreadRadius: -2,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
                              child: quill.QuillEditor.basic(
                                controller: quillController,
                                config: quill.QuillEditorConfig(
                                  placeholder: context.t(
                                    'Write the lecture note here...',
                                  ),
                                  padding: EdgeInsets.zero,
                                  embedBuilders: [
                                    ...FlutterQuillEmbeds.defaultEditorBuilders(),
                                    _AudioEmbedBuilder(),
                                  ],
                                  // ignore: experimental_member_use
                                  onKeyPressed: _handleOutlineKeyPressed,
                                  // ignore: experimental_member_use
                                  customLeadingBlockBuilder: _buildFoldLeading,
                                  customStyleBuilder: _foldStyle,
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
                                _applyFoldVisibility();
                              },
                              onJump: _jumpToOffset,
                            ),
                          ),
                      ],
                    )
                  : _surface == EditorSurface.mindMap
                  ? _MindMapWorkspace(
                      rootTitle: file.title.trim().isEmpty
                          ? context.t('Untitled lecture')
                          : _displayLectureTitle(context, file.title),
                      sections: _buildOutlineSections(quillController),
                      onAddBranch: _addMindMapBranch,
                      onJump: (offset) {
                        _jumpToOffset(offset);
                        setState(() => _surface = EditorSurface.note);
                      },
                    )
                  : _surface == EditorSurface.sheet
                  ? _SheetGraphWorkspace(
                      file: file,
                      fastMode: widget.controller.fastMode,
                      onChanged: (json) =>
                          widget.controller.updateSelectedFile(sheetJson: json),
                    )
                  : _surface == EditorSurface.slides
                  ? _SlidesWorkspace(
                      file: file,
                      isGenerating: _isGeneratingWorkspace,
                      onGenerate: () {
                        if (widget.controller.selectedAiProviderNeedsApiKey) {
                          _showAiConfigBottomSheet(_generateSlides);
                        } else {
                          _generateSlides();
                        }
                      },
                      onChanged: (json) => widget.controller.updateSelectedFile(
                        slidesJson: json,
                      ),
                      onExport: _exportSlides,
                    )
                  : _surface == EditorSurface.flashcards
                  ? _FlashcardWorkspace(
                      cards: _flashcardsFromFile(file),
                      index: _flashcardIndex,
                      showAnswer: _showFlashAnswer,
                      isGenerating: _isGeneratingWorkspace,
                      onGenerate: () {
                        if (widget.controller.selectedAiProviderNeedsApiKey) {
                          _showAiConfigBottomSheet(_generateFlashcards);
                        } else {
                          _generateFlashcards();
                        }
                      },
                      onChanged: (json) => widget.controller.updateSelectedFile(
                        flashcardsJson: json,
                      ),
                      onToggleAnswer: () =>
                          setState(() => _showFlashAnswer = !_showFlashAnswer),
                      onPrevious: _previousFlashcard,
                      onNext: _nextFlashcard,
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteActionBar extends StatelessWidget {
  const _NoteActionBar({
    required this.showAdvancedTools,
    required this.controller,
    required this.searchController,
    required this.markerColors,
    required this.activeMarkerColor,
    required this.activeFontSize,
    required this.showFormatToolbar,
    required this.isRestructuring,
    required this.showOutline,
    required this.searchLabel,
    required this.onHeadingSelected,
    required this.onHighlight,
    required this.onMarkerColorSelected,
    required this.onFontSizeSelected,
    required this.onIncreaseFontSize,
    required this.onDecreaseFontSize,
    required this.onClearHighlight,
    required this.onInsertImage,
    required this.onInsertVideo,
    required this.onInsertDrawing,
    required this.onInsertLink,
    required this.onRecordVoice,
    required this.onImportFile,
    required this.onExportFile,
    required this.onRestructure,
    required this.onRestoreRestructure,
    required this.onToggleOutline,
    required this.onToggleFormatToolbar,
    required this.onSearchChanged,
    required this.onSearchSubmitted,
    required this.onPreviousSearch,
    required this.onNextSearch,
  });

  final bool showAdvancedTools;
  final quill.QuillController controller;
  final TextEditingController searchController;
  final List<Color> markerColors;
  final Color activeMarkerColor;
  final String activeFontSize;
  final bool showFormatToolbar;
  final bool isRestructuring;
  final bool showOutline;
  final String searchLabel;
  final ValueChanged<int?> onHeadingSelected;
  final ValueChanged<Color> onHighlight;
  final ValueChanged<Color> onMarkerColorSelected;
  final ValueChanged<String> onFontSizeSelected;
  final VoidCallback onIncreaseFontSize;
  final VoidCallback onDecreaseFontSize;
  final VoidCallback onClearHighlight;
  final VoidCallback onInsertImage;
  final VoidCallback onInsertVideo;
  final VoidCallback onInsertDrawing;
  final VoidCallback onInsertLink;
  final VoidCallback onRecordVoice;
  final VoidCallback onImportFile;
  final VoidCallback onExportFile;
  final VoidCallback onRestructure;
  final VoidCallback? onRestoreRestructure;
  final VoidCallback onToggleOutline;
  final VoidCallback onToggleFormatToolbar;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onSearchSubmitted;
  final VoidCallback? onPreviousSearch;
  final VoidCallback? onNextSearch;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: Theme.of(context).brightness == Brightness.dark
                    ? const [Color(0x1EFFFFFF), Color(0x0AFFFFFF)]
                    : const [Color(0xF0FFFFFF), Color(0xA8FFFFFF)],
              ),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0x22FFFFFF)
                    : const Color(0x55FFFFFF),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: Theme.of(context).brightness == Brightness.dark ? 0.30 : 0.05,
                  ),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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
                          segments: [
                            const ButtonSegment(value: 1, label: Text('H1')),
                            const ButtonSegment(value: 2, label: Text('H2')),
                            ButtonSegment(value: 0, label: Text(context.t('Body'))),
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
                        _MarkerPickerButton(
                          colors: markerColors,
                          activeColor: activeMarkerColor,
                          onPick: onMarkerColorSelected,
                        ),
                        const SizedBox(width: 4),
                        _GlassIconButton(
                          tooltip: context.t('Apply marker'),
                          onPressed: () => onHighlight(activeMarkerColor),
                          icon: Icons.draw_rounded,
                          size: 36,
                          iconSize: 18,
                        ),
                        IconButton(
                          tooltip: context.t('Clear marker'),
                          onPressed: onClearHighlight,
                          icon: const Icon(Icons.format_color_reset_rounded),
                        ),
                        const SizedBox(width: 8),
                        _FontStepButton(
                          tooltip: context.t('Smaller text'),
                          label: 'A-',
                          onPressed: onDecreaseFontSize,
                        ),
                        _FontSizePicker(
                          value: activeFontSize,
                          onSelected: onFontSizeSelected,
                        ),
                        _FontStepButton(
                          tooltip: context.t('Bigger text'),
                          label: 'A+',
                          onPressed: onIncreaseFontSize,
                        ),
                        const SizedBox(width: 8),
                        _GlassIconButton(
                          tooltip: context.t('Insert picture'),
                          onPressed: onInsertImage,
                          icon: Icons.image_outlined,
                          size: 36,
                          iconSize: 18,
                        ),
                        if (showAdvancedTools) ...[
                          _GlassIconButton(
                            tooltip: context.t('Insert video'),
                            onPressed: onInsertVideo,
                            icon: Icons.video_file_outlined,
                            size: 36,
                            iconSize: 18,
                          ),
                          _GlassIconButton(
                            tooltip: context.t('Draw'),
                            onPressed: onInsertDrawing,
                            icon: Icons.gesture_rounded,
                            size: 36,
                            iconSize: 18,
                          ),
                        ],
                        _GlassIconButton(
                          tooltip: context.t('Insert link'),
                          onPressed: onInsertLink,
                          icon: Icons.link_rounded,
                          size: 36,
                          iconSize: 18,
                        ),
                        if (showAdvancedTools) ...[
                          _GlassIconButton(
                            tooltip: context.t('Record voice'),
                            onPressed: onRecordVoice,
                            icon: Icons.mic_rounded,
                            size: 36,
                            iconSize: 18,
                          ),
                          const SizedBox(width: 8),
                          _GlassIconButton(
                            tooltip: context.t(
                              'Import txt, markdown, json, or leccy',
                            ),
                            onPressed: onImportFile,
                            icon: Icons.upload_file_rounded,
                            size: 36,
                            iconSize: 18,
                          ),
                          _GlassIconButton(
                            tooltip: context.t('Export lecture'),
                            onPressed: onExportFile,
                            icon: Icons.download_rounded,
                            size: 36,
                            iconSize: 18,
                          ),
                          const SizedBox(width: 8),
                          FilledButton.tonalIcon(
                            onPressed: isRestructuring ? null : onRestructure,
                            icon: const Icon(Icons.account_tree_rounded, size: 18),
                            label: Text(
                              isRestructuring
                                  ? context.t('Structuring')
                                  : context.t('Restructure'),
                            ),
                          ),
                          if (onRestoreRestructure != null) ...[
                            const SizedBox(width: 4),
                            TextButton.icon(
                              onPressed: onRestoreRestructure,
                              icon: const Icon(Icons.restore_rounded, size: 18),
                              label: Text(context.t('Restore original')),
                            ),
                          ],
                        ],
                        const SizedBox(width: 8),
                    _GlassIconButton(
                      tooltip: showOutline
                          ? context.t('Hide note accordion')
                          : context.t('Show note accordion'),
                      selected: showOutline,
                      onPressed: onToggleOutline,
                      icon: showOutline
                          ? Icons.view_agenda_rounded
                          : Icons.view_agenda_outlined,
                    ),
                    const SizedBox(width: 4),
                    _GlassIconButton(
                      tooltip: showFormatToolbar
                          ? context.t('Hide formatting')
                          : context.t('Show formatting'),
                      selected: showFormatToolbar,
                      onPressed: onToggleFormatToolbar,
                      icon: showFormatToolbar
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.tune_rounded,
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 260,
                      child: TextField(
                        controller: searchController,
                        onChanged: onSearchChanged,
                        onSubmitted: onSearchSubmitted,
                        decoration: InputDecoration(
                          hintText: context.t('Search'),
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixText: searchLabel,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: context.t('Previous match'),
                      onPressed: onPreviousSearch,
                      icon: const Icon(Icons.keyboard_arrow_up_rounded),
                    ),
                    IconButton(
                      tooltip: context.t('Next match'),
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
    ),
  ),
);
  }
}

class _MarkerPickerButton extends StatelessWidget {
  const _MarkerPickerButton({
    required this.colors,
    required this.activeColor,
    required this.onPick,
  });

  final List<Color> colors;
  final Color activeColor;
  final ValueChanged<Color> onPick;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<Color>(
      tooltip: context.t('Marker color'),
      onSelected: onPick,
      itemBuilder: (context) => [
        for (final color in colors)
          PopupMenuItem<Color>(
            value: color,
            child: Row(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '#${(color.toARGB32() & 0x00FFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
                ),
              ],
            ),
          ),
      ],
      child: _LiquidGlass(
        borderRadius: 18,
        blur: 10,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.color_lens_outlined, size: 16),
            const SizedBox(width: 6),
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: activeColor,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more_rounded, size: 16),
          ],
        ),
      ),
    );
  }
}

class _FontSizePicker extends StatelessWidget {
  const _FontSizePicker({required this.value, required this.onSelected});

  final String value;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: context.t('Font size'),
      onSelected: onSelected,
      itemBuilder: (context) => [
        PopupMenuItem(value: 'small', child: Text(context.t('Small'))),
        PopupMenuItem(value: 'normal', child: Text(context.t('Normal'))),
        PopupMenuItem(value: 'large', child: Text(context.t('Large'))),
        PopupMenuItem(value: 'huge', child: Text(context.t('Huge'))),
      ],
      child: _LiquidGlass(
        borderRadius: 18,
        blur: 10,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(switch (value) {
              'small' => context.t('Small'),
              'large' => context.t('Large'),
              'huge' => context.t('Huge'),
              _ => context.t('Normal'),
            }, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more_rounded, size: 16),
          ],
        ),
      ),
    );
  }
}

class _FontStepButton extends StatelessWidget {
  const _FontStepButton({
    required this.tooltip,
    required this.label,
    required this.onPressed,
  });

  final String tooltip;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: _LiquidGlass(
        borderRadius: 18,
        blur: 10,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(18),
          child: Text(label, style: Theme.of(context).textTheme.labelLarge),
        ),
      ),
    );
  }
}

class _LinkDraft {
  const _LinkDraft({required this.url, required this.label});

  final String url;
  final String label;
}

class _RestructureBackup {
  const _RestructureBackup({
    required this.title,
    required this.description,
    required this.quickNote,
    required this.contentJson,
  });

  final String title;
  final String description;
  final String quickNote;
  final String contentJson;
}

class _LinkDialog extends StatefulWidget {
  const _LinkDialog();

  @override
  State<_LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<_LinkDialog> {
  final _urlController = TextEditingController();
  final _labelController = TextEditingController();

  @override
  void dispose() {
    _urlController.dispose();
    _labelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.t('Insert link')),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _urlController,
              decoration: InputDecoration(
                labelText: context.t('URL'),
                hintText: 'https://example.com',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _labelController,
              decoration: InputDecoration(labelText: context.t('Label')),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.t('Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            _LinkDraft(
              url: _urlController.text.trim(),
              label: _labelController.text.trim(),
            ),
          ),
          child: Text(context.t('Insert')),
        ),
      ],
    );
  }
}

class _DrawingResult {
  const _DrawingResult({required this.pngBytes, required this.json});

  final Uint8List pngBytes;
  final List<Map<String, dynamic>> json;
}

class _DrawingDialog extends StatefulWidget {
  const _DrawingDialog();

  @override
  State<_DrawingDialog> createState() => _DrawingDialogState();
}

class _DrawingDialogState extends State<_DrawingDialog> {
  late final drawing.DrawingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = drawing.DrawingController()
      ..setStyle(color: Colors.black, strokeWidth: 4);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _insert() async {
    final image = await _controller.getImageData(
      format: ImageByteFormat.png,
      pixelRatio: 2,
    );
    if (image == null || !mounted) {
      return;
    }
    Navigator.of(context).pop(
      _DrawingResult(
        pngBytes: image.buffer.asUint8List(),
        json: _controller.getJsonList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: 900,
        height: 680,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Text(
                    context.t('Drawing'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(context.t('Cancel')),
                  ),
                  FilledButton(
                    onPressed: _insert,
                    child: Text(context.t('Insert')),
                  ),
                ],
              ),
            ),
            Expanded(
              child: drawing.DrawingBoard(
                controller: _controller,
                background: Container(color: Colors.white),
              ),
            ),
            drawing.DrawingBar(
              controller: _controller,
              tools: [
                drawing.DefaultActionItem.slider(),
                drawing.DefaultActionItem.undo(),
                drawing.DefaultActionItem.redo(),
                drawing.DefaultActionItem.turn(),
                drawing.DefaultActionItem.clear(),
              ],
            ),
            drawing.DrawingBar(
              controller: _controller,
              tools: [
                drawing.DefaultToolItem.pen(),
                drawing.DefaultToolItem.brush(),
                drawing.DefaultToolItem.rectangle(),
                drawing.DefaultToolItem.circle(),
                drawing.DefaultToolItem.straightLine(),
                drawing.DefaultToolItem.eraser(),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _ExportFormat { text, markdown, leccy }

class _ExportDialog extends StatelessWidget {
  const _ExportDialog();

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: Text(context.t('Export lecture')),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.of(context).pop(_ExportFormat.text),
          child: ListTile(
            leading: const Icon(Icons.text_snippet_outlined),
            title: Text(context.t('Plain text (.txt)')),
          ),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.of(context).pop(_ExportFormat.markdown),
          child: ListTile(
            leading: const Icon(Icons.notes_rounded),
            title: Text(context.t('Markdown text (.md)')),
          ),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.of(context).pop(_ExportFormat.leccy),
          child: ListTile(
            leading: const Icon(Icons.inventory_2_outlined),
            title: Text(context.t('Leccy package (.leccy)')),
            subtitle: Text(
              context.t('Includes notes, sheet, slides, and flashcards'),
            ),
          ),
        ),
      ],
    );
  }
}

class _VoiceRecorderDialog extends StatefulWidget {
  const _VoiceRecorderDialog({required this.repository});

  final LeccyStore repository;

  @override
  State<_VoiceRecorderDialog> createState() => _VoiceRecorderDialogState();
}

class _VoiceRecorderDialogState extends State<_VoiceRecorderDialog> {
  final AudioRecorder _recorder = AudioRecorder();
  Timer? _timer;
  bool _isRecording = false;
  bool _isSaving = false;
  Duration _elapsed = Duration.zero;

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final deniedMessage = context.t('Microphone permission was denied.');
    final allowed = await _recorder.hasPermission();
    if (!allowed) {
      _showLocalMessage(deniedMessage);
      return;
    }
    final path = await buildVoiceRecordingPath('wav');
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.wav),
      path: path,
    );
    setState(() {
      _isRecording = true;
      _elapsed = Duration.zero;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _elapsed += const Duration(seconds: 1));
      }
    });
  }

  Future<void> _stopAndInsert() async {
    final noRecordingMessage = context.t('No recording was saved.');
    setState(() => _isSaving = true);
    _timer?.cancel();
    final path = await _recorder.stop();
    if (path == null || path.isEmpty) {
      _showLocalMessage(noRecordingMessage);
      if (mounted) {
        setState(() {
          _isSaving = false;
          _isRecording = false;
        });
      }
      return;
    }
    final storedPath = await persistVoiceRecording(
      repository: widget.repository,
      path: path,
      extension: 'wav',
    );
    if (mounted) {
      Navigator.of(context).pop(storedPath);
    }
  }

  Future<void> _cancel() async {
    _timer?.cancel();
    if (_isRecording) {
      await _recorder.cancel();
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _showLocalMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  String _timeLabel(Duration value) {
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.t('Record voice note')),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isRecording ? Icons.mic_rounded : Icons.mic_none_rounded,
              size: 52,
              color: _isRecording
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              _timeLabel(_elapsed),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              _isRecording
                  ? context.t('Recording. Press Insert when finished.')
                  : context.t('Press Record and allow microphone access.'),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : _cancel,
          child: Text(context.t('Cancel')),
        ),
        if (!_isRecording)
          FilledButton.icon(
            onPressed: _isSaving ? null : _start,
            icon: const Icon(Icons.fiber_manual_record_rounded),
            label: Text(context.t('Record')),
          )
        else
          FilledButton.icon(
            onPressed: _isSaving ? null : _stopAndInsert,
            icon: const Icon(Icons.check_rounded),
            label: Text(_isSaving ? context.t('Saving') : context.t('Insert')),
          ),
      ],
    );
  }
}

class _AudioEmbedBuilder extends quill.EmbedBuilder {
  @override
  String get key => leccyAudioEmbedType;

  @override
  bool get expanded => false;

  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) {
    final data = _AudioEmbedData.fromRaw(embedContext.node.value.data);
    return _AudioEmbedCard(data: data);
  }
}

class _AudioEmbedData {
  const _AudioEmbedData({required this.source, required this.label});

  final String source;
  final String label;

  factory _AudioEmbedData.fromRaw(Object? raw) {
    try {
      final decoded = raw is String ? jsonDecode(raw) : raw;
      if (decoded is Map) {
        return _AudioEmbedData(
          source: decoded['source']?.toString() ?? '',
          label: decoded['label']?.toString() ?? 'Voice note',
        );
      }
    } catch (_) {
      // Fall through to raw string support.
    }
    return _AudioEmbedData(source: raw?.toString() ?? '', label: 'Voice note');
  }
}

class _AudioEmbedCard extends StatefulWidget {
  const _AudioEmbedCard({required this.data});

  final _AudioEmbedData data;

  @override
  State<_AudioEmbedCard> createState() => _AudioEmbedCardState();
}

class _AudioEmbedCardState extends State<_AudioEmbedCard> {
  late final AudioPlayer _player;
  PlayerState _state = PlayerState.stopped;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _player.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() => _state = state);
      }
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_state == PlayerState.playing) {
      await _player.stop();
      return;
    }
    final source = widget.data.source;
    if (source.isEmpty) {
      return;
    }
    if (source.startsWith('data:')) {
      final comma = source.indexOf(',');
      if (comma == -1) {
        return;
      }
      final bytes = base64Decode(source.substring(comma + 1));
      await _player.play(BytesSource(bytes, mimeType: 'audio/wav'));
      return;
    }
    if (source.startsWith('http://') ||
        source.startsWith('https://') ||
        source.startsWith('blob:')) {
      await _player.play(UrlSource(source));
    } else {
      await _player.play(DeviceFileSource(source));
    }
  }

  Future<void> _openExternal() async {
    final source = widget.data.source;
    if (source.isEmpty || source.startsWith('data:')) {
      return;
    }
    final uri = source.startsWith(RegExp(r'[a-zA-Z]+:'))
        ? Uri.tryParse(source)
        : Uri.file(source);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: _LiquidGlass(
        borderRadius: 18,
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            _GlassIconButton(
              tooltip: _state == PlayerState.playing
                  ? context.t('Stop')
                  : context.t('Play'),
              icon: _state == PlayerState.playing
                  ? Icons.stop_rounded
                  : Icons.play_arrow_rounded,
              onPressed: _toggle,
              selected: _state == PlayerState.playing,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.data.label,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(
                    context.t('Voice recording'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: context.t('Open audio file'),
              onPressed: widget.data.source.startsWith('data:')
                  ? null
                  : _openExternal,
              icon: const Icon(Icons.open_in_new_rounded),
            ),
          ],
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
              context.t('Accordion'),
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
                        ? context.t('Text block')
                        : section.level == 1
                        ? context.t('Heading')
                        : context.t('Sub heading'),
                  ),
                  trailing: IconButton(
                    tooltip: context.t('Jump to section'),
                    onPressed: () => onJump(section.offset),
                    icon: const Icon(Icons.arrow_forward_rounded),
                  ),
                  children: [
                    if (section.bodyLines.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            context.t('No text under this heading yet.'),
                          ),
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

class _MindMapNode {
  _MindMapNode({
    required this.title,
    required this.level,
    required this.offset,
    required this.bodyLines,
  });

  final String title;
  final int level;
  final int offset;
  final List<String> bodyLines;
  final List<_MindMapNode> children = [];
}

class _MindMapWorkspace extends StatelessWidget {
  const _MindMapWorkspace({
    required this.rootTitle,
    required this.sections,
    required this.onAddBranch,
    required this.onJump,
  });

  final String rootTitle;
  final List<_OutlineSection> sections;
  final ValueChanged<_MindMapNode> onAddBranch;
  final ValueChanged<int> onJump;

  static const double _nodeWidth = 230;
  static const double _nodeHeight = 96;
  static const double _horizontalGap = 92;
  static const double _verticalGap = 26;
  static const double _margin = 32;

  _MindMapNode _root() {
    final root = _MindMapNode(
      title: rootTitle,
      level: 0,
      offset: 0,
      bodyLines: const [],
    );
    final stack = <_MindMapNode>[root];
    for (final section in sections) {
      final level = section.level <= 0 ? 1 : section.level;
      final node = _MindMapNode(
        title: section.title,
        level: level,
        offset: section.offset,
        bodyLines: section.bodyLines,
      );
      while (stack.length > 1 && stack.last.level >= level) {
        stack.removeLast();
      }
      stack.last.children.add(node);
      stack.add(node);
    }
    return root;
  }

  _MindMapLayout _layout(_MindMapNode root, Size viewport) {
    final positions = <_MindMapNode, Offset>{};
    var nextY = _margin;
    var maxDepth = 0;

    double walk(_MindMapNode node, int depth) {
      maxDepth = math.max(maxDepth, depth);
      late final double y;
      if (node.children.isEmpty) {
        y = nextY;
        nextY += _nodeHeight + _verticalGap;
      } else {
        final childYs = [
          for (final child in node.children) walk(child, depth + 1),
        ];
        y = (childYs.first + childYs.last) / 2;
      }
      positions[node] = Offset(
        _margin + depth * (_nodeWidth + _horizontalGap),
        y,
      );
      return y;
    }

    walk(root, 0);
    return _MindMapLayout(
      root: root,
      positions: positions,
      size: Size(
        math.max(
          viewport.width,
          (_margin * 2) +
              ((maxDepth + 1) * _nodeWidth) +
              (maxDepth * _horizontalGap),
        ),
        math.max(viewport.height, nextY + _margin),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final root = _root();
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = _layout(
          root,
          Size(constraints.maxWidth, constraints.maxHeight),
        );
        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerLowest.withValues(alpha: 0.7),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  left: 14,
                  top: 12,
                  child: _LiquidGlass(
                    borderRadius: 18,
                    blur: 12,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.hub_rounded, size: 16),
                        const SizedBox(width: 6),
                        Text(context.t('Mind map')),
                        const SizedBox(width: 12),
                        Text(
                          context.t('Tap a node to jump to that section.'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                InteractiveViewer(
                  constrained: false,
                  minScale: 0.65,
                  maxScale: 2.4,
                  boundaryMargin: const EdgeInsets.all(280),
                  child: SizedBox(
                    width: layout.size.width,
                    height: layout.size.height,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _MindMapLinesPainter(
                              layout: layout,
                              lineColor: Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.46),
                              nodeWidth: _nodeWidth,
                              nodeHeight: _nodeHeight,
                            ),
                          ),
                        ),
                        for (final entry in layout.positions.entries)
                          Positioned(
                            left: entry.value.dx,
                            top: entry.value.dy,
                            width: _nodeWidth,
                            height: _nodeHeight,
                            child: _MindMapCard(
                              node: entry.key,
                              isRoot: entry.key == root,
                              onAddBranch: () => onAddBranch(entry.key),
                              onTap: () => onJump(entry.key.offset),
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
      },
    );
  }
}

class _MindMapLayout {
  const _MindMapLayout({
    required this.root,
    required this.positions,
    required this.size,
  });

  final _MindMapNode root;
  final Map<_MindMapNode, Offset> positions;
  final Size size;
}

class _MindMapLinesPainter extends CustomPainter {
  const _MindMapLinesPainter({
    required this.layout,
    required this.lineColor,
    required this.nodeWidth,
    required this.nodeHeight,
  });

  final _MindMapLayout layout;
  final Color lineColor;
  final double nodeWidth;
  final double nodeHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    void drawLinks(_MindMapNode node) {
      final from = layout.positions[node];
      if (from == null) {
        return;
      }
      final start = Offset(from.dx + nodeWidth, from.dy + nodeHeight / 2);
      for (final child in node.children) {
        final to = layout.positions[child];
        if (to == null) {
          continue;
        }
        final end = Offset(to.dx, to.dy + nodeHeight / 2);
        final midX = (start.dx + end.dx) / 2;
        final path = Path()
          ..moveTo(start.dx, start.dy)
          ..cubicTo(midX, start.dy, midX, end.dy, end.dx, end.dy);
        canvas.drawPath(path, paint);
        drawLinks(child);
      }
    }

    drawLinks(layout.root);
  }

  @override
  bool shouldRepaint(covariant _MindMapLinesPainter oldDelegate) {
    return oldDelegate.layout != layout ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.nodeWidth != nodeWidth ||
        oldDelegate.nodeHeight != nodeHeight;
  }
}

Future<String?> _showMindMapBranchDialog(BuildContext context) async {
  return showDialog<String>(
    context: context,
    builder: (context) => const _MindMapBranchDialog(),
  );
}

class _MindMapBranchDialog extends StatefulWidget {
  const _MindMapBranchDialog();

  @override
  State<_MindMapBranchDialog> createState() => _MindMapBranchDialogState();
}

class _MindMapBranchDialogState extends State<_MindMapBranchDialog> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.t('New branch')),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: context.t('Branch title'),
          prefixIcon: const Icon(Icons.hub_rounded),
        ),
        onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.t('Cancel')),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          icon: const Icon(Icons.add_rounded),
          label: Text(context.t('Add branch')),
        ),
      ],
    );
  }
}

class _MindMapCard extends StatelessWidget {
  const _MindMapCard({
    required this.node,
    required this.isRoot,
    required this.onAddBranch,
    required this.onTap,
  });

  final _MindMapNode node;
  final bool isRoot;
  final VoidCallback onAddBranch;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = isRoot
        ? scheme.primaryContainer
        : Color.lerp(
            scheme.secondaryContainer,
            scheme.tertiaryContainer,
            (node.level.clamp(1, 4) - 1) / 3,
          )!;
    final subtitle = node.children.isNotEmpty
        ? context.t('{count} branches', {'count': node.children.length})
        : node.bodyLines.isNotEmpty
        ? node.bodyLines.first
        : context.t('No branches yet');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: scheme.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(
                isRoot ? Icons.radio_button_checked_rounded : Icons.circle,
                size: isRoot ? 22 : 12,
                color: scheme.onPrimaryContainer,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      node.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onPrimaryContainer.withValues(
                          alpha: 0.72,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Tooltip(
                message: context.t('Add branch'),
                child: IconButton.filledTonal(
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  onPressed: onAddBranch,
                  icon: const Icon(Icons.add_rounded),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetGraphWorkspace extends StatefulWidget {
  const _SheetGraphWorkspace({
    required this.file,
    required this.fastMode,
    required this.onChanged,
  });

  final LectureFile file;
  final bool fastMode;
  final ValueChanged<String> onChanged;

  @override
  State<_SheetGraphWorkspace> createState() => _SheetGraphWorkspaceState();
}

class _SheetGraphWorkspaceState extends State<_SheetGraphWorkspace> {
  late List<List<String>> rows;
  String chartType = 'bar';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _SheetGraphWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.id != widget.file.id ||
        oldWidget.file.sheetJson != widget.file.sheetJson) {
      _load();
    }
  }

  void _load() {
    try {
      final decoded = jsonDecode(widget.file.sheetJson);
      final rawRows = decoded is Map ? decoded['rows'] : null;
      rows = rawRows is List
          ? rawRows
                .map(
                  (row) => row is List
                      ? row.map((cell) => cell.toString()).toList()
                      : <String>['', '', ''],
                )
                .toList()
          : <List<String>>[];
      chartType = decoded is Map
          ? decoded['chartType']?.toString() ?? 'bar'
          : 'bar';
    } catch (_) {
      rows = <List<String>>[];
      chartType = 'bar';
    }
    if (rows.isEmpty) {
      rows = List.generate(3, (_) => ['', '', '']);
    }
    for (final row in rows) {
      while (row.length < 3) {
        row.add('');
      }
    }
  }

  void _persist() {
    widget.onChanged(
      jsonEncode({
        'columns': ['A', 'B', 'C'],
        'rows': rows,
        'chartType': chartType,
        'labelColumn': 0,
        'valueColumn': 1,
      }),
    );
  }

  double _valueFor(String raw) {
    final value = raw.trim();
    if (!value.startsWith('=')) {
      return double.tryParse(value) ?? 0;
    }
    final expression = value.substring(1);
    final parts = expression.split('+');
    if (parts.length > 1) {
      return parts.fold<double>(0, (sum, part) => sum + _cellValue(part));
    }
    return _cellValue(expression);
  }

  double _cellValue(String ref) {
    final clean = ref.trim().toUpperCase();
    if (clean.length < 2) {
      return double.tryParse(clean) ?? 0;
    }
    final column = clean.codeUnitAt(0) - 'A'.codeUnitAt(0);
    final row = int.tryParse(clean.substring(1));
    if (row == null ||
        row < 1 ||
        row > rows.length ||
        column < 0 ||
        column >= rows[row - 1].length) {
      return double.tryParse(clean) ?? 0;
    }
    return double.tryParse(rows[row - 1][column]) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final graphType = switch (chartType) {
      'line' => _GraphType.line,
      'pie' => _GraphType.pie,
      _ => _GraphType.bar,
    };
    final points = [
      for (var i = 0; i < rows.length; i++)
        _DataPoint(
          rows[i][0].trim().isEmpty ? 'Row ${i + 1}' : rows[i][0],
          _valueFor(rows[i][1]),
        ),
    ];
    final cleanPoints = points.where((point) => point.value > 0).toList();
    final maxY = math.max(
      10,
      cleanPoints.fold<double>(0, (max, point) => math.max(max, point.value)),
    );
    return Row(
      children: [
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text(
                        context.t('Mini sheet'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: context.t('Add row'),
                        onPressed: () {
                          setState(() => rows.add(['', '', '']));
                          _persist();
                        },
                        icon: const Icon(Icons.add_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (context, rowIndex) {
                        return Row(
                          children: [
                            SizedBox(width: 36, child: Text('${rowIndex + 1}')),
                            for (var col = 0; col < 3; col++)
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: TextFormField(
                                    key: ValueKey(
                                      '$rowIndex-$col-${rows[rowIndex][col]}',
                                    ),
                                    initialValue: rows[rowIndex][col],
                                    decoration: InputDecoration(
                                      hintText:
                                          '${String.fromCharCode(65 + col)}${rowIndex + 1}',
                                    ),
                                    onChanged: (value) {
                                      rows[rowIndex][col] = value;
                                      _persist();
                                      setState(() {});
                                    },
                                  ),
                                ),
                              ),
                            IconButton(
                              tooltip: context.t('Delete row'),
                              onPressed: rows.length == 1
                                  ? null
                                  : () {
                                      setState(() => rows.removeAt(rowIndex));
                                      _persist();
                                    },
                              icon: const Icon(Icons.delete_outline_rounded),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text(
                        context.t('Graph'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Spacer(),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: 'bar',
                            icon: Icon(Icons.bar_chart_rounded),
                          ),
                          ButtonSegment(
                            value: 'line',
                            icon: Icon(Icons.show_chart_rounded),
                          ),
                          ButtonSegment(
                            value: 'pie',
                            icon: Icon(Icons.pie_chart_rounded),
                          ),
                        ],
                        selected: {chartType},
                        onSelectionChanged: (value) {
                          setState(() => chartType = value.first);
                          _persist();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: CustomPaint(
                      painter: _GraphPainter(
                        points: cleanPoints,
                        maxY: maxY.toDouble(),
                        color: Theme.of(context).colorScheme.primary,
                        type: graphType,
                        textColor: Theme.of(context).colorScheme.onSurface,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SlidesWorkspace extends StatelessWidget {
  const _SlidesWorkspace({
    required this.file,
    required this.isGenerating,
    required this.onGenerate,
    required this.onChanged,
    required this.onExport,
  });

  final LectureFile file;
  final bool isGenerating;
  final VoidCallback onGenerate;
  final ValueChanged<String> onChanged;
  final VoidCallback onExport;

  List<GeneratedSlide> _slides() {
    try {
      final decoded = jsonDecode(file.slidesJson);
      final slides = decoded is Map ? decoded['slides'] : null;
      if (slides is! List) {
        return const [];
      }
      return slides
          .whereType<Map>()
          .map((item) => GeneratedSlide.fromJson(item.cast<String, Object?>()))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  void _persist(List<GeneratedSlide> slides) {
    onChanged(
      jsonEncode({'slides': slides.map((slide) => slide.toJson()).toList()}),
    );
  }

  @override
  Widget build(BuildContext context) {
    final slides = _slides();
    return Column(
      children: [
        Row(
          children: [
                  FilledButton.icon(
                    onPressed: isGenerating ? null : onGenerate,
                    icon: const Icon(Icons.auto_awesome_rounded),
                    label: Text(
                      isGenerating
                          ? context.t('Generating')
                          : context.t('Generate with AI'),
                    ),
                  ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: onExport,
              icon: const Icon(Icons.ios_share_rounded),
              label: Text(context.t('Export PPTX')),
            ),
            const Spacer(),
            Text(context.slidesCount(slides.length)),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: slides.isEmpty
              ? Center(
                  child: Text(
                    context.t('Generate slides from your note content.'),
                  ),
                )
              : ListView.separated(
                  itemCount: slides.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final slide = slides[index];
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          children: [
                            TextFormField(
                              initialValue: slide.title,
                              decoration: InputDecoration(
                                labelText: context.t('Slide title'),
                              ),
                              onChanged: (value) {
                                slides[index] = GeneratedSlide(
                                  title: value,
                                  bullets: slide.bullets,
                                  notes: slide.notes,
                                );
                                _persist(slides);
                              },
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              initialValue: slide.bullets.join('\n'),
                              minLines: 3,
                              maxLines: 6,
                              decoration: InputDecoration(
                                labelText: context.t('Bullets, one per line'),
                              ),
                              onChanged: (value) {
                                slides[index] = GeneratedSlide(
                                  title: slide.title,
                                  bullets: value
                                      .split('\n')
                                      .map((line) => line.trim())
                                      .where((line) => line.isNotEmpty)
                                      .toList(),
                                  notes: slide.notes,
                                );
                                _persist(slides);
                              },
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

class _FlashcardWorkspace extends StatelessWidget {
  const _FlashcardWorkspace({
    required this.cards,
    required this.index,
    required this.showAnswer,
    required this.isGenerating,
    required this.onGenerate,
    required this.onChanged,
    required this.onToggleAnswer,
    required this.onPrevious,
    required this.onNext,
  });

  final List<GeneratedFlashcard> cards;
  final int index;
  final bool showAnswer;
  final bool isGenerating;
  final VoidCallback onGenerate;
  final ValueChanged<String> onChanged;
  final VoidCallback onToggleAnswer;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final safeIndex = cards.isEmpty ? 0 : index.clamp(0, cards.length - 1);
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
                Text(
                  context.t('Flashcards'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                if (cards.isNotEmpty)
                  Chip(
                    label: Text('${safeIndex + 1}/${cards.length}'),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: isGenerating ? null : onGenerate,
                    icon: const Icon(Icons.auto_awesome_rounded),
                    label: Text(
                      isGenerating
                          ? context.t('Generating')
                          : context.t('Generate cards'),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: cards.isEmpty ? null : onPrevious,
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: Text(context.t('Previous')),
                  ),
                  OutlinedButton.icon(
                    onPressed: cards.isEmpty ? null : onNext,
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: Text(context.t('Next')),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: cards.isEmpty
                    ? Center(
                        child: Text(
                          context.t(
                            'Generate flashcards from your note content.',
                          ),
                        ),
                      )
                    : Column(
                        children: [
                          Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: onToggleAnswer,
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(20),
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainer,
                                  border: Border.all(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.outlineVariant,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      showAnswer
                                          ? context.t('Answer')
                                          : context.t('Question'),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.labelLarge,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      showAnswer
                                          ? cards[safeIndex].answer
                                          : cards[safeIndex].question,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                    const Spacer(),
                                    Text(
                                      context.t('Tap card to flip'),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            initialValue: cards[safeIndex].question,
                            decoration: InputDecoration(
                              labelText: context.t('Question'),
                            ),
                            onChanged: (value) {
                              final next = [...cards];
                              next[safeIndex] = GeneratedFlashcard(
                                question: value,
                                answer: cards[safeIndex].answer,
                                topic: cards[safeIndex].topic,
                              );
                              onChanged(
                                jsonEncode({
                                  'cards': next
                                      .map((card) => card.toJson())
                                      .toList(),
                                }),
                              );
                            },
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            initialValue: cards[safeIndex].answer,
                            decoration: InputDecoration(
                              labelText: context.t('Answer'),
                            ),
                            onChanged: (value) {
                              final next = [...cards];
                              next[safeIndex] = GeneratedFlashcard(
                                question: cards[safeIndex].question,
                                answer: value,
                                topic: cards[safeIndex].topic,
                              );
                              onChanged(
                                jsonEncode({
                                  'cards': next
                                      .map((card) => card.toJson())
                                      .toList(),
                                }),
                              );
                            },
                          ),
                        ],
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum EditorSurface { note, mindMap, sheet, slides, flashcards, table, graph }

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
                    context.t('Tools'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: context.t('Close right panel'),
                  onPressed: () => controller.setRightPaneVisible(false),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              context.t('Study sets'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (controller.studySets.isEmpty)
              Text(
                context.t(
                  'Select multiple files and press the progress button to link them.',
                ),
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
                            tooltip: context.t('Open file'),
                            iconSize: 18,
                            onPressed: () => controller.selectFile(file.id),
                            icon: const Icon(Icons.arrow_forward_rounded),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _displayLectureTitle(context, file.title),
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
                  context.t('Folder progress'),
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
                      ? context.t('Table data')
                      : context.t('Graph from file data'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Spacer(),
                if (widget.mode == EditorSurface.table)
                  IconButton(
                    tooltip: context.t('Add row'),
                    onPressed: () {
                      setState(() {
                        data.add(
                          _DataPoint(
                            '${context.t('Item')} ${data.length + 1}',
                            0,
                          ),
                        );
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
                                decoration: InputDecoration(
                                  hintText: context.t('Label'),
                                ),
                                onChanged: (value) {
                                  data[index] = _DataPoint(
                                    value.trim().isEmpty
                                        ? context.t('Item')
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
                                decoration: InputDecoration(
                                  hintText: context.t('Value'),
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
                              tooltip: context.t('Delete row'),
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
                              _MetricChip(
                                label: context.t('Total'),
                                value: total,
                              ),
                              const SizedBox(width: 8),
                              _MetricChip(label: context.t('Avg'), value: avg),
                              const SizedBox(width: 8),
                              _MetricChip(label: context.t('Max'), value: max),
                              const SizedBox(width: 8),
                              _MetricChip(label: context.t('Min'), value: min),
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
    return _LiquidGlass(
      borderRadius: 12,
      blur: 10,
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
    final fastMode = _FastModeScope.of(context);
    if (fastMode) {
      return ColoredBox(
        color: isDark ? const Color(0xFF070A13) : const Color(0xFFE8DCC8),
      );
    }
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0xFF070A13), Color(0xFF101A2E), Color(0xFF202844)]
              : const [Color(0xFFE8DCC8), Color(0xFFFFF7EA), Color(0xFFD9C6A8)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: -120,
            top: -140,
            child: _Blob(
              size: 360,
              color: isDark ? const Color(0x3347B8FF) : const Color(0x77FFF6E6),
            ),
          ),
          Positioned(
            right: -80,
            top: 120,
            child: _Blob(
              size: 310,
              color: isDark ? const Color(0x3367E5D6) : const Color(0x66D6B98C),
            ),
          ),
          Positioned(
            left: 220,
            bottom: -130,
            child: _Blob(
              size: 340,
              color: isDark ? const Color(0x335894FF) : const Color(0x66F5E4C9),
            ),
          ),
          Positioned(
            right: 120,
            bottom: 120,
            child: _Blob(
              size: 220,
              color: isDark ? const Color(0x224A6EFF) : const Color(0x55B99664),
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
    final fastMode = _FastModeScope.of(context) || this.fastMode;
    return Padding(
      padding: padding,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: fastMode ? 0 : 20,
            sigmaY: fastMode ? 0 : 20,
          ),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? const [Color(0x22FFFFFF), Color(0x08FFFFFF)]
                    : [const Color(0xDDFFFFFF), const Color(0x88FFFFFF)],
              ),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(
                color: isDark
                    ? const Color(0x22FFFFFF)
                    : const Color(0x44FFFFFF),
              ),
              boxShadow: [
                BoxShadow(
                  color: isDark
                      ? const Color(0x44000000)
                      : const Color(0x110E1933),
                  blurRadius: fastMode ? 0 : 32,
                  spreadRadius: 0,
                  offset: const Offset(0, 8),
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

class _LiquidGlass extends StatelessWidget {
  const _LiquidGlass({
    required this.child,
    this.borderRadius = 18,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    this.selected = false,
    this.tint,
    this.blur = 14,
  });

  final Widget child;
  final double borderRadius;
  final EdgeInsets padding;
  final bool selected;
  final Color? tint;
  final double blur;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fastMode = _FastModeScope.of(context);
    final baseTint = tint ?? Theme.of(context).colorScheme.primary;
    final radius = BorderRadius.circular(borderRadius);
    return AnimatedContainer(
      duration: _motionDuration(context, 180),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: isDark
                ? const Color(0x33000000)
                : baseTint.withValues(alpha: selected ? 0.18 : 0.08),
            blurRadius: fastMode
                ? 0
                : selected
                ? 24
                : 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: fastMode ? 0 : blur,
            sigmaY: fastMode ? 0 : blur,
          ),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: selected
                    ? [
                        baseTint.withValues(alpha: isDark ? 0.34 : 0.24),
                        Colors.white.withValues(alpha: isDark ? 0.10 : 0.50),
                      ]
                    : [
                        Colors.white.withValues(alpha: isDark ? 0.13 : 0.62),
                        Colors.white.withValues(alpha: isDark ? 0.05 : 0.24),
                      ],
              ),
              border: Border.all(
                color: selected
                    ? baseTint.withValues(alpha: 0.60)
                    : Colors.white.withValues(alpha: isDark ? 0.16 : 0.58),
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.size = 38,
    this.iconSize = 19,
    this.selected = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: _LiquidGlass(
        selected: selected,
        borderRadius: 12,
        padding: EdgeInsets.zero,
        blur: 12,
        child: SizedBox(
          width: size,
          height: size,
          child: IconButton(
            padding: EdgeInsets.zero,
            iconSize: iconSize,
            onPressed: onPressed,
            icon: Icon(icon),
          ),
        ),
      ),
    );
  }
}

Future<void> _showViewOptions(
  BuildContext context,
  AppController controller,
) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return ListenableBuilder(
        listenable: controller,
        builder: (context, child) => _GlassPanel(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          fastMode: controller.fastMode,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.t('View Options'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(context.t('Layout')),
                    SegmentedButton<bool>(
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
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(context.t('Sort by')),
                    DropdownButton<FolderSortMode>(
                      value: controller.sortMode,
                      onChanged: (mode) =>
                          mode != null ? controller.setSortMode(mode) : null,
                      items: [
                        DropdownMenuItem(
                          value: FolderSortMode.custom,
                          child: Text(context.t('Custom')),
                        ),
                        DropdownMenuItem(
                          value: FolderSortMode.name,
                          child: Text(context.t('Name')),
                        ),
                        DropdownMenuItem(
                          value: FolderSortMode.progress,
                          child: Text(context.t('Progress')),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

void _showSheetMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
  );
}

class _CommandPaletteSelection {
  const _CommandPaletteSelection(this.action, {this.fileId});

  final String action;
  final int? fileId;
}

Future<void> _showCommandPalette(
  BuildContext context,
  AppController controller,
) async {
  final queryController = TextEditingController();
  var query = '';
  final selection = await showDialog<_CommandPaletteSelection>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(context.t('Command Palette')),
          content: SizedBox(
            width: 620,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: queryController,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: context.t('Search notes or run a command'),
                    prefixIcon: const Icon(Icons.search_rounded),
                  ),
                  onChanged: (value) => setState(() => query = value.trim()),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: query.isEmpty
                      ? ListView(
                          shrinkWrap: true,
                          children: [
                            ListTile(
                              leading: const Icon(Icons.note_add_outlined),
                              title: Text(context.t('Create new file')),
                              subtitle: Text(context.t('Shortcut: Ctrl+N')),
                              onTap: () => Navigator.of(
                                dialogContext,
                              ).pop(const _CommandPaletteSelection('new-file')),
                            ),
                            ListTile(
                              leading: const Icon(Icons.upload_file_rounded),
                              title: Text(context.t('Export backup')),
                              onTap: () => Navigator.of(dialogContext).pop(
                                const _CommandPaletteSelection('export-backup'),
                              ),
                            ),
                            ListTile(
                              leading: const Icon(Icons.download_rounded),
                              title: Text(context.t('Import backup')),
                              onTap: () => Navigator.of(dialogContext).pop(
                                const _CommandPaletteSelection('import-backup'),
                              ),
                            ),
                            ListTile(
                              leading: const Icon(Icons.delete_outline_rounded),
                              title: Text(context.t('Open trash')),
                              onTap: () => Navigator.of(dialogContext).pop(
                                const _CommandPaletteSelection('open-trash'),
                              ),
                            ),
                          ],
                        )
                      : FutureBuilder<List<LectureFile>>(
                          future: controller.searchFiles(query),
                          builder: (context, snapshot) {
                            final data = snapshot.data ?? const <LectureFile>[];
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }
                            if (data.isEmpty) {
                              return Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Text(context.t('No matching notes')),
                                ),
                              );
                            }
                            return ListView.builder(
                              shrinkWrap: true,
                              itemCount: data.length,
                              itemBuilder: (context, index) {
                                final file = data[index];
                                return ListTile(
                                  leading: Icon(
                                    file.isImportant
                                        ? Icons.flag_rounded
                                        : Icons.article_outlined,
                                  ),
                                  title: Text(
                                    _displayLectureTitle(context, file.title),
                                  ),
                                  subtitle: Text(
                                    file.description.isEmpty
                                        ? context.t('No description')
                                        : file.description,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onTap: () => Navigator.of(dialogContext).pop(
                                    _CommandPaletteSelection(
                                      'open-file',
                                      fileId: file.id,
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  queryController.dispose();
  if (selection == null) {
    return;
  }
  if (!context.mounted) {
    return;
  }
  switch (selection.action) {
    case 'new-file':
      await controller.createFile();
    case 'export-backup':
      await _exportAppBackup(context, controller);
    case 'import-backup':
      await _importAppBackup(context, controller);
    case 'open-trash':
      await _showTrashSheet(context, controller);
    case 'open-file':
      final fileId = selection.fileId;
      if (fileId != null) {
        await controller.openFileFromGlobalSearch(fileId);
      }
  }
}

Future<void> _showTrashSheet(
  BuildContext context,
  AppController controller,
) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return _GlassPanel(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        fastMode: controller.fastMode,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FutureBuilder<(List<LectureFolder>, List<LectureFile>)>(
            future:
                Future.wait<Object>([
                  controller.loadTrashedFolders(),
                  controller.loadTrashedFiles(),
                ]).then(
                  (value) => (
                    value[0] as List<LectureFolder>,
                    value[1] as List<LectureFile>,
                  ),
                ),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const SizedBox(
                  height: 220,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final (folders, files) = snapshot.data!;
              return SizedBox(
                height: 420,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.t('Trash'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 10),
                    if (folders.isEmpty && files.isEmpty)
                      Expanded(
                        child: Center(child: Text(context.t('Trash is empty'))),
                      )
                    else
                      Expanded(
                        child: ListView(
                          children: [
                            for (final folder in folders)
                              ListTile(
                                leading: const Icon(
                                  Icons.folder_delete_outlined,
                                ),
                                title: Text(folder.name),
                                subtitle: Text(context.t('Folder')),
                                trailing: Wrap(
                                  spacing: 8,
                                  children: [
                                    IconButton(
                                      tooltip: context.t('Restore'),
                                      onPressed: () async {
                                        await controller.restoreFolderFromTrash(
                                          folder.id,
                                        );
                                        if (context.mounted) {
                                          Navigator.of(context).pop();
                                          await _showTrashSheet(
                                            context,
                                            controller,
                                          );
                                        }
                                      },
                                      icon: const Icon(Icons.restore_rounded),
                                    ),
                                    IconButton(
                                      tooltip: context.t('Delete forever'),
                                      onPressed: () async {
                                        await controller
                                            .permanentlyDeleteFolder(folder.id);
                                        if (context.mounted) {
                                          Navigator.of(context).pop();
                                          await _showTrashSheet(
                                            context,
                                            controller,
                                          );
                                        }
                                      },
                                      icon: const Icon(Icons.delete_forever),
                                    ),
                                  ],
                                ),
                              ),
                            for (final file in files)
                              ListTile(
                                leading: const Icon(Icons.description_outlined),
                                title: Text(
                                  _displayLectureTitle(context, file.title),
                                ),
                                subtitle: Text(context.t('File')),
                                trailing: Wrap(
                                  spacing: 8,
                                  children: [
                                    IconButton(
                                      tooltip: context.t('Restore'),
                                      onPressed: () async {
                                        await controller.restoreFileFromTrash(
                                          file.id,
                                        );
                                        if (context.mounted) {
                                          Navigator.of(context).pop();
                                          await _showTrashSheet(
                                            context,
                                            controller,
                                          );
                                        }
                                      },
                                      icon: const Icon(Icons.restore_rounded),
                                    ),
                                    IconButton(
                                      tooltip: context.t('Delete forever'),
                                      onPressed: () async {
                                        await controller.permanentlyDeleteFile(
                                          file.id,
                                        );
                                        if (context.mounted) {
                                          Navigator.of(context).pop();
                                          await _showTrashSheet(
                                            context,
                                            controller,
                                          );
                                        }
                                      },
                                      icon: const Icon(Icons.delete_forever),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      );
    },
  );
}

Future<void> _exportAppBackup(
  BuildContext context,
  AppController controller,
) async {
  try {
    final bytes = await controller.exportBackupBytes();
    final stamp = intl.DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final path = await FilePicker.saveFile(
      dialogTitle: 'Export backup',
      fileName: 'leccy_backup_$stamp.leccy',
      type: FileType.custom,
      allowedExtensions: const ['leccy', 'txt'],
      bytes: bytes,
    );
    if (!context.mounted) {
      return;
    }
    if (path != null) {
      _showSheetMessage(
        context,
        context.t('Backup exported: {path}', {'path': path}),
      );
    }
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    _showSheetMessage(
      context,
      context.t('Backup export failed: {error}', {'error': error}),
    );
  }
}

Future<void> _importAppBackup(
  BuildContext context,
  AppController controller,
) async {
  final picked = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['leccy', 'txt', 'json'],
    withData: true,
  );
  final file = picked?.files.single;
  final bytes = file?.bytes;
  if (file == null || bytes == null) {
    return;
  }
  LeccyBackupBundle backup;
  try {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      throw const FormatException('Backup file must contain a JSON object.');
    }
    backup = LeccyBackupBundle.fromJson(
      decoded.map((key, value) => MapEntry(key.toString(), value as Object?)),
    );
  } catch (error) {
    if (context.mounted) {
      _showSheetMessage(
        context,
        context.t('Invalid backup file: {error}', {'error': error}),
      );
    }
    return;
  }
  if (!context.mounted) {
    return;
  }
  final mode = await _showBackupImportModeDialog(context, backup);
  if (!context.mounted) {
    return;
  }
  if (mode == null) {
    return;
  }
  try {
    await controller.importBackupBytes(bytes, mode: mode);
    if (!context.mounted) {
      return;
    }
    _showSheetMessage(
      context,
      context.t('Backup imported: {name}', {'name': file.name}),
    );
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    _showSheetMessage(
      context,
      context.t('Backup import failed: {error}', {'error': error}),
    );
  }
}

Future<BackupImportMode?> _showBackupImportModeDialog(
  BuildContext context,
  LeccyBackupBundle backup,
) {
  return showDialog<BackupImportMode>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.t('Import backup')),
      content: Text(
        context.backupContents(
          folders: backup.folders.length,
          files: backup.files.length,
          studySets: backup.studySets.length,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.t('Cancel')),
        ),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(BackupImportMode.merge),
          child: Text(context.t('Merge as new')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(BackupImportMode.replace),
          child: Text(context.t('Replace all')),
        ),
      ],
    ),
  );
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
                      Expanded(child: Text(context.t('Fast mode'))),
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
                      Expanded(child: Text(context.t('Theme'))),
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
                      Expanded(child: Text(context.t('App font'))),
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
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.translate_rounded),
                      const SizedBox(width: 10),
                      Expanded(child: Text(context.t('Language'))),
                      SegmentedButton<AppLanguage>(
                        segments: [
                          ButtonSegment(
                            value: AppLanguage.en,
                            label: Text(context.t('English')),
                          ),
                          ButtonSegment(
                            value: AppLanguage.th,
                            label: Text(context.t('Thai')),
                          ),
                        ],
                        selected: {controller.language},
                        onSelectionChanged: (value) =>
                            controller.setLanguage(value.first),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ExpansionTile(
                    leading: const Icon(Icons.palette_outlined),
                    title: Text(context.t('Accent color')),
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
                    title: Text(context.t('Editor paper color')),
                    subtitle: Text(
                      '#${(controller.editorPaperColorValue & 0x00FFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                        child: _AnyColorPicker(
                          value: Color(controller.editorPaperColorValue),
                          onChanged: (color) => controller
                              .setEditorPaperColorValue(color.toARGB32()),
                        ),
                      ),
                    ],
                  ),
                  ExpansionTile(
                    leading: const Icon(Icons.auto_awesome_rounded),
                    title: Text(context.t('AI Settings')),
                    subtitle: Text(
                      '${controller.aiProviderDisplayName()} - ${controller.resolvedAiModel()}',
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                        child: Column(
                          children: [
                            DropdownButtonFormField<String>(
                              value: controller.aiProvider,
                              decoration: InputDecoration(
                                labelText: context.t('AI Provider'),
                                prefixIcon: const Icon(Icons.hub_outlined),
                              ),
                              items: const [
                                DropdownMenuItem(value: 'gemini', child: Text('Google Gemini')),
                                DropdownMenuItem(value: 'openai', child: Text('OpenAI')),
                                DropdownMenuItem(value: 'anthropic', child: Text('Anthropic Claude')),
                                DropdownMenuItem(value: 'deepseek', child: Text('DeepSeek')),
                                DropdownMenuItem(value: 'ollama_custom', child: Text('Ollama / Custom (OpenAI-compatible)')),
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  controller.setAiProvider(value);
                                }
                              },
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              initialValue: controller.aiModel,
                              onChanged: controller.setAiModel,
                              decoration: InputDecoration(
                                labelText: context.t('Model ID'),
                                hintText: controller.defaultModelForProvider(),
                                prefixIcon: const Icon(Icons.memory_rounded),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              initialValue: controller.aiBaseUrl,
                              onChanged: controller.setAiBaseUrl,
                              decoration: InputDecoration(
                                labelText: context.t('Base URL (optional override)'),
                                hintText: controller.defaultBaseUrlForProvider(),
                                prefixIcon: const Icon(Icons.link_rounded),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              initialValue: controller.apiKey,
                              obscureText: true,
                              onChanged: controller.setApiKey,
                              decoration: InputDecoration(
                                labelText: context.t('API Key / Token'),
                                helperText: controller.selectedAiProviderRequiresApiKey
                                    ? context.t('Required for this provider')
                                    : context.t('Optional for local/custom providers'),
                                prefixIcon: const Icon(Icons.vpn_key_outlined),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  ExpansionTile(
                    leading: const Icon(Icons.backup_rounded),
                    title: Text(context.t('Backup & restore')),
                    subtitle: Text(
                      controller.lastBackupAt == null
                          ? context.t('Export or import a .leccy/.txt backup')
                          : context.lastBackup(
                              controller.lastBackupAt!,
                              intl.DateFormat(
                                'yyyy-MM-dd HH:mm',
                              ).format(controller.lastBackupAt!),
                            ),
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: FilledButton.tonalIcon(
                                onPressed: () =>
                                    _exportAppBackup(context, controller),
                                icon: const Icon(Icons.upload_file_rounded),
                                label: Text(context.t('Export backup')),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton.tonalIcon(
                                onPressed: () =>
                                    _importAppBackup(context, controller),
                                icon: const Icon(Icons.download_rounded),
                                label: Text(context.t('Import backup')),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  ExpansionTile(
                    leading: const Icon(Icons.tune_rounded),
                    title: Text(context.t('Advanced Options')),
                    subtitle: Text(
                      controller.showAdvancedTools
                          ? context.t('Show all formatting & power-user features')
                          : context.t('Minimal and clean mode'),
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Row(
                          children: [
                            const Icon(Icons.build_outlined, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(context.t('Show Advanced Editing Tools')),
                            ),
                            Switch(
                              value: controller.showAdvancedTools,
                              onChanged: controller.setShowAdvancedTools,
                            ),
                          ],
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
                        Expanded(
                          child: Text(
                            context.t('Want more customization? Go here'),
                          ),
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
                          child: Text(context.t('Open')),
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
          label: context.t('Hue'),
          onChanged: (value) => _update(hsv.withHue(value)),
        ),
        Slider(
          value: hsv.saturation,
          min: 0,
          max: 1,
          label: context.t('Saturation'),
          onChanged: (value) => _update(hsv.withSaturation(value)),
        ),
        Slider(
          value: hsv.value,
          min: 0,
          max: 1,
          label: context.t('Brightness'),
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
      message: context.progressPercent(percent),
      child: _LiquidGlass(
        borderRadius: 18,
        blur: 10,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.flag_rounded, size: 16),
            const SizedBox(width: 6),
            Text('$percent%'),
          ],
        ),
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
        ? context.t('Saving')
        : hasPendingChanges
        ? context.t('Unsaved')
        : context.t('Saved');
    final icon = isSaving
        ? Icons.sync_rounded
        : hasPendingChanges
        ? Icons.pending_outlined
        : Icons.check_circle_outline_rounded;
    return _LiquidGlass(
      borderRadius: 18,
      blur: 10,
      selected: hasPendingChanges || isSaving,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 16), const SizedBox(width: 6), Text(text)],
      ),
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
      title: Text(
        widget.folder == null
            ? context.t('New folder')
            : context.t('Customize folder'),
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              decoration: InputDecoration(labelText: context.t('Folder name')),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _badgeController,
              maxLength: 3,
              decoration: InputDecoration(
                labelText: context.t('Emoji or letters'),
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
                  label: Text(
                    _isSavingImage
                        ? context.t('Saving')
                        : context.t('Cover image'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: context.t('Remove cover image'),
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
        if (widget.folder != null)
          TextButton.icon(
            onPressed: () async {
              await widget.controller.moveFolderToTrash(widget.folder!.id);
              if (context.mounted) {
                Navigator.of(context).pop();
              }
            },
            icon: const Icon(Icons.delete_outline_rounded),
            label: Text(context.t('Move To Trash')),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.t('Cancel')),
        ),
        FilledButton(onPressed: _save, child: Text(context.t('Save'))),
      ],
    );
  }
}
