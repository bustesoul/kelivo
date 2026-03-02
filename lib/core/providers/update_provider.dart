import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

const String _repoOwner = 'bustezero';
const String _repoName = 'kelivo';
const String _repoWebBase = 'https://github.com/$_repoOwner/$_repoName';
const String _repoApiBase =
    'https://api.github.com/repos/$_repoOwner/$_repoName';

class UpdateInfo {
  final String app;
  final String version;
  final int? build;
  final DateTime? releasedAt;
  final String? notes;
  final bool mandatory;
  final Map<String, String> downloads;

  const UpdateInfo({
    required this.app,
    required this.version,
    this.build,
    this.releasedAt,
    this.notes,
    this.mandatory = false,
    this.downloads = const {},
  });

  String? bestDownloadUrl() {
    if (Platform.isIOS) {
      return downloads['ios'] ??
          downloads['iosAppStore'] ??
          downloads['universal'];
    }
    if (Platform.isAndroid) {
      return downloads['android'] ?? downloads['universal'];
    }
    if (Platform.isMacOS) {
      return downloads['macos'] ??
          downloads['mac'] ??
          downloads['darwin'] ??
          downloads['universal'];
    }
    if (Platform.isWindows) {
      return downloads['windows'] ?? downloads['win'] ?? downloads['universal'];
    }
    if (Platform.isLinux) {
      return downloads['linux'] ?? downloads['universal'];
    }
    return downloads['universal'] ?? downloads['android'] ?? downloads['ios'];
  }

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    final latest = (json['latest'] as Map?) ?? const {};
    final downloads =
        (latest['downloads'] as Map?)?.map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        ) ??
        const {};
    DateTime? released;
    final releasedRaw = latest['releasedAt']?.toString();
    if (releasedRaw != null && releasedRaw.isNotEmpty) {
      try {
        released = DateTime.parse(releasedRaw);
      } catch (_) {}
    }
    return UpdateInfo(
      app: (json['app'] ?? '').toString(),
      version: (latest['version'] ?? '').toString(),
      build: int.tryParse((latest['build'] ?? '').toString()),
      releasedAt: released,
      notes: (latest['notes'] ?? '').toString(),
      mandatory: (latest['mandatory'] as bool?) ?? false,
      downloads: downloads,
    );
  }
}

class UpdateProvider extends ChangeNotifier {
  UpdateInfo? _available;
  UpdateInfo? get available => _available;
  bool _checking = false;
  bool get checking => _checking;
  String? _error;
  String? get error => _error;

  Future<void> checkForUpdates() async {
    if (_checking) return;
    _checking = true;
    _error = null;
    notifyListeners();
    try {
      final info = await _fetchLatestFromGitHub();

      final pkg = await PackageInfo.fromPlatform();
      final currentVer = pkg.version; // e.g., 1.0.0

      // Compare by version only; ignore build numbers
      final hasNew = _isRemoteNewer(
        remoteVersion: info.version,
        currentVersion: currentVer,
      );
      _available = hasNew ? info : null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _checking = false;
      notifyListeners();
    }
  }

  Future<UpdateInfo> _fetchLatestFromGitHub() async {
    final headers = <String, String>{
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
    };

    final releaseUrl = Uri.parse('$_repoApiBase/releases/latest');
    final releaseResp = await http.get(releaseUrl, headers: headers);
    if (releaseResp.statusCode == 200) {
      final data =
          jsonDecode(utf8.decode(releaseResp.bodyBytes))
              as Map<String, dynamic>;
      return _parseGitHubRelease(data);
    }
    if (releaseResp.statusCode != 404) {
      throw Exception('GitHub releases/latest HTTP ${releaseResp.statusCode}');
    }

    final tagsUrl = Uri.parse('$_repoApiBase/tags?per_page=1');
    final tagsResp = await http.get(tagsUrl, headers: headers);
    if (tagsResp.statusCode != 200) {
      throw Exception('GitHub tags HTTP ${tagsResp.statusCode}');
    }
    final tags = jsonDecode(utf8.decode(tagsResp.bodyBytes)) as List<dynamic>;
    if (tags.isEmpty) {
      throw Exception('GitHub tags is empty');
    }
    final first = tags.first;
    if (first is! Map<String, dynamic>) {
      throw Exception('Invalid GitHub tags payload');
    }

    final rawTag = (first['name'] ?? '').toString().trim();
    if (rawTag.isEmpty) {
      throw Exception('GitHub tag name is empty');
    }
    final normalized = _normalizeVersion(rawTag);

    return UpdateInfo(
      app: '$_repoOwner/$_repoName',
      version: normalized.isNotEmpty ? normalized : rawTag,
      notes: null,
      mandatory: false,
      downloads: <String, String>{
        'universal': '$_repoWebBase/releases/tag/$rawTag',
      },
    );
  }

  UpdateInfo _parseGitHubRelease(Map<String, dynamic> data) {
    final rawTag = (data['tag_name'] ?? '').toString().trim();
    final normalized = _normalizeVersion(rawTag);
    final releasePage = (data['html_url'] ?? '').toString().trim();

    DateTime? releasedAt;
    final releasedRaw = (data['published_at'] ?? data['created_at'])
        ?.toString()
        .trim();
    if (releasedRaw != null && releasedRaw.isNotEmpty) {
      try {
        releasedAt = DateTime.parse(releasedRaw);
      } catch (_) {}
    }

    final downloads = <String, String>{};
    if (releasePage.isNotEmpty) {
      downloads['universal'] = releasePage;
    }

    final assets = data['assets'];
    if (assets is List) {
      for (final item in assets) {
        if (item is! Map) continue;
        final name = (item['name'] ?? '').toString().toLowerCase();
        final url = (item['browser_download_url'] ?? '').toString().trim();
        if (name.isEmpty || url.isEmpty) continue;
        final platformKey = _detectPlatformFromAssetName(name);
        if (platformKey == null) continue;
        downloads.putIfAbsent(platformKey, () => url);
      }
    }

    if (downloads.isEmpty) {
      downloads['universal'] = '$_repoWebBase/releases/latest';
    }

    final notes = (data['body'] ?? '').toString();
    return UpdateInfo(
      app: '$_repoOwner/$_repoName',
      version: normalized.isNotEmpty ? normalized : rawTag,
      releasedAt: releasedAt,
      notes: notes.isEmpty ? null : notes,
      mandatory: false,
      downloads: downloads,
    );
  }

  String? _detectPlatformFromAssetName(String name) {
    if (name.contains('android') ||
        name.endsWith('.apk') ||
        name.endsWith('.aab')) {
      return 'android';
    }
    if (name.contains('ios') || name.endsWith('.ipa')) {
      return 'ios';
    }
    if (name.contains('mac') ||
        name.endsWith('.dmg') ||
        name.endsWith('.pkg')) {
      return 'macos';
    }
    if (name.contains('windows') ||
        name.contains('win') ||
        name.endsWith('.exe') ||
        name.endsWith('.msi')) {
      return 'windows';
    }
    if (name.contains('linux') ||
        name.endsWith('.appimage') ||
        name.endsWith('.deb') ||
        name.endsWith('.rpm')) {
      return 'linux';
    }
    return null;
  }

  String _normalizeVersion(String input) {
    final raw = input.trim();
    if (raw.isEmpty) return '';
    final matched = RegExp(r'(\d+)(?:\.(\d+))?(?:\.(\d+))?').firstMatch(raw);
    if (matched == null) {
      return raw.replaceFirst(RegExp(r'^[vV]'), '');
    }
    final major = matched.group(1) ?? '0';
    final minor = matched.group(2) ?? '0';
    final patch = matched.group(3) ?? '0';
    return '$major.$minor.$patch';
  }

  bool _isRemoteNewer({
    required String remoteVersion,
    required String currentVersion,
  }) {
    // Compare semantic versions only (ignore internal build numbers)
    List<int> parseVer(String v) {
      final matched = RegExp(r'(\d+)(?:\.(\d+))?(?:\.(\d+))?').firstMatch(v);
      if (matched == null) return const <int>[0, 0, 0];
      return <int>[
        int.tryParse(matched.group(1) ?? '0') ?? 0,
        int.tryParse(matched.group(2) ?? '0') ?? 0,
        int.tryParse(matched.group(3) ?? '0') ?? 0,
      ];
    }

    final a = parseVer(remoteVersion);
    final b = parseVer(currentVersion);
    if (a[0] != b[0]) return a[0] > b[0];
    if (a[1] != b[1]) return a[1] > b[1];
    if (a[2] != b[2]) return a[2] > b[2];
    return false;
  }
}
