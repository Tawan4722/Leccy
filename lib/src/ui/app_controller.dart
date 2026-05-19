import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../data/leccy_store.dart';
import '../data/leccy_store_factory.dart'
    if (dart.library.io) '../data/leccy_store_factory_io.dart';
import '../domain/backup_models.dart';
import '../domain/models.dart';
import '../domain/summary_service.dart';

final appControllerProvider = ChangeNotifierProvider<AppController>((ref) {
  final controller = AppController();
  controller.load();
  return controller;
});

enum FolderSortMode { custom, name, progress }

enum AppThemeMode { light, dark }

enum AppFontPreset { workSans, nunito, sourceSerif, lato }

enum AppLanguage { en, th }

class AppController extends ChangeNotifier {
  AppController({LeccyStore? repository, SummaryService? summaryService})
    : _repository = repository,
      _summaryService = summaryService ?? SummaryService();

  LeccyStore? _repository;
  final SummaryService _summaryService;

  bool isLoading = true;
  bool isGrid = true;
  String searchQuery = '';
  String? errorMessage;
  FolderSortMode sortMode = FolderSortMode.custom;
  AppThemeMode themeMode = AppThemeMode.light;
  AppFontPreset fontPreset = AppFontPreset.workSans;
  AppLanguage language = AppLanguage.en;
  bool fastMode = true;
  int accentColorValue = const Color(0xFFE8DCC8).toARGB32();
  int editorPaperColorValue = const Color(0xFFFFFBF4).toARGB32();
  String apiKey = '';
  bool showLeftPane = true;
  bool showRightPane = true;
  bool editorFullscreen = false;
  bool fileSelectionMode = false;
  double leftPaneWidth = 330;
  double rightPaneWidth = 320;
  bool? _fastModeBeforeFullscreen;
  int _folderLoadGeneration = 0;
  DateTime? lastBackupAt;

  static const _themeModeKey = 'theme_mode';
  static const _languageKey = 'language';
  static const _fastModeKey = 'fast_mode';
  static const _fontPresetKey = 'font_preset';
  static const _accentColorKey = 'accent_color';
  static const _editorPaperColorKey = 'editor_paper_color';
  static const _leftPaneKey = 'left_pane_visible';
  static const _rightPaneKey = 'right_pane_visible';
  static const _apiKeyKey = 'api_key';
  static const _lastBackupKey = 'last_backup_at';

  List<LectureFolder> folders = [];
  List<LectureFile> files = [];
  List<StudySet> studySets = [];
  List<StudySetItem> activeStudySetItems = [];
  Map<int, int> fileCounts = {};
  Map<int, int> progressByFolder = {};

  int? selectedFolderId;
  int? selectedFileId;
  int? activeStudySetId;
  final Set<int> selectedFileIds = {};

  LeccyStore get repository {
    final repo = _repository;
    if (repo == null) {
      throw StateError('Repository is not initialized');
    }
    return repo;
  }

  LectureFolder? get selectedFolder {
    return folders.where((folder) => folder.id == selectedFolderId).firstOrNull;
  }

  LectureFile? get selectedFile {
    return files.where((file) => file.id == selectedFileId).firstOrNull;
  }

  StudySet? get activeStudySet {
    return studySets.where((set) => set.id == activeStudySetId).firstOrNull;
  }

  List<LectureFolder> get visibleFolders {
    final query = searchQuery.trim().toLowerCase();
    final filtered = query.isEmpty
        ? [...folders]
        : folders
              .where((folder) => folder.name.toLowerCase().contains(query))
              .toList();
    switch (sortMode) {
      case FolderSortMode.custom:
        filtered.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      case FolderSortMode.name:
        filtered.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      case FolderSortMode.progress:
        filtered.sort(
          (a, b) => (progressByFolder[b.id] ?? 0).compareTo(
            progressByFolder[a.id] ?? 0,
          ),
        );
    }
    return filtered;
  }

  List<LectureFile> get selectedFiles {
    return files.where((file) => selectedFileIds.contains(file.id)).toList();
  }

  Future<void> load() async {
    try {
      isLoading = true;
      errorMessage = null;
      notifyListeners();
      _repository ??= await openLeccyStore();
      await _loadSettings();
      await _loadFolders();
      if (folders.isNotEmpty) {
        selectedFolderId ??= folders.first.id;
        await _loadFolderContent(selectedFolderId!);
      }
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadFolders() async {
    folders = await repository.folders();
    fileCounts = await repository.fileCountsByFolder();
    progressByFolder = await repository.folderProgress();
  }

  Future<void> _loadFolderContent(int folderId) async {
    final generation = ++_folderLoadGeneration;
    final loadedFiles = await repository.filesForFolder(folderId);
    final loadedStudySets = await repository.studySetsForFolder(folderId);
    if (generation != _folderLoadGeneration || folderId != selectedFolderId) {
      return;
    }
    files = loadedFiles;
    studySets = loadedStudySets;
    selectedFileIds.removeWhere(
      (fileId) => !files.any((file) => file.id == fileId),
    );
    if (loadedFiles.isNotEmpty) {
      selectedFileId ??= loadedFiles.first.id;
      if (!loadedFiles.any((file) => file.id == selectedFileId)) {
        selectedFileId = loadedFiles.first.id;
      }
    } else {
      selectedFileId = null;
    }
    if (activeStudySetId != null &&
        !studySets.any((set) => set.id == activeStudySetId)) {
      activeStudySetId = null;
      activeStudySetItems = [];
    }
  }

  Future<void> selectFolder(int folderId) async {
    if (selectedFolderId == folderId) {
      return;
    }
    selectedFolderId = folderId;
    selectedFileId = null;
    activeStudySetId = null;
    selectedFileIds.clear();
    fileSelectionMode = false;
    activeStudySetItems = [];
    notifyListeners();
    await _loadFolderContent(folderId);
    notifyListeners();
  }

  void setSearchQuery(String value) {
    searchQuery = value;
    notifyListeners();
  }

  void setGrid(bool value) {
    isGrid = value;
    notifyListeners();
  }

  void setSortMode(FolderSortMode value) {
    sortMode = value;
    notifyListeners();
  }

  void setThemeMode(AppThemeMode value) {
    themeMode = value;
    unawaited(repository.setSetting(_themeModeKey, value.name));
    notifyListeners();
  }

  void setLanguage(AppLanguage value) {
    language = value;
    unawaited(repository.setSetting(_languageKey, value.name));
    notifyListeners();
  }

  void setFastMode(bool value) {
    fastMode = value;
    unawaited(repository.setSetting(_fastModeKey, value.toString()));
    notifyListeners();
  }

  void setFontPreset(AppFontPreset value) {
    fontPreset = value;
    unawaited(repository.setSetting(_fontPresetKey, value.name));
    notifyListeners();
  }

  void setAccentColorValue(int value) {
    accentColorValue = value;
    unawaited(repository.setSetting(_accentColorKey, value.toString()));
    notifyListeners();
  }

  void setEditorPaperColorValue(int value) {
    editorPaperColorValue = value;
    unawaited(repository.setSetting(_editorPaperColorKey, value.toString()));
    notifyListeners();
  }

  bool get hasApiKey => apiKey.trim().isNotEmpty;

  void setApiKey(String value) {
    apiKey = value.trim();
    unawaited(repository.setSetting(_apiKeyKey, apiKey));
    notifyListeners();
  }

  void setLeftPaneVisible(bool value) {
    showLeftPane = value;
    unawaited(repository.setSetting(_leftPaneKey, value.toString()));
    notifyListeners();
  }

  void setRightPaneVisible(bool value) {
    showRightPane = value;
    unawaited(repository.setSetting(_rightPaneKey, value.toString()));
    notifyListeners();
  }

  void resizeLeftPane(double delta) {
    leftPaneWidth = (leftPaneWidth + delta).clamp(240, 520);
    notifyListeners();
  }

  void resizeRightPane(double delta) {
    rightPaneWidth = (rightPaneWidth + delta).clamp(240, 520);
    notifyListeners();
  }

  void toggleEditorFullscreen() {
    editorFullscreen = !editorFullscreen;
    if (editorFullscreen) {
      _fastModeBeforeFullscreen = fastMode;
      fastMode = true;
      showLeftPane = false;
      showRightPane = false;
    } else {
      if (_fastModeBeforeFullscreen != null) {
        fastMode = _fastModeBeforeFullscreen!;
      }
      showLeftPane = true;
      showRightPane = true;
    }
    notifyListeners();
  }

  int get selectedFolderProgress {
    final folderId = selectedFolderId;
    if (folderId == null) {
      return 0;
    }
    return progressByFolder[folderId] ?? 0;
  }

  Future<void> setSelectedFolderProgress(int percent) async {
    final folderId = selectedFolderId;
    if (folderId == null) {
      return;
    }
    final clamped = percent.clamp(0, 100);
    final folderFiles = await repository.filesForFolder(folderId);
    for (final file in folderFiles) {
      await repository.updateFile(file.copyWith(progressPercent: clamped));
    }
    await refreshFolderContent(keepSelection: true);
  }

  Future<void> createFolder({
    required String name,
    required int colorValue,
    required String badge,
    String? coverImagePath,
  }) async {
    final folder = await repository.createFolder(
      name: name.trim().isEmpty ? 'New folder' : name.trim(),
      colorValue: colorValue,
      badge: _cleanBadge(badge),
      coverImagePath: coverImagePath,
    );
    await _loadFolders();
    await selectFolder(folder.id);
  }

  Future<void> updateFolder(LectureFolder folder) async {
    await repository.updateFolder(
      folder.copyWith(badge: _cleanBadge(folder.badge)),
    );
    await _loadFolders();
    notifyListeners();
  }

  Future<void> createFile() async {
    final folderId = selectedFolderId;
    if (folderId == null) {
      return;
    }
    final file = await repository.createFile(folderId);
    await refreshFolderContent();
    selectedFileId = file.id;
    notifyListeners();
  }

  Future<void> updateFile(LectureFile file) async {
    await repository.updateFile(file);
    await refreshFolderContent(keepSelection: true);
  }

  Future<void> saveFileDraft(LectureFile file, {bool notify = true}) async {
    await repository.updateFile(file);

    final now = DateTime.now();
    final updated = file.copyWith(updatedAt: now);
    final index = files.indexWhere((item) => item.id == file.id);
    if (index != -1) {
      files[index] = updated;
      files.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }

    if (notify) {
      notifyListeners();
    }
  }

  Future<void> updateSelectedFile({
    String? title,
    String? description,
    String? quickNote,
    String? contentJson,
    String? sheetJson,
    String? slidesJson,
    String? flashcardsJson,
    int? progressPercent,
  }) async {
    final file = selectedFile;
    if (file == null) {
      return;
    }
    await updateFile(
      file.copyWith(
        title: title,
        description: description,
        quickNote: quickNote,
        contentJson: contentJson,
        sheetJson: sheetJson,
        slidesJson: slidesJson,
        flashcardsJson: flashcardsJson,
        progressPercent: progressPercent,
      ),
    );
  }

  Future<void> setAutoSummaryEnabledForSelectedFile(bool enabled) async {
    final file = selectedFile;
    if (file == null) {
      return;
    }
    await updateFile(file.copyWith(autoSummaryEnabled: enabled));
  }

  Future<void> generateSummaryForSelectedFile({
    required String noteText,
    bool manual = false,
  }) async {
    final file = selectedFile;
    if (file == null) {
      return;
    }
    final summary = _summaryService.summarize(
      title: file.title,
      noteText: noteText,
      quickNote: file.quickNote,
    );
    if (summary.isEmpty && !manual) {
      return;
    }
    final hash = _summaryService.sourceHash(
      title: file.title,
      noteText: noteText,
      quickNote: file.quickNote,
    );
    await updateFile(
      file.copyWith(
        description: summary,
        summarySourceHash: hash,
        summaryUpdatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> maybeAutoSummarizeSelectedFile({
    required String noteText,
  }) async {
    final file = selectedFile;
    if (file == null || !file.autoSummaryEnabled) {
      return;
    }
    final hash = _summaryService.sourceHash(
      title: file.title,
      noteText: noteText,
      quickNote: file.quickNote,
    );
    if (!_summaryService.shouldAutoSummarize(
      sourceHash: hash,
      previousHash: file.summarySourceHash,
      sourceText: noteText,
    )) {
      return;
    }
    final summary = _summaryService.summarize(
      title: file.title,
      noteText: noteText,
      quickNote: file.quickNote,
    );
    if (summary.isEmpty) {
      return;
    }
    await updateFile(
      file.copyWith(
        description: summary,
        summarySourceHash: hash,
        summaryUpdatedAt: DateTime.now(),
      ),
    );
  }

  String notePlainTextFromContent(String contentJson) {
    return _summaryService.plainTextFromQuillJson(contentJson);
  }

  Future<void> refreshFolderContent({bool keepSelection = false}) async {
    final folderId = selectedFolderId;
    if (folderId == null) {
      return;
    }
    final previousFileId = selectedFileId;
    await _loadFolders();
    await _loadFolderContent(folderId);
    if (keepSelection && files.any((file) => file.id == previousFileId)) {
      selectedFileId = previousFileId;
    }
    notifyListeners();
  }

  void selectFile(int fileId) {
    if (fileSelectionMode) {
      toggleFileSelection(fileId);
      return;
    }
    if (!files.any((file) => file.id == fileId) || selectedFileId == fileId) {
      return;
    }
    selectedFileId = fileId;
    notifyListeners();
  }

  void setFileSelectionMode(bool value) {
    fileSelectionMode = value;
    if (!value) {
      selectedFileIds.clear();
    }
    notifyListeners();
  }

  void toggleFileSelection(int fileId) {
    fileSelectionMode = true;
    if (selectedFileIds.contains(fileId)) {
      selectedFileIds.remove(fileId);
    } else {
      selectedFileIds.add(fileId);
    }
    notifyListeners();
  }

  Future<void> toggleFileImportant(int fileId) async {
    final file = files.where((item) => item.id == fileId).firstOrNull;
    if (file == null) {
      return;
    }
    await updateFile(file.copyWith(isImportant: !file.isImportant));
  }

  Future<void> moveSelectedFileToTrash() async {
    final fileId = selectedFileId;
    if (fileId == null) {
      return;
    }
    await repository.moveFileToTrash(fileId);
    await refreshFolderContent();
  }

  Future<void> moveFileToTrash(int fileId) async {
    await repository.moveFileToTrash(fileId);
    if (selectedFileId == fileId) {
      selectedFileId = null;
    }
    await refreshFolderContent();
  }

  Future<void> moveFolderToTrash(int folderId) async {
    await repository.moveFolderToTrash(folderId);
    await _loadFolders();
    if (selectedFolderId == folderId) {
      selectedFolderId = folders.isEmpty ? null : folders.first.id;
      selectedFileId = null;
      if (selectedFolderId != null) {
        await _loadFolderContent(selectedFolderId!);
      } else {
        files = [];
        studySets = [];
      }
    }
    notifyListeners();
  }

  Future<void> restoreFileFromTrash(int fileId) async {
    await repository.restoreFileFromTrash(fileId);
    await refreshFolderContent(keepSelection: true);
  }

  Future<void> permanentlyDeleteFile(int fileId) async {
    await repository.permanentlyDeleteFile(fileId);
    await refreshFolderContent(keepSelection: true);
  }

  Future<void> restoreFolderFromTrash(int folderId) async {
    await repository.restoreFolderFromTrash(folderId);
    await _loadFolders();
    notifyListeners();
  }

  Future<void> permanentlyDeleteFolder(int folderId) async {
    await repository.permanentlyDeleteFolder(folderId);
    await _loadFolders();
    notifyListeners();
  }

  Future<List<LectureFolder>> loadTrashedFolders() {
    return repository.trashedFolders();
  }

  Future<List<LectureFile>> loadTrashedFiles() {
    return repository.trashedFiles();
  }

  Future<List<LectureFile>> searchFiles(String query) {
    return repository.searchFiles(query);
  }

  Future<void> openFileFromGlobalSearch(int fileId) async {
    final allFolders = await repository.folders();
    for (final folder in allFolders) {
      final folderFiles = await repository.filesForFolder(folder.id);
      if (folderFiles.any((file) => file.id == fileId)) {
        selectedFolderId = folder.id;
        selectedFileId = fileId;
        await _loadFolders();
        await _loadFolderContent(folder.id);
        notifyListeners();
        return;
      }
    }
  }

  Future<void> createStudySetFromSelection() async {
    final folderId = selectedFolderId;
    if (folderId == null || selectedFileIds.isEmpty) {
      return;
    }
    final chosenFiles = selectedFiles;
    final set = await repository.createStudySet(
      folderId: folderId,
      name: 'Progress set ${studySets.length + 1}',
      files: chosenFiles,
    );
    selectedFileIds.clear();
    fileSelectionMode = false;
    await refreshFolderContent(keepSelection: true);
    await selectStudySet(set.id);
  }

  Future<void> selectStudySet(int studySetId) async {
    activeStudySetId = studySetId;
    activeStudySetItems = await repository.studySetItems(studySetId);
    if (activeStudySetItems.isNotEmpty) {
      selectedFileId = activeStudySetItems.first.fileId;
    }
    notifyListeners();
  }

  Future<void> updateStudySetMarker(StudySetItem item, int percent) async {
    await repository.updateStudySetMarker(
      itemId: item.id,
      fileId: item.fileId,
      percent: percent,
    );
    if (activeStudySetId != null) {
      activeStudySetItems = await repository.studySetItems(activeStudySetId!);
    }
    await refreshFolderContent(keepSelection: true);
  }

  Future<Uint8List> exportBackupBytes() async {
    final backup = await repository.exportBackup();
    lastBackupAt = DateTime.now();
    await repository.setSetting(
      _lastBackupKey,
      lastBackupAt!.millisecondsSinceEpoch.toString(),
    );
    return Uint8List.fromList(utf8.encode(backup.toJsonString(pretty: true)));
  }

  Future<void> importBackupBytes(
    Uint8List bytes, {
    required BackupImportMode mode,
  }) async {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      throw const FormatException('Backup file must contain a JSON object.');
    }
    final backup = LeccyBackupBundle.fromJson(
      decoded.map((key, value) => MapEntry(key.toString(), value as Object?)),
    );
    await repository.importBackup(backup, mode: mode);
    lastBackupAt = DateTime.now();
    await repository.setSetting(
      _lastBackupKey,
      lastBackupAt!.millisecondsSinceEpoch.toString(),
    );

    selectedFolderId = null;
    selectedFileId = null;
    activeStudySetId = null;
    activeStudySetItems = [];
    selectedFileIds.clear();
    fileSelectionMode = false;

    await _loadFolders();
    if (folders.isEmpty) {
      files = [];
      studySets = [];
      notifyListeners();
      return;
    }

    selectedFolderId = folders.first.id;
    await _loadFolderContent(selectedFolderId!);
    notifyListeners();
  }

  int studySetProgress(StudySet set) {
    final items = set.id == activeStudySetId
        ? activeStudySetItems
        : <StudySetItem>[];
    if (items.isEmpty) {
      return 0;
    }
    final total = items.fold<int>(0, (sum, item) => sum + item.markerPercent);
    return (total / items.length).round();
  }

  String documentJsonForFile(LectureFile? file) {
    if (file == null) {
      return LectureFile.emptyDocumentJson();
    }
    try {
      jsonDecode(file.contentJson);
      return file.contentJson;
    } catch (_) {
      return LectureFile.emptyDocumentJson();
    }
  }

  String _cleanBadge(String badge) {
    final trimmed = badge.trim();
    if (trimmed.isEmpty) {
      return 'L';
    }
    return trimmed.characters.take(3).toString().toUpperCase();
  }

  Future<void> _loadSettings() async {
    final loadedTheme = await repository.getSetting(_themeModeKey);
    if (loadedTheme == AppThemeMode.dark.name) {
      themeMode = AppThemeMode.dark;
    }
    final loadedLanguage = await repository.getSetting(_languageKey);
    if (loadedLanguage != null) {
      for (final value in AppLanguage.values) {
        if (value.name == loadedLanguage) {
          language = value;
          break;
        }
      }
    }
    final loadedFastMode = await repository.getSetting(_fastModeKey);
    if (loadedFastMode != null) {
      fastMode = loadedFastMode == 'true';
    }
    final loadedFont = await repository.getSetting(_fontPresetKey);
    if (loadedFont != null) {
      for (final preset in AppFontPreset.values) {
        if (preset.name == loadedFont) {
          fontPreset = preset;
          break;
        }
      }
    }
    final loadedAccent = await repository.getSetting(_accentColorKey);
    final parsedAccent = int.tryParse(loadedAccent ?? '');
    if (parsedAccent != null) {
      accentColorValue = parsedAccent;
    }
    final loadedPaper = await repository.getSetting(_editorPaperColorKey);
    final parsedPaper = int.tryParse(loadedPaper ?? '');
    if (parsedPaper != null) {
      editorPaperColorValue = parsedPaper;
    }
    final loadedLeftPane = await repository.getSetting(_leftPaneKey);
    if (loadedLeftPane != null) {
      showLeftPane = loadedLeftPane == 'true';
    }
    final loadedRightPane = await repository.getSetting(_rightPaneKey);
    if (loadedRightPane != null) {
      showRightPane = loadedRightPane == 'true';
    }
    apiKey = (await repository.getSetting(_apiKeyKey)) ?? '';
    final loadedBackupAt = await repository.getSetting(_lastBackupKey);
    final millis = int.tryParse(loadedBackupAt ?? '');
    if (millis != null) {
      lastBackupAt = DateTime.fromMillisecondsSinceEpoch(millis);
    }
  }

  @override
  void dispose() {
    _repository?.close();
    super.dispose();
  }
}
