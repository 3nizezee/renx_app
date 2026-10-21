import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class RenpyBridge {
  static const MethodChannel _channel =
      MethodChannel('com.example.ax_app/renpy_bridge');

  /// Check if an execution engine (like JoiPlay Ren'Py plugin) is installed
  static Future<bool> isPluginInstalled() async {
    try {
      final bool? result = await _channel.invokeMethod('isPluginInstalled');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Check if the app has full file access on Android 11+
  static Future<bool> hasAllFilesAccess() async {
    try {
      final bool? result = await _channel.invokeMethod('hasAllFilesAccess');
      return result ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Request full file access on Android 11+
  static Future<bool> requestAllFilesAccess() async {
    try {
      final bool? result =
          await _channel.invokeMethod('requestAllFilesAccess');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Launch the game via the native Ren'Py Android engine
  static Future<bool> launchRenpyGame({
    required String gamePath,
    required String executable,
  }) async {
    try {
      final bool? success = await _channel.invokeMethod('launchRenpyGame', {
        'gamePath': gamePath,
        'executable': executable,
      });
      return success ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Open link to download the Ren'Py plugin if not installed
  static Future<void> openPluginDownloadPage() async {
    final uri = Uri.parse(
        'https://joiplay.cyou/'); // Or itch.io / Google Play link
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
