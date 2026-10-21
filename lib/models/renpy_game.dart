import 'dart:convert';

class RenpyGame {
  final String id;
  final String title;
  final String path;
  final String executableName;
  final String? iconPath;
  final String? coverPath;
  final String renpyVersion;
  final DateTime dateAdded;
  DateTime? lastPlayed;
  int playTimeMinutes;
  bool isFavorite;
  final int archiveCount;
  final int scriptCount;
  final int assetCount;

  RenpyGame({
    required this.id,
    required this.title,
    required this.path,
    required this.executableName,
    this.iconPath,
    this.coverPath,
    this.renpyVersion = 'Ren\'Py 7/8',
    required this.dateAdded,
    this.lastPlayed,
    this.playTimeMinutes = 0,
    this.isFavorite = false,
    this.archiveCount = 0,
    this.scriptCount = 0,
    this.assetCount = 0,
  });

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'path': path,
      'executableName': executableName,
      'iconPath': iconPath,
      'coverPath': coverPath,
      'renpyVersion': renpyVersion,
      'dateAdded': dateAdded.toIso8601String(),
      'lastPlayed': lastPlayed?.toIso8601String(),
      'playTimeMinutes': playTimeMinutes,
      'isFavorite': isFavorite,
      'archiveCount': archiveCount,
      'scriptCount': scriptCount,
      'assetCount': assetCount,
    };
  }

  factory RenpyGame.fromMap(Map<String, dynamic> map) {
    return RenpyGame(
      id: (map['id'] as String?) ?? '',
      title: (map['title'] as String?) ?? 'Untitled Project',
      path: (map['path'] as String?) ?? '',
      executableName: (map['executableName'] as String?) ?? '',
      iconPath: map['iconPath'] as String?,
      coverPath: map['coverPath'] as String?,
      renpyVersion: (map['renpyVersion'] as String?) ?? 'Ren\'Py 7/8',
      dateAdded: DateTime.tryParse((map['dateAdded'] as String?) ?? '') ??
          DateTime.now(),
      lastPlayed: map['lastPlayed'] != null
          ? DateTime.tryParse(map['lastPlayed'].toString())
          : null,
      playTimeMinutes: (map['playTimeMinutes'] as num?)?.toInt() ?? 0,
      isFavorite: (map['isFavorite'] as bool?) ?? false,
      archiveCount: (map['archiveCount'] as num?)?.toInt() ?? 0,
      scriptCount: (map['scriptCount'] as num?)?.toInt() ?? 0,
      assetCount: (map['assetCount'] as num?)?.toInt() ?? 0,
    );
  }

  String toJson() => json.encode(toMap());

  factory RenpyGame.fromJson(String source) =>
      RenpyGame.fromMap(Map<String, dynamic>.from(json.decode(source) as Map));
}
