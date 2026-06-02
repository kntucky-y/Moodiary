import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:image_picker/image_picker.dart';

Future<Uint8List?> pickAvatarBytesImpl() async {
  if (Platform.isWindows) {
    final script = [
      r'Add-Type -AssemblyName System.Windows.Forms',
      r'$dialog = New-Object System.Windows.Forms.OpenFileDialog',
      r'$dialog.Title = "Select avatar image"',
      r'$dialog.Filter = "Image Files (*.png;*.jpg;*.jpeg;*.webp)|*.png;*.jpg;*.jpeg;*.webp|All files (*.*)|*.*"',
      r'if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { Write-Output $dialog.FileName }',
    ].join('; ');

    final result = await Process.run('powershell.exe', [
      '-NoProfile',
      '-STA',
      '-Command',
      script,
    ]);

    final output = (result.stdout as String).trim();
    if (result.exitCode != 0 || output.isEmpty) return null;
    final file = File(output);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  if (Platform.isMacOS || Platform.isLinux) {
    const fileTypeGroup = XTypeGroup(
      label: 'Images',
      extensions: ['png', 'jpg', 'jpeg', 'webp'],
    );
    final picked = await openFile(acceptedTypeGroups: [fileTypeGroup]);
    if (picked == null) return null;
    return picked.readAsBytes();
  }

  final picker = ImagePicker();
  final picked = await picker.pickImage(
    source: ImageSource.gallery,
    imageQuality: 35,
    maxWidth: 256,
    maxHeight: 256,
  );
  if (picked == null) return null;
  return picked.readAsBytes();
}
