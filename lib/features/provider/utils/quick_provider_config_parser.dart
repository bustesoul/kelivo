import 'dart:convert';

/// The provider type inferred from a pasted quick-add config.
enum QuickProviderKind { openai, google, claude }

/// A lightweight, UI-independent parse result for the "quick add" paste box.
///
/// Only fields that could be recognized from the pasted JSON are non-null.
/// The caller decides which form fields to fill based on [kind].
class QuickProviderConfig {
  final QuickProviderKind kind;
  final String? apiKey;
  final String? baseUrl;
  final String? name;
  final String? apiPath;
  final String? location;
  final String? projectId;
  final String? serviceAccountJson;

  const QuickProviderConfig({
    required this.kind,
    this.apiKey,
    this.baseUrl,
    this.name,
    this.apiPath,
    this.location,
    this.projectId,
    this.serviceAccountJson,
  });

  /// True when at least one fillable field was recognized.
  bool get hasAnyField =>
      apiKey != null ||
      baseUrl != null ||
      name != null ||
      apiPath != null ||
      location != null ||
      projectId != null ||
      serviceAccountJson != null;
}

/// Normalize a JSON key for fuzzy matching: lowercase, then strip the
/// separators that humans use interchangeably (`_`, `-`, spaces, dots), and
/// split camelCase boundaries so `apiKey` becomes `apikey`.
/// e.g. `API Key` / `api_key` / `api-key` / `apiKey` -> `apikey`.
String _normalizeKey(String key) {
  final spaced = key.replaceAllMapped(
    RegExp(r'([a-z0-9])([A-Z])'),
    (m) => '${m[1]} ${m[2]}',
  );
  return spaced.toLowerCase().replaceAll(RegExp(r'[\s_\-./]+'), '');
}

/// Returns true when [normalizedKey] contains any of [keywords].
bool _matchesAny(String normalizedKey, Iterable<String> keywords) {
  for (final raw in keywords) {
    final kw = _normalizeKey(raw);
    if (kw.isEmpty) continue;
    if (normalizedKey.contains(kw)) return true;
  }
  return false;
}

// Keyword sets per logical field. Ordered from most-specific to least so that
// the matching loop below can claim each raw key for at most one field.
// API Key is claimed BEFORE Base URL: a raw key like `key`/`apikey` matches the
// `key` keyword and gets claimed, so it cannot later be matched by the broader
// Base URL keyword `api`.
const List<String> _kApiKey = [
  'apikey',
  'token',
  'secret',
  'authorization',
  'key',
];
const List<String> _kBaseUrl = [
  'baseurl',
  'endpoint',
  'host',
  'server',
  'url',
  'base',
  'api',
];
const List<String> _kApiPath = ['apipath', 'chatpath', 'completion', 'path'];
const List<String> _kLocation = ['location', 'region', 'zone'];
const List<String> _kProjectId = ['projectid', 'project'];
const List<String> _kServiceAccount = [
  'serviceaccountjson',
  'serviceaccount',
  'credential',
  'sa',
];
const List<String> _kName = ['title', 'label', 'alias', 'provider', 'name'];

QuickProviderKind _inferKind(String? typeField, String? baseUrl) {
  // 1. Explicit _type discriminator (optional).
  if (typeField != null && typeField.isNotEmpty) {
    final t = typeField.toLowerCase();
    if (t.contains('gemini') || t.contains('google')) {
      return QuickProviderKind.google;
    }
    if (t.contains('claude') || t.contains('anthropic')) {
      return QuickProviderKind.claude;
    }
    // newapi_channel_conn / openai / one-api / unknown -> openai (compat gateway)
    return QuickProviderKind.openai;
  }
  // 2. Infer from Base URL host.
  if (baseUrl != null && baseUrl.isNotEmpty) {
    final u = baseUrl.toLowerCase();
    if (u.contains('gemini') ||
        u.contains('googleapis') ||
        u.contains('generativelanguage')) {
      return QuickProviderKind.google;
    }
    if (u.contains('anthropic') || u.contains('claude')) {
      return QuickProviderKind.claude;
    }
  }
  // 3. Default: OpenAI-compatible gateway.
  return QuickProviderKind.openai;
}

/// Parses a pasted provider config string into a [QuickProviderConfig].
///
/// Returns `null` when the input is not valid JSON, is not a JSON object, or
/// when no known field could be recognized. Use [quickParseError] to obtain a
/// human-readable reason for the failure.
QuickProviderConfig? parseQuickProviderConfig(String raw) {
  final error = quickParseError(raw);
  if (error != null) return null;
  return _doParse(raw.trim());
}

/// Returns a human-readable error string when [raw] cannot be parsed, or
/// `null` when parsing would succeed. This is the canonical check: callers
/// should use it when they need the failure reason (e.g. for a SnackBar).
String? quickParseError(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return 'empty input';
  dynamic decoded;
  try {
    decoded = jsonDecode(trimmed);
  } catch (e) {
    return 'invalid JSON: $e';
  }
  if (decoded is! Map<String, dynamic>) return 'expected a JSON object';
  if (decoded.isEmpty) return 'empty object';
  final result = _doParse(trimmed);
  if (result == null || !result.hasAnyField) {
    return 'no recognizable provider field';
  }
  return null;
}

QuickProviderConfig? _doParse(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map<String, dynamic>) return null;

  // Raw keys already consumed by a field (most-specific-first claiming, so a
  // single key like `apikey` fills at most one field).
  final claimed = <String>{};
  String? apiKey,
      baseUrl,
      name,
      apiPath,
      location,
      projectId,
      serviceAccountJson;

  // Scan the object once per field, claiming the first matching non-empty key.
  void claim(List<String> keywords, void Function(String value) assign) {
    for (final entry in decoded.entries) {
      if (claimed.contains(entry.key)) continue;
      final norm = _normalizeKey(entry.key);
      if (!_matchesAny(norm, keywords)) continue;
      final value = entry.value?.toString().trim();
      // Claim the key regardless of value so a later, broader keyword cannot
      // re-interpret it; only assign when there is something to fill.
      claimed.add(entry.key);
      if (value != null && value.isNotEmpty) {
        assign(value);
        return;
      }
    }
  }

  // _type (optional discriminator, not itself a form field).
  final typeField = decoded['_type']?.toString();

  // Order matters: claim specific fields before broad ones.
  claim(_kApiKey, (v) => apiKey = v);
  claim(_kBaseUrl, (v) => baseUrl = v);
  claim(_kApiPath, (v) => apiPath = v);
  claim(_kLocation, (v) => location = v);
  claim(_kProjectId, (v) => projectId = v);
  claim(_kServiceAccount, (v) => serviceAccountJson = v);
  claim(_kName, (v) => name = v);

  final result = QuickProviderConfig(
    kind: _inferKind(typeField, baseUrl),
    apiKey: apiKey,
    baseUrl: baseUrl,
    name: name,
    apiPath: apiPath,
    location: location,
    projectId: projectId,
    serviceAccountJson: serviceAccountJson,
  );

  return result.hasAnyField ? result : null;
}
