# Leccy Project Analysis

Generated: 2026-05-14

## Executive Summary

Leccy is a Flutter lecture-organizer application. The project is Windows-first, but it also includes generated Flutter platform folders for Android, iOS, and web. The app lets users organize lecture folders, write rich-text lecture files, keep quick notes/descriptions, track progress, generate simple summaries, save study sets, and view notes through multiple study-oriented surfaces.

The active application code is mostly in `lib/src`, with a clear split between:

- `domain`: plain data models and summary logic.
- `data`: persistence interface plus native SQLite and in-memory implementations.
- `ui`: Riverpod controller and Flutter widgets.

The repository currently contains tests for persistence, summary generation, controller summary behavior, and a small widget check.

## Top-Level Structure

```text
E:/Leccy
├── README.md
├── LICENSE
├── pubspec.yaml
├── pubspec.lock
├── analysis_options.yaml
├── .gitignore
├── .metadata
├── flutter_web.log
├── flutter_web.err.log
├── lib/
├── test/
├── android/
├── ios/
├── web/
└── windows/
```

### Important top-level files

| Path | Purpose |
|---|---|
| `README.md` | Human overview, local Flutter SDK path, run/test/build commands, Windows setup notes. |
| `pubspec.yaml` | Flutter package metadata, SDK constraint, dependencies, dev dependencies. |
| `pubspec.lock` | Locked dependency versions. |
| `analysis_options.yaml` | Uses `package:flutter_lints/flutter.yaml`. |
| `.gitignore` | Standard Flutter/Dart ignores plus `migrate_working_dir/`. |
| `LICENSE` | Project license file. |
| `flutter_web.log`, `flutter_web.err.log` | Runtime logs from web runs; not application source. |

## Technology Stack

- **Framework:** Flutter
- **Language:** Dart
- **State management:** Riverpod / `flutter_riverpod`
- **Desktop persistence:** SQLite through `sqflite_common_ffi`
- **General SQLite package:** `sqflite`
- **Local paths:** `path_provider`, `path`
- **File selection:** `file_picker`
- **Rich text editor:** `flutter_quill`
- **Localization/date formatting:** `flutter_localizations`, `intl`
- **External URL launch:** `url_launcher`
- **Fonts:** `google_fonts`
- **Linting:** `flutter_lints`
- **Testing:** `flutter_test`

`pubspec.yaml` declares Dart SDK `^3.11.5` and app version `1.0.0+1`.

## Run, Analyze, Test, Build Commands

The README says this workspace uses a local Flutter SDK at:

```powershell
E:\flutter_sdk\bin\flutter.bat
```

Useful commands documented by the project:

```powershell
E:\flutter_sdk\bin\flutter.bat analyze
E:\flutter_sdk\bin\flutter.bat test
E:\flutter_sdk\bin\flutter.bat run -d chrome
E:\flutter_sdk\bin\flutter.bat run -d windows
E:\flutter_sdk\bin\flutter.bat build windows
```

Notes from `README.md`:

- Chrome preview uses in-memory storage and resets data when the browser session restarts.
- Windows build uses SQLite persistence.
- Native Windows run/build still requires Windows Developer Mode and Visual Studio with the `Desktop development with C++` workload.

## Source Code Structure

```text
lib
├── main.dart
└── src
    ├── data
    │   ├── app_database.dart
    │   ├── leccy_repository.dart
    │   ├── leccy_store.dart
    │   ├── leccy_store_factory.dart
    │   ├── leccy_store_factory_io.dart
    │   ├── memory_leccy_store.dart
    │   └── native_leccy_store.dart
    ├── domain
    │   ├── models.dart
    │   └── summary_service.dart
    └── ui
        ├── app_controller.dart
        ├── cover_image_provider.dart
        ├── cover_image_provider_io.dart
        └── leccy_app.dart
```

## Application Entry Point

### `lib/main.dart`

`main()` initializes Flutter bindings and starts the app inside a Riverpod `ProviderScope`:

```dart
runApp(const ProviderScope(child: LeccyApp()));
```

The main app widget is `LeccyApp` in `lib/src/ui/leccy_app.dart`.

## Domain Layer

### `lib/src/domain/models.dart`

Defines the core application entities:

| Model | Meaning |
|---|---|
| `LectureFolder` | A folder/category for lecture files. Stores name, color, badge, optional cover image path, and sort order. |
| `LectureFile` | A lecture note file. Stores title, description, Quill document JSON, quick note, progress, update time, and summary metadata. |
| `StudySet` | A saved set of lecture files for progress/study tracking. |
| `StudySetItem` | A file inside a study set with order and marker progress. |

Each model includes map conversion helpers for SQLite/in-memory storage. `LectureFile.emptyDocumentJson()` creates an empty Quill document JSON payload.

### `lib/src/domain/summary_service.dart`

`SummaryService` provides local text-summary behavior without calling an external AI service.

Main responsibilities:

- Generate a source hash from title, note text, and quick note.
- Decide whether auto-summary should run.
- Extract plain text from Flutter Quill JSON.
- Build a short summary by splitting sentences, scoring sentences by repeated terms, taking the top sentences, and truncating preview text.

Important thresholds/constants:

- Maximum summary sentences: `2`
- Minimum words for auto-summary: `40`
- Minimum change threshold: `40`
- Maximum preview characters: `120`

## Data Layer

### `lib/src/data/leccy_store.dart`

Defines the `LeccyStore` interface. It abstracts all persistence operations:

- Folder CRUD/listing
- File creation/update/listing
- Folder file counts and progress
- Study set creation/listing/item marker updates
- Cover image saving
- Store closing

### `lib/src/data/app_database.dart`

Manages native SQLite database creation/opening through `sqflite_common_ffi`.

Database details:

- Database version: `2`
- Default path: application documents directory under `Leccy/leccy.db`
- Enables foreign keys with `PRAGMA foreign_keys = ON`
- Creates four tables:
  - `folders`
  - `lecture_files`
  - `study_sets`
  - `study_set_items`

Version 2 migration adds these columns to `lecture_files`:

- `auto_summary_enabled`
- `summary_source_hash`
- `summary_updated_at`

### `lib/src/data/leccy_repository.dart`

SQLite-backed implementation of `LeccyStore`.

Responsibilities:

- Queries folders ordered by `sort_order` and name.
- Creates folders with the next sort order.
- Creates/updates lecture files.
- Calculates file counts per folder.
- Calculates average folder progress.
- Creates study sets transactionally with their items.
- Updates a study set marker and the linked lecture file progress in one transaction.
- Saves cover images to the application documents directory under `Leccy/covers`.

### `lib/src/data/memory_leccy_store.dart`

In-memory `LeccyStore` implementation. This is used by the default non-IO factory and by tests.

This enables browser/web preview without native SQLite persistence. Data is reset when the runtime restarts.

### `lib/src/data/native_leccy_store.dart`

Wraps `AppDatabase` and exposes it as a `LeccyStore` using `LeccyRepository`.

### Conditional store factories

| File | Purpose |
|---|---|
| `leccy_store_factory.dart` | Default factory; returns `MemoryLeccyStore`. |
| `leccy_store_factory_io.dart` | IO/native override; returns `NativeLeccyStore.open()`. |

`app_controller.dart` imports these conditionally:

```dart
import '../data/leccy_store_factory.dart'
    if (dart.library.io) '../data/leccy_store_factory_io.dart';
```

So native platforms use SQLite, while web-like builds use memory storage.

## UI and State Layer

### `lib/src/ui/app_controller.dart`

`AppController` is a `ChangeNotifier` exposed through Riverpod:

```dart
final appControllerProvider = ChangeNotifierProvider<AppController>((ref) {
  final controller = AppController();
  controller.load();
  return controller;
});
```

It owns most app state and coordinates between UI and persistence.

Key state areas:

- Loading/error state
- Folder list, file list, study sets, active study set items
- Selected folder/file/study set
- Folder search, sort mode, grid/list mode
- Theme mode, font preset, accent color, editor paper color
- Fast mode and glass-effect performance setting
- Pane visibility, pane width, fullscreen editor mode
- API key text state, though the observed summary implementation is local

Key operations:

- Load initial store and folder content.
- Select folders/files/study sets.
- Create/update folders.
- Create/update/save lecture files.
- Update selected file fields.
- Enable/disable auto-summary.
- Generate manual or automatic summaries.
- Create study sets from selected files.
- Update study set progress markers.
- Convert stored Quill JSON to plain note text.

### `lib/src/ui/leccy_app.dart`

This is the largest source file and contains most UI widgets.

Major widgets/classes found in this file:

| Class/enum | Role |
|---|---|
| `LeccyApp` | Builds `MaterialApp`, theme, localization delegates, and app home. |
| `LeccyHomePage` | Main page shell with wallpaper and two-column workspace. |
| `FolderLibrary` | Left folder library panel with search, settings, folder creation, grid/list display. |
| `FolderTile` | Folder card/tile UI. |
| `LectureWorkspace` | Main workspace layout around file list, editor, and progress panel. |
| `FileListPanel` | Displays lecture files in the selected folder and study-set creation action. |
| `FileTile` | File list item with checkbox and progress bar. |
| `NoteEditor` / `_NoteEditorState` | Rich note editor, auto-save, summaries, search, flashcards, surfaces. |
| `_NoteActionBar` | Editor action controls. |
| `_DocumentOutlinePanel` | Outline/navigation UI for document sections. |
| `_FlashcardWorkspace` | Flashcard study UI. |
| `EditorSurface` | Switches between note, table, graph, and flashcard surfaces. |
| `ProgressPanel` | Right-side progress/study panel. |
| `StudySetDetails` | Displays active study set details. |
| `FolderProgressControl` | Folder progress slider/control. |
| `EmptyState` | Reusable empty state UI. |
| `_PaneHandle` | Resizable pane drag handle. |
| `_FileDataWorkspace` | Data/table/graph workspace. |
| `_GraphPainter` | Custom painter for graph rendering. |
| `_LiquidWallpaper`, `_Blob`, `_GlassPanel` | Visual background/glassmorphism effects. |
| `_AnyColorPicker` | Color picker UI. |
| `_ProgressChip` | Small progress chip. |
| `_SaveState` | Save-state indicator UI. |
| `FolderDialog` | Folder creation/customization dialog. |

Observed feature areas in the UI:

- Folder creation and customization.
- Folder badge and optional cover image support.
- Folder search, sorting, grid/list display.
- Lecture file creation, selection, multi-selection.
- Rich text editing through Flutter Quill.
- Quick note and description fields.
- Manual and automatic local summaries.
- Editor fullscreen mode.
- Toggleable/resizable side panes.
- Theme, font, color, fast mode, and layout settings.
- Study/progress sets from selected files.
- Progress tracking by folder/file/study set item.
- Flashcard-oriented workspace.
- Table/graph-oriented data workspace.

### Cover image providers

| File | Behavior |
|---|---|
| `cover_image_provider.dart` | Default provider uses `NetworkImage(path)`. This supports data URLs from the in-memory store. |
| `cover_image_provider_io.dart` | IO/native provider uses `FileImage(File(path))`. This supports cover images saved to disk. |

## Platform Folders

### `windows/`

Flutter Windows desktop runner and CMake files. This is the primary native target according to the README.

Notable files:

- `windows/CMakeLists.txt`
- `windows/flutter/generated_plugin_registrant.cc`
- `windows/runner/main.cpp`
- `windows/runner/flutter_window.cpp`
- `windows/runner/resources/app_icon.ico`

### `web/`

Flutter web shell and icons.

Notable files:

- `web/index.html`
- `web/manifest.json`
- `web/favicon.png`
- `web/icons/*`

### `android/`

Generated Flutter Android project with Gradle/Kotlin configuration. The working tree also contains generated/build-related Android files.

Notable files/directories:

- `android/app/build.gradle.kts`
- `android/build.gradle.kts`
- `android/settings.gradle.kts`
- `android/gradle/wrapper/*`
- `android/.gradle/*`

### `ios/`

Generated Flutter iOS project.

Notable files/directories:

- `ios/Runner/AppDelegate.swift`
- `ios/Runner/Info.plist`
- `ios/Runner.xcodeproj/*`
- `ios/Runner.xcworkspace/*`
- `ios/Flutter/*`

## Tests

```text
test
├── controller_summary_test.dart
├── repository_test.dart
├── summary_service_test.dart
└── widget_test.dart
```

### Test coverage by file

| Test file | Coverage |
|---|---|
| `test/repository_test.dart` | SQLite repository folder/file creation, metadata updates, counts, folder progress, study set creation, marker updates. |
| `test/summary_service_test.dart` | Summary generation, Quill JSON plain text extraction, unchanged-hash auto-summary skip. |
| `test/controller_summary_test.dart` | Manual summary metadata, no-op auto summary when disabled, unchanged-source auto summary skip. |
| `test/widget_test.dart` | Folder library renders a created folder and actions. |

The tests use `flutter_test`, in-memory SQLite via `sqflite_common_ffi`, and `MemoryLeccyStore` for controller-level behavior.

## Data Model / Database Schema

### `folders`

| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER PRIMARY KEY AUTOINCREMENT | Folder ID. |
| `name` | TEXT NOT NULL | Folder name. |
| `color_value` | INTEGER NOT NULL | ARGB color integer. |
| `badge` | TEXT NOT NULL | Folder badge text. |
| `cover_image_path` | TEXT | Optional native path or web/data image source. |
| `sort_order` | INTEGER NOT NULL DEFAULT 0 | Manual/custom ordering. |

### `lecture_files`

| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER PRIMARY KEY AUTOINCREMENT | File ID. |
| `folder_id` | INTEGER NOT NULL | References `folders(id)` with cascade delete. |
| `title` | TEXT NOT NULL | Lecture title. |
| `description` | TEXT NOT NULL DEFAULT '' | Description or generated summary. |
| `content_json` | TEXT NOT NULL | Flutter Quill document JSON. |
| `quick_note` | TEXT NOT NULL DEFAULT '' | Short note. |
| `progress_percent` | INTEGER NOT NULL DEFAULT 0 | File progress, clamped 0-100 in model/repository flows. |
| `updated_at` | INTEGER NOT NULL | Milliseconds since epoch. |
| `auto_summary_enabled` | INTEGER NOT NULL DEFAULT 0 | Boolean stored as 0/1. |
| `summary_source_hash` | TEXT | Last summary source hash. |
| `summary_updated_at` | INTEGER | Summary update timestamp. |

### `study_sets`

| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER PRIMARY KEY AUTOINCREMENT | Study set ID. |
| `folder_id` | INTEGER NOT NULL | References `folders(id)` with cascade delete. |
| `name` | TEXT NOT NULL | Study set name. |
| `created_at` | INTEGER NOT NULL | Milliseconds since epoch. |

### `study_set_items`

| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER PRIMARY KEY AUTOINCREMENT | Item ID. |
| `study_set_id` | INTEGER NOT NULL | References `study_sets(id)` with cascade delete. |
| `file_id` | INTEGER NOT NULL | References `lecture_files(id)` with cascade delete. |
| `item_order` | INTEGER NOT NULL | Order in set. |
| `marker_percent` | INTEGER NOT NULL DEFAULT 0 | Study marker progress. |

## Current Git / Working Tree Notes

`git -C E:/Leccy status --short` reported:

```text
 M lib/src/ui/leccy_app.dart
?? android/build/
```

This means there are pre-existing local modifications/untracked build output in the project. This analysis file was created separately and does not describe those changes as intentional source changes.

## Notable Observations

1. **Most UI is concentrated in one large file.**  
   `lib/src/ui/leccy_app.dart` contains the app widget, major panels, editor, dialogs, visual effects, graph painter, color picker, and many supporting widgets. This makes the app easy to inspect in one place, but the file is large.

2. **Platform-specific persistence is cleanly abstracted.**  
   `LeccyStore` allows the same controller to work with native SQLite or in-memory storage. Conditional imports choose the implementation.

3. **Web/Chrome preview intentionally does not persist.**  
   README and code agree: non-IO/default store is `MemoryLeccyStore`, so browser data resets per runtime session.

4. **Summary generation is local and extractive.**  
   The code has an `apiKey` field in `AppController`, but the analyzed summary service does not call an external API. It scores local sentences and stores the result in `description`.

5. **SQLite migrations are minimal and versioned.**  
   Current DB version is 2 and only adds summary-related columns from version 1.

6. **Generated/build artifacts are present.**  
   The tree includes `android/.gradle`, `ios/Flutter/ephemeral`, `windows/flutter/ephemeral`, and untracked `android/build/`. These are generated rather than core app logic.

7. **Test suite covers key backend/domain behavior.**  
   Repository, summary service, and controller summary logic have targeted tests. UI testing is currently light.

## File Counts

A compact scan excluding `.git`, `.dart_tool`, and `build` found approximately 140 files. Common extension groups include:

- `.dart`: 18 files
- `.png`: 28 files
- `.xml`: 12 files
- `.h`: 7 files
- `.cpp`: 4 files
- `.swift`: 3 files
- `.kts`: 3 files
- `.json`: 3 files
- `.yaml`: 2 files
- `.md`: 2 existing markdown files before this report

## Suggested Next Checks

If you want to verify the current project health, run:

```powershell
E:\flutter_sdk\bin\flutter.bat analyze
E:\flutter_sdk\bin\flutter.bat test
```

For Windows native app verification after installing prerequisites:

```powershell
E:\flutter_sdk\bin\flutter.bat run -d windows
E:\flutter_sdk\bin\flutter.bat build windows
```

## Quick Orientation for Future Work

- Start app flow: `lib/main.dart` → `LeccyApp` → `LeccyHomePage`.
- Main state/controller: `lib/src/ui/app_controller.dart`.
- Main UI widgets: `lib/src/ui/leccy_app.dart`.
- Data contract: `lib/src/data/leccy_store.dart`.
- Native database: `lib/src/data/app_database.dart` + `lib/src/data/leccy_repository.dart`.
- Web/in-memory behavior: `lib/src/data/memory_leccy_store.dart`.
- Core models: `lib/src/domain/models.dart`.
- Summary logic: `lib/src/domain/summary_service.dart`.
- Tests: `test/*.dart`.
