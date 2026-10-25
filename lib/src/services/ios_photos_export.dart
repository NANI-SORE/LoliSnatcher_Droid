import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Keeps successful Photos publication separate from a file saved in Downloads.
class IOSPhotosExport {
  IOSPhotosExport({required this.receipts, required this.publish});

  final Directory receipts;
  final Future<String?> Function(File file) publish;
  static Future<void> _pending = Future<void>.value();

  /// Returns false when these exact bytes have already been published.
  Future<bool> export(File file, {bool force = false}) async {
    // Sharing a queue prevents concurrent downloads of the same content from
    // producing duplicate Photos assets before their receipt is persisted.
    final previous = _pending;
    final operation = _exportAfter(previous, file, force);
    _pending = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }

  Future<bool> _exportAfter(Future<void> previous, File file, bool force) async {
    await previous;
    if (await file.length() == 0) throw const FileSystemException('Downloaded file is empty');
    final digest = await sha256.bind(file.openRead()).first;
    final receipt = File(p.join(receipts.path, '$digest.asset'));
    if (!force && await receipt.exists() && (await receipt.readAsString()).trim().isNotEmpty) return false;
    // Detect an unusable receipt directory before creating a Photos asset.
    await receipts.create(recursive: true);
    final identifier = await publish(file);
    if (identifier == null || identifier.isEmpty) {
      throw const FileSystemException('Could not save to Photos. The file is available in Downloads.');
    }
    final temporary = File('${receipt.path}.tmp');
    await temporary.writeAsString(identifier, flush: true);
    await temporary.rename(receipt.path);
    return true;
  }
}
