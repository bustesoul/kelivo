import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/shared/widgets/markdown_with_highlight.dart';

void main() {
  group('MarkdownWithCodeHighlight fence repair', () {
    test('keeps a valid fenced block unchanged', () {
      const input = '```bash\nhello\n```';

      final output = MarkdownWithCodeHighlight.preprocessFencesForTesting(
        input,
        enableMath: false,
        enableDollarLatex: false,
      );

      expect(output, input);
    });

    test('does not rewrite malformed-looking text inside a valid fence', () {
      const input = '```text\n```bash docker compose restart ```\n```';

      final output = MarkdownWithCodeHighlight.preprocessFencesForTesting(
        input,
        enableMath: false,
        enableDollarLatex: false,
      );

      expect(output, input);
    });

    test('splits a spaced malformed opener into a real fenced block', () {
      const input = '```bash curl -fsSL https://get.docker.com | bash ```';
      const expected = '```bash\ncurl -fsSL https://get.docker.com | bash\n```';

      final output = MarkdownWithCodeHighlight.preprocessFencesForTesting(
        input,
        enableMath: false,
        enableDollarLatex: false,
      );

      expect(output, expected);
    });

    test('splits an attached malformed opener with no separator', () {
      const input = '```pythonfrom openai import OpenAIclient = OpenAI(';
      const expected = '```python\nfrom openai import OpenAIclient = OpenAI(';

      final output = MarkdownWithCodeHighlight.preprocessFencesForTesting(
        input,
        enableMath: false,
        enableDollarLatex: false,
      );

      expect(output, expected);
    });

    test('splits prefixed text and keeps the fence as a separate block', () {
      const input =
          '### 五、常用运维命令```bash# 查看日志docker compose logs -f grok2api# 重启docker compose restart\n'
          'docker compose pulldocker compose up -d```';
      const expected =
          '### 五、常用运维命令\n'
          '```bash\n'
          '# 查看日志docker compose logs -f grok2api# 重启docker compose restart\n'
          'docker compose pulldocker compose up -d\n'
          '```';

      final output = MarkdownWithCodeHighlight.preprocessFencesForTesting(
        input,
        enableMath: false,
        enableDollarLatex: false,
      );

      expect(output, expected);
    });

    test('normalizes consecutive malformed blocks into independent fences', () {
      const input =
          '1. **克隆项目**\n'
          '   ```bash git clone https://github.com/chenyme/grok2api.git cd grok2api ```\n\n'
          '2. **复制环境变量文件**\n'
          '   ```bash cp .env.example .env ```\n'
          '   （一般不用改 .env，默认配置就够用。你可以后期修改 `HOST_PORT` 来改变宿主机端口）\n\n'
          '3. **启动 Docker Compose**（一行命令搞定）\n'
          '   ```bash docker compose up -d ```\n\n'
          '启动后会自动拉取 `ghcr.io/chenyme/grok2api:latest`镜像。\n\n'
          '4. **查看日志确认启动成功**\n'
          '   ```bash docker compose logs -f ```\n';
      const expected =
          '1. **克隆项目**\n'
          '```bash\n'
          'git clone https://github.com/chenyme/grok2api.git cd grok2api\n'
          '```\n\n'
          '2. **复制环境变量文件**\n'
          '```bash\n'
          'cp .env.example .env\n'
          '```\n'
          '   （一般不用改 .env，默认配置就够用。你可以后期修改 `HOST_PORT` 来改变宿主机端口）\n\n'
          '3. **启动 Docker Compose**（一行命令搞定）\n'
          '```bash\n'
          'docker compose up -d\n'
          '```\n\n'
          '启动后会自动拉取 `ghcr.io/chenyme/grok2api:latest`镜像。\n\n'
          '4. **查看日志确认启动成功**\n'
          '```bash\n'
          'docker compose logs -f\n'
          '```\n';

      final output = MarkdownWithCodeHighlight.preprocessFencesForTesting(
        input,
        enableMath: false,
        enableDollarLatex: false,
      );

      expect(output, expected);
      expect(output, isNot(contains('__CODE_MASK_')));
    });

    test('repair stage normalizes malformed blocks before masking', () {
      const input =
          '1. **克隆项目**\n'
          '   ```bash git clone https://github.com/chenyme/grok2api.git cd grok2api ```\n\n'
          '2. **复制环境变量文件**\n'
          '   ```bash cp .env.example .env ```\n';
      const expectedStart =
          '1. **克隆项目**\n'
          '```bash\n'
          'git clone https://github.com/chenyme/grok2api.git cd grok2api\n'
          '```\n\n'
          '2. **复制环境变量文件**\n'
          '```bash\n'
          'cp .env.example .env\n'
          '```\n';

      final repaired =
          MarkdownWithCodeHighlight.repairMalformedFencesForTesting(input);

      expect(repaired, expectedStart);
    });
  });
}
