# Leccy

Leccy is a Flutter lecture organizer built Windows-first with a mobile-friendly
project structure. It supports customizable folders, rich-text lecture notes,
quick notes, descriptions, text highlighting, file progress, and saved study
sets made from selected files.

## Local Flutter SDK

This workspace uses the local SDK installed at:

```powershell
E:\flutter_sdk\bin\flutter.bat
```

Useful commands:

```powershell
E:\flutter_sdk\bin\flutter.bat analyze
E:\flutter_sdk\bin\flutter.bat test
E:\flutter_sdk\bin\flutter.bat run -d chrome
E:\flutter_sdk\bin\flutter.bat run -d windows
E:\flutter_sdk\bin\flutter.bat build windows
```

Chrome preview uses in-memory storage so it can run without the Windows native
toolchain. Data will reset when the browser session restarts. The Windows build
uses SQLite persistence.

## Windows Setup Still Required

Flutter source, analysis, and tests are ready. Running or building the native
Windows app still requires:

- Windows Developer Mode enabled for plugin symlinks.
- Visual Studio with the `Desktop development with C++` workload.

After those are installed, `flutter run -d windows` and
`flutter build windows` should be the next checks.
