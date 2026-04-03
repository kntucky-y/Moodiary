import 'dart:typed_data';

import 'avatar_file_picker_stub.dart'
    if (dart.library.io) 'avatar_file_picker_io.dart';

Future<Uint8List?> pickAvatarBytes() => pickAvatarBytesImpl();
