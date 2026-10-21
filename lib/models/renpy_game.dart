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
  });

  Map<String, dynamic> toMap() {
    return {
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
    };
  }

  factory RenpyGame.fromMap(Map<String, dynamic> map) {
    return RenpyGame(
      id: map['id'] ?? '',
      title: map['title'] ?? 'Unknown Game',
      path: map['path'] ?? '',
      executableName: map['executableName'] ?? '',
      iconPath: map['iconPath'],
      coverPath: map['coverPath'],
      renpyVersion: map['renpyVersion'] ?? 'Ren\'Py 7/8',
      dateAdded: DateTime.tryParse(map['dateAdded'] ?? '') ?? DateTime.now(),
      lastPlayed: map['lastPlayed'] != null
          ? DateTime.tryParse(map['lastPlayed'])
          : null,
      playTimeMinutes: map['playTimeMinutes'] ?? 0,
      isFavorite: map['isFavorite'] ?? false,
    );
  }

  String toJson() => json.encode(toMap());

  factory RenpyGame.fromJson(String source) =>
      RenpyGame.fromMap(json.decode(source));
}
