import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:highlight/highlight_core.dart' as hl;
import 'package:highlight/languages/bash.dart' as bash_language;
import 'package:highlight/languages/cpp.dart' as cpp_language;
import 'package:highlight/languages/cs.dart' as csharp_language;
import 'package:highlight/languages/css.dart' as css_language;
import 'package:highlight/languages/dart.dart' as dart_language;
import 'package:highlight/languages/go.dart' as go_language;
import 'package:highlight/languages/java.dart' as java_language;
import 'package:highlight/languages/javascript.dart' as javascript_language;
import 'package:highlight/languages/json.dart' as json_language;
import 'package:highlight/languages/kotlin.dart' as kotlin_language;
import 'package:highlight/languages/python.dart' as python_language;
import 'package:highlight/languages/rust.dart' as rust_language;
import 'package:highlight/languages/sql.dart' as sql_language;
import 'package:highlight/languages/swift.dart' as swift_language;
import 'package:highlight/languages/typescript.dart' as typescript_language;
import 'package:highlight/languages/xml.dart' as xml_language;
import 'package:highlight/languages/yaml.dart' as yaml_language;
import 'package:markdown/markdown.dart' as md;

class MarkdownCodeBlockBuilder extends MarkdownElementBuilder {
  MarkdownCodeBlockBuilder({required this.colors}) {
    _registerLanguages();
  }

  final ColorScheme colors;

  static bool _languagesRegistered = false;

  static const _languageAliases = <String, String>{
    'c#': 'csharp',
    'cs': 'csharp',
    'c++': 'cpp',
    'go': 'go',
    'golang': 'go',
    'html': 'xml',
    'htm': 'xml',
    'js': 'javascript',
    'jsx': 'javascript',
    'kt': 'kotlin',
    'py': 'python',
    'sh': 'bash',
    'shell': 'bash',
    'svg': 'xml',
    'ts': 'typescript',
    'tsx': 'typescript',
    'yml': 'yaml',
    'zsh': 'bash',
  };

  static const _supportedLanguages = <String>{
    'bash',
    'cpp',
    'csharp',
    'css',
    'dart',
    'go',
    'java',
    'javascript',
    'json',
    'kotlin',
    'python',
    'rust',
    'sql',
    'swift',
    'typescript',
    'xml',
    'yaml',
  };

  static void _registerLanguages() {
    if (_languagesRegistered) return;
    hl.highlight.registerLanguage('bash', bash_language.bash);
    hl.highlight.registerLanguage('cpp', cpp_language.cpp);
    hl.highlight.registerLanguage('csharp', csharp_language.cs);
    hl.highlight.registerLanguage('css', css_language.css);
    hl.highlight.registerLanguage('dart', dart_language.dart);
    hl.highlight.registerLanguage('go', go_language.go);
    hl.highlight.registerLanguage('java', java_language.java);
    hl.highlight.registerLanguage(
      'javascript',
      javascript_language.javascript,
    );
    hl.highlight.registerLanguage('json', json_language.json);
    hl.highlight.registerLanguage('kotlin', kotlin_language.kotlin);
    hl.highlight.registerLanguage('python', python_language.python);
    hl.highlight.registerLanguage('rust', rust_language.rust);
    hl.highlight.registerLanguage('sql', sql_language.sql);
    hl.highlight.registerLanguage('swift', swift_language.swift);
    hl.highlight.registerLanguage(
      'typescript',
      typescript_language.typescript,
    );
    hl.highlight.registerLanguage('xml', xml_language.xml);
    hl.highlight.registerLanguage('yaml', yaml_language.yaml);
    _languagesRegistered = true;
  }

  @override
  bool isBlockElement() => true;

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    md.Element? codeElement;
    for (final child in element.children ?? const <md.Node>[]) {
      if (child is md.Element && child.tag == 'code') {
        codeElement = child;
        break;
      }
    }
    final source = (codeElement?.textContent ?? element.textContent)
        .replaceFirst(RegExp(r'\n$'), '');
    final language = _languageFrom(codeElement);
    final baseStyle = TextStyle(
      color: colors.onSurface,
      backgroundColor: Colors.transparent,
      fontFamily: 'monospace',
      fontSize: 14,
      height: 1.45,
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(12),
      child: Text.rich(_highlight(source, language, baseStyle)),
    );
  }

  String? _languageFrom(md.Element? codeElement) {
    final classes = codeElement?.attributes['class']?.split(' ') ?? const [];
    String? language;
    for (final className in classes) {
      if (className.startsWith('language-')) {
        language = className.substring('language-'.length).toLowerCase();
        break;
      }
    }
    if (language == null || language.isEmpty) return null;
    final normalized = _languageAliases[language] ?? language;
    return _supportedLanguages.contains(normalized) ? normalized : null;
  }

  TextSpan _highlight(String source, String? language, TextStyle baseStyle) {
    if (language == null) return TextSpan(text: source, style: baseStyle);
    try {
      final nodes = hl.highlight.parse(source, language: language).nodes;
      return TextSpan(
        style: baseStyle,
        children: _spansFor(nodes, baseStyle),
      );
    } catch (_) {
      return TextSpan(text: source, style: baseStyle);
    }
  }

  List<InlineSpan> _spansFor(List<hl.Node>? nodes, TextStyle baseStyle) =>
      nodes
          ?.map(
            (node) => TextSpan(
              text: node.value,
              style: node.className == null
                  ? null
                  : _styleFor(node.className, baseStyle),
              children: _spansFor(node.children, baseStyle),
            ),
          )
          .toList() ??
      const [];

  TextStyle _styleFor(String? name, TextStyle baseStyle) {
    final color = switch (name) {
      'comment' || 'quote' => const Color(0xFF6B7280),
      'keyword' || 'selector-tag' || 'section' => const Color(0xFF7C3AED),
      'string' || 'regexp' || 'addition' || 'meta-string' =>
        const Color(0xFF16823C),
      'number' || 'literal' => const Color(0xFF1565C0),
      'title' || 'title.function' || 'title.class' || 'name' =>
        const Color(0xFF00796B),
      'attr' || 'attribute' || 'variable' || 'template-variable' =>
        const Color(0xFFC2410C),
      'built_in' || 'type' || 'symbol' || 'bullet' =>
        const Color(0xFFB42318),
      'meta' || 'doctag' || 'link' => const Color(0xFF9C2C86),
      _ => baseStyle.color,
    };
    return baseStyle.copyWith(
      color: color,
      fontStyle: name == 'comment' || name == 'quote'
          ? FontStyle.italic
          : FontStyle.normal,
      fontWeight: name == 'keyword' ? FontWeight.w600 : FontWeight.normal,
    );
  }
}
