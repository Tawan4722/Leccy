# Leccy

Leccy is a modern, beautifully designed lecture and study organizer application built with Flutter. Originally developed as a Windows-first application, it embraces a fluid, glassmorphic UI to provide students and lifelong learners with an engaging, distraction-free environment for their studies.

## Features

- **Rich Text Editing:** Create comprehensive lecture notes using an advanced rich-text editor, complete with inline formatting, highlighting, and embedded content.
- **Custom Folders & Organization:** Group your files into colorful, customizable folders. Assign specific badges and cover images to keep your workspace visually organized.
- **Study Sets & Flashcards:** Quickly transform your notes into study sets or flashcards, enabling active recall and efficient review sessions.
- **Progress Tracking:** Track your reading and study progress on individual files or entire folders.
- **Data Visualizations:** Built-in table and graphing workspaces to handle complex datasets directly alongside your notes.
- **Local & Private:** By default, Leccy uses local SQLite persistence, keeping all your study materials safely on your device.

## Getting Started

### Prerequisites

To run or build Leccy, you will need the following tools:

- [Flutter SDK](https://flutter.dev/docs/get-started/install)
- Windows Developer Mode enabled
- Visual Studio (with "Desktop development with C++" workload)

### Running Locally

To run the application in development mode:

```powershell
flutter run -d windows
```

*(Note: Chrome preview is supported for UI testing, but uses in-memory storage. Any data created in Chrome will reset when the browser restarts.)*

## Building for Production

### Windows Binary

To build a release executable for Windows:

```powershell
flutter build windows --release
```

The compiled files will be located at `build/windows/x64/runner/Release/`.

### Windows Installer (Inno Setup)

You can easily generate a complete setup executable for distribution using Inno Setup.

1. Install [Inno Setup](https://jrsoftware.org/isdl.php).
2. Ensure you have built the Windows release executable using the command above.
3. Open `LeccyInstaller.iss` in the Inno Setup IDE.
4. Click **Compile** (or press Ctrl+F9).
5. The installer will be generated in the `Output/` directory.

## Contributing

Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.

## License

This project is licensed under the terms described in the `LICENSE` file.
