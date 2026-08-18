import 'dart:io';

class BrowserFileLauncher {
  static Future<void> open(String source) async {
    final uri = _toUri(source);
    if (uri == null) {
      throw Exception('ไม่สามารถเปิดไฟล์หรือ URL นี้ได้');
    }

    if (Platform.isWindows) {
      await Process.start('rundll32.exe', [
        'url.dll,FileProtocolHandler',
        uri.toString(),
      ]);
      return;
    }

    await Process.start(uri.toString(), const []);
  }

  static Uri? _toUri(String source) {
    final trimmed = source.trim();
    if (trimmed.isEmpty) return null;

    final parsed = Uri.tryParse(trimmed);
    if (parsed != null && parsed.hasScheme) {
      return parsed;
    }

    return Uri.file(trimmed, windows: Platform.isWindows);
  }
}
