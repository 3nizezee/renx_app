import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'pickle_decoder.dart';

class RpaEntry {
  const RpaEntry({
    required this.archivePath,
    required this.virtualPath,
    required this.offset,
    required this.length,
    required this.prefix,
  });

  final String archivePath;
  final String virtualPath;
  final int offset;
  final int length;
  final Uint8List prefix;
}

/// Reader for Ren'Py `.rpa` archives (both RPA-3.0 and RPA-2.0).
/// Parses the zlib-compressed pickle index at the offset specified in the
/// archive header and reads individual entries on demand using random access.
class RpaArchive {
  RpaArchive._({
    required this.archivePath,
    required this.version,
    required this.entries,
  });

  final String archivePath;
  final String version;
  final Map<String, RpaEntry> entries;

  static Future<RpaArchive?> open(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return null;

    final raf = await file.open(mode: FileMode.read);
    try {
      final fileLen = await raf.length();
      if (fileLen < 25) return null;

      final headerBuf = await raf.read(64);
      int newlineIdx = headerBuf.indexOf(0x0a);
      if (newlineIdx == -1) newlineIdx = headerBuf.length;
      final headerLine = ascii.decode(headerBuf.sublist(0, newlineIdx)).trim();

      String version = '';
      int indexOffset = 0;
      int xorKey = 0;

      if (headerLine.startsWith('RPA-3.0 ')) {
        version = 'RPA-3.0';
        final parts = headerLine.split(RegExp(r'\s+'));
        if (parts.length < 3) return null;
        indexOffset = int.tryParse(parts[1], radix: 16) ?? 0;
        xorKey = int.tryParse(parts[2], radix: 16) ?? 0;
      } else if (headerLine.startsWith('RPA-2.0 ')) {
        version = 'RPA-2.0';
        final parts = headerLine.split(RegExp(r'\s+'));
        if (parts.length < 2) return null;
        indexOffset = int.tryParse(parts[1], radix: 16) ?? 0;
        xorKey = 0;
      } else {
        return null;
      }

      if (indexOffset <= 0 || indexOffset >= fileLen) return null;

      await raf.setPosition(indexOffset);
      final compressedIndex = await raf.read(fileLen - indexOffset);
      final decompressedIndex =
          Uint8List.fromList(zlib.decode(compressedIndex));

      final decoded = PickleDecoder(decompressedIndex).decode();
      if (decoded is! Map) return null;

      final entries = <String, RpaEntry>{};
      for (final mapEntry in decoded.entries) {
        final rawPath = mapEntry.key.toString().replaceAll(r'\', '/');
        final val = mapEntry.value;
        if (val is List && val.isNotEmpty) {
          final firstTuple = val.first;
          if (firstTuple is List && firstTuple.length >= 2) {
            final rawOffset = (firstTuple[0] as num).toInt();
            final rawLen = (firstTuple[1] as num).toInt();
            final actualOffset = rawOffset ^ xorKey;
            final actualLength = rawLen ^ xorKey;

            Uint8List prefix = Uint8List(0);
            if (firstTuple.length >= 3 && firstTuple[2] != null) {
              final rawPrefix = firstTuple[2];
              if (rawPrefix is Uint8List) {
                prefix = rawPrefix;
              } else if (rawPrefix is List<int>) {
                prefix = Uint8List.fromList(rawPrefix);
              } else if (rawPrefix is String && rawPrefix.isNotEmpty) {
                prefix = Uint8List.fromList(latin1.encode(rawPrefix));
              }
            }

            entries[rawPath] = RpaEntry(
              archivePath: filePath,
              virtualPath: rawPath,
              offset: actualOffset,
              length: actualLength,
              prefix: prefix,
            );
          }
        }
      }

      return RpaArchive._(
        archivePath: filePath,
        version: version,
        entries: entries,
      );
    } catch (_) {
      return null;
    } finally {
      await raf.close();
    }
  }

  /// Reads the raw bytes of an entry inside this archive.
  Future<Uint8List?> readEntry(RpaEntry entry) async {
    final file = File(entry.archivePath);
    if (!await file.exists()) return null;
    final raf = await file.open(mode: FileMode.read);
    try {
      await raf.setPosition(entry.offset);
      final remaining = entry.length - entry.prefix.length;
      final body =
          remaining > 0 ? await raf.read(remaining) : Uint8List(0);
      if (entry.prefix.isEmpty) {
        return body;
      }
      final combined = Uint8List(entry.prefix.length + body.length);
      combined.setRange(0, entry.prefix.length, entry.prefix);
      combined.setRange(entry.prefix.length, combined.length, body);
      return combined;
    } finally {
      await raf.close();
    }
  }
}
