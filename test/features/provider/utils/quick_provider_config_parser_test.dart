import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/features/provider/utils/quick_provider_config_parser.dart';

void main() {
  group('parseQuickProviderConfig - 标准格式', () {
    test('newapi_channel_conn 示例可解析为 OpenAI', () {
      const raw =
          '{"_type":"newapi_channel_conn","key":"sk-abc","url":"https://new-api.abrdns.com"}';
      final result = parseQuickProviderConfig(raw);
      expect(result, isNotNull);
      expect(result!.kind, QuickProviderKind.openai);
      expect(result.apiKey, 'sk-abc');
      expect(result.baseUrl, 'https://new-api.abrdns.com');
    });

    test('字段值前后空格会被 trim', () {
      const raw = '{"key": "  sk-space  ", "url": " https://x.com "}';
      final result = parseQuickProviderConfig(raw);
      expect(result, isNotNull);
      expect(result!.apiKey, 'sk-space');
      expect(result.baseUrl, 'https://x.com');
    });
  });

  group('模糊关键字匹配', () {
    test('apikey 命中 API Key（与预设 key 匹配）', () {
      const raw = '{"apikey": "sk-1", "url": "https://a.com"}';
      final result = parseQuickProviderConfig(raw);
      expect(result, isNotNull);
      expect(result!.apiKey, 'sk-1');
    });

    test('token 命中 API Key', () {
      const raw = '{"token": "tok", "baseurl": "https://a.com"}';
      final result = parseQuickProviderConfig(raw);
      expect(result, isNotNull);
      expect(result!.apiKey, 'tok');
    });

    test('api_key（带下划线）归一化后命中', () {
      const raw = '{"api_key": "sk-u", "base_url": "https://a.com"}';
      final result = parseQuickProviderConfig(raw);
      expect(result, isNotNull);
      expect(result!.apiKey, 'sk-u');
      expect(result.baseUrl, 'https://a.com');
    });

    test('camelCase apiKey 归一化后命中', () {
      const raw = '{"apiKey": "sk-cc", "baseUrl": "https://a.com"}';
      final result = parseQuickProviderConfig(raw);
      expect(result, isNotNull);
      expect(result!.apiKey, 'sk-cc');
      expect(result.baseUrl, 'https://a.com');
    });

    test('endpoint / host 命中 Base URL', () {
      const raw = '{"endpoint": "https://ep.com"}';
      final result = parseQuickProviderConfig(raw);
      expect(result, isNotNull);
      expect(result!.baseUrl, 'https://ep.com');
    });

    test('name / title 命中 Name', () {
      const raw1 = '{"name": "My Provider", "url": "https://a.com"}';
      expect(parseQuickProviderConfig(raw1)?.name, 'My Provider');
      const raw2 = '{"title": "T", "url": "https://a.com"}';
      expect(parseQuickProviderConfig(raw2)?.name, 'T');
    });

    test('path 命中 API Path', () {
      const raw = '{"path": "/v1/chat/completions", "url": "https://a.com"}';
      final result = parseQuickProviderConfig(raw);
      expect(result, isNotNull);
      expect(result!.apiPath, '/v1/chat/completions');
    });
  });

  group('同一 key 不会被多个字段重复占用', () {
    test('apikey 只填入 API Key，不会被 api 误判为 Base URL', () {
      // `apikey` 含 `api`，但因 API Key 先声明，Base URL 不会抢走它。
      const raw = '{"apikey": "sk-1"}';
      final result = parseQuickProviderConfig(raw);
      expect(result, isNotNull);
      expect(result!.apiKey, 'sk-1');
      expect(result.baseUrl, isNull);
    });
  });

  group('类型推断', () {
    test('无 _type 时按 URL 推测为 Google', () {
      const raw =
          '{"key": "g", "url": "https://generativelanguage.googleapis.com/v1beta"}';
      final result = parseQuickProviderConfig(raw);
      expect(result, isNotNull);
      expect(result!.kind, QuickProviderKind.google);
    });

    test('无 _type 时按 URL 推测为 Claude', () {
      const raw = '{"key": "c", "url": "https://api.anthropic.com/v1"}';
      final result = parseQuickProviderConfig(raw);
      expect(result, isNotNull);
      expect(result!.kind, QuickProviderKind.claude);
    });

    test('无 _type 且无特征的兼容网关默认 OpenAI', () {
      const raw = '{"key": "k", "url": "https://new-api.example.com"}';
      final result = parseQuickProviderConfig(raw);
      expect(result, isNotNull);
      expect(result!.kind, QuickProviderKind.openai);
    });

    test('_type 含 gemini 推测为 Google', () {
      const raw =
          '{"_type": "gemini_channel", "key": "g", "url": "https://x.com"}';
      expect(parseQuickProviderConfig(raw)?.kind, QuickProviderKind.google);
    });

    test('_type 含 anthropic 推测为 Claude', () {
      const raw =
          '{"_type": "anthropic_conn", "key": "c", "url": "https://x.com"}';
      expect(parseQuickProviderConfig(raw)?.kind, QuickProviderKind.claude);
    });
  });

  group('Google Vertex 字段识别', () {
    test('location / region 命中 Location', () {
      const raw1 = '{"location": "us-east1", "url": "https://x.com"}';
      expect(parseQuickProviderConfig(raw1)?.location, 'us-east1');
      const raw2 = '{"region": "europe-west4", "url": "https://x.com"}';
      expect(parseQuickProviderConfig(raw2)?.location, 'europe-west4');
    });

    test('project 命中 Project ID', () {
      const raw = '{"project": "my-proj", "url": "https://x.com"}';
      expect(parseQuickProviderConfig(raw)?.projectId, 'my-proj');
    });

    test('serviceaccount 命中 Service Account JSON', () {
      // Use a plain string value to avoid JSON-in-JSON escaping ambiguity; the
      // parser only forwards the string value, so any non-empty value works.
      const raw =
          '{"serviceaccount": "SA-PLAIN-VALUE", "url": "https://x.com"}';
      expect(
        parseQuickProviderConfig(raw)?.serviceAccountJson,
        'SA-PLAIN-VALUE',
      );
    });
  });

  group('失败路径', () {
    test('非 JSON 返回 null 并给出错误', () {
      const raw = 'this is not json';
      expect(parseQuickProviderConfig(raw), isNull);
      expect(quickParseError(raw), isNotNull);
      expect(quickParseError(raw), contains('invalid JSON'));
    });

    test('空字符串', () {
      expect(parseQuickProviderConfig(''), isNull);
      expect(quickParseError(''), 'empty input');
    });

    test('空对象', () {
      const raw = '{}';
      expect(parseQuickProviderConfig(raw), isNull);
      expect(quickParseError(raw), 'empty object');
    });

    test('JSON 数组不被接受', () {
      const raw = '[1,2,3]';
      expect(parseQuickProviderConfig(raw), isNull);
      expect(quickParseError(raw), 'expected a JSON object');
    });

    test('没有任何可识别字段', () {
      const raw = '{"foo": "bar", "baz": 42}';
      expect(parseQuickProviderConfig(raw), isNull);
      expect(quickParseError(raw), 'no recognizable provider field');
    });

    test('仅有一个字段（key）也视为成功', () {
      const raw = '{"key": "sk-only"}';
      final result = parseQuickProviderConfig(raw);
      expect(result, isNotNull);
      expect(result!.apiKey, 'sk-only');
      expect(result.hasAnyField, isTrue);
    });
  });

  group('quickParseError 成功时返回 null', () {
    test('合法配置返回 null', () {
      const raw = '{"key": "k", "url": "https://a.com"}';
      expect(quickParseError(raw), isNull);
    });
  });
}
