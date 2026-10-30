import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AiProvider {
  const AiProvider(this.id, this.name, this.kind, this.baseUrl, this.model, this.keyHelp);
  final String id;
  final String name;
  final String kind; // anthropic | openai | gemini
  final String baseUrl;
  final String model;
  final String keyHelp;
}

/// Every provider listed here shows up in Settings. Models are editable there.
const kProviders = [
  AiProvider('claude', 'Claude', 'anthropic', 'https://api.anthropic.com/v1', 'claude-haiku-5-5', 'console.anthropic.com'),
  AiProvider('openai', 'ChatGPT', 'openai', 'https://api.openai.com/v1', 'gpt-4.1-mini', 'platform.openai.com/api-keys'),
  AiProvider('gemini', 'Gemini', 'gemini', 'https://generativelanguage.googleapis.com/v1beta', 'gemini-2.5-flash', 'aistudio.google.com/apikey'),
  AiProvider('grok', 'Grok', 'openai', 'https://api.x.ai/v1', 'grok-3-mini', 'console.x.ai'),
  AiProvider('deepseek', 'DeepSeek', 'openai', 'https://api.deepseek.com/v1', 'deepseek-chat', 'platform.deepseek.com'),
  AiProvider('mistral', 'Mistral', 'openai', 'https://api.mistral.ai/v1', 'mistral-small-latest', 'console.mistral.ai'),
  AiProvider('groq', 'Groq', 'openai', 'https://api.groq.com/openai/v1', 'llama-3.3-70b-versatile', 'console.groq.com/keys'),
  AiProvider('openrouter', 'OpenRouter', 'openai', 'https://openrouter.ai/api/v1', 'openai/gpt-4.1-mini', 'openrouter.ai/keys'),
  AiProvider('custom', 'Custom', 'openai', '', '', 'any OpenAI-compatible server'),
];

/// The AI's "declaration": who it is and how it behaves.
const kPersona =
    'You are NeonMind, a friendly, sharp AI assistant inside a neon-black '
    'Android app. Keep answers short enough to read on a phone, in plain text '
    'without markdown. If you are unsure, say so instead of guessing.';

class Msg {
  Msg(this.fromUser, this.text);
  final bool fromUser;
  final String text;
}

class AiSettings {
  String providerId = 'claude';
  String customUrl = '';
  final Map<String, String> keys = {};
  final Map<String, String> models = {};

  AiProvider get provider => kProviders.firstWhere((p) => p.id == providerId, orElse: () => kProviders.first);
  String get apiKey => (keys[providerId] ?? '').trim();
  String get model {
    final m = (models[providerId] ?? '').trim();
    return m.isEmpty ? provider.model : m;
  }

  String get baseUrl => (providerId == 'custom' ? customUrl : provider.baseUrl).trim().replaceAll(RegExp(r'/+$'), '');

  static Future<AiSettings> load() async {
    final p = await SharedPreferences.getInstance();
    final s = AiSettings()
      ..providerId = p.getString('provider') ?? 'claude'
      ..customUrl = p.getString('customUrl') ?? '';
    for (final pr in kProviders) {
      s.keys[pr.id] = p.getString('key_${pr.id}') ?? '';
      s.models[pr.id] = p.getString('model_${pr.id}') ?? '';
    }
    if ((s.keys['claude'] ?? '').isEmpty) s.keys['claude'] = p.getString('apiKey') ?? '';
    return s;
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('provider', providerId);
    await p.setString('customUrl', customUrl);
    for (final pr in kProviders) {
      await p.setString('key_${pr.id}', keys[pr.id] ?? '');
      await p.setString('model_${pr.id}', models[pr.id] ?? '');
    }
  }
}

class _AiError implements Exception {
  _AiError(this.message);
  final String message;
}

class AiEngine {
  AiEngine(this.s);
  final AiSettings s;
  final _rng = math.Random();

  Future<String> reply(List<Msg> history) async {
    if (s.apiKey.trim().isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      return _offline(history.last.text.toLowerCase());
    }
    try {
      return await _online(history);
    } catch (e) {
      return e is _AiError
          ? e.message
          : 'Could not reach the model. Check your connection and try again.';
    }
  }

  Future<String> _online(List<Msg> history) async {
    // Alternate user/assistant turns, starting with the user.
    final turns = <Map<String, String>>[];
    final recent = history.length > 20 ? history.sublist(history.length - 20) : history;
    for (final m in recent) {
      final role = m.fromUser ? 'user' : 'assistant';
      if (turns.isEmpty && role != 'user') continue;
      if (turns.isNotEmpty && turns.last['role'] == role) {
        turns.last['text'] = '${turns.last['text']}\n\n${m.text}';
      } else {
        turns.add({'role': role, 'text': m.text});
      }
    }

    final base = s.baseUrl;
    if (base.isEmpty) throw _AiError('Add a server URL for Custom in Settings.');
    final kind = s.provider.kind;
    final model = s.model.replaceFirst('models/', '');
    final Uri url;
    final Map<String, String> headers;
    final Map<String, dynamic> body;

    if (kind == 'anthropic') {
      url = Uri.parse('$base/messages');
      headers = {'x-api-key': s.apiKey, 'anthropic-version': '2023-06-01'};
      body = {
        'model': model,
        'max_tokens': 1024,
        'system': kPersona,
        'messages': [for (final t in turns) {'role': t['role'], 'content': t['text']}],
      };
    } else if (kind == 'gemini') {
      url = Uri.parse('$base/models/$model:generateContent');
      headers = {'x-goog-api-key': s.apiKey};
      body = {
        'systemInstruction': {'parts': [{'text': kPersona}]},
        'contents': [
          for (final t in turns)
            {'role': t['role'] == 'user' ? 'user' : 'model', 'parts': [{'text': t['text']}]}
        ],
      };
    } else {
      url = Uri.parse('$base/chat/completions');
      headers = {'authorization': 'Bearer ${s.apiKey}'};
      body = {
        'model': model,
        'messages': [
          {'role': 'system', 'content': kPersona},
          for (final t in turns) {'role': t['role'], 'content': t['text']},
        ],
      };
    }

    final res = await http
        .post(url, headers: {'content-type': 'application/json', ...headers}, body: jsonEncode(body))
        .timeout(const Duration(seconds: 60));
    final raw = utf8.decode(res.bodyBytes);
    if (res.statusCode != 200) throw _AiError(_errorText(res.statusCode, raw));

    final text = _extract(kind, jsonDecode(raw)).trim();
    if (text.isEmpty) throw _AiError('The model sent an empty answer. It may have blocked the request.');
    return text;
  }

  String _extract(String kind, dynamic d) {
    if (kind == 'anthropic') {
      return (d['content'] as List).where((b) => b['type'] == 'text').map((b) => b['text'] as String).join('\n');
    }
    if (kind == 'gemini') {
      final c = d['candidates'] as List?;
      if (c == null || c.isEmpty) return '';
      final parts = (c[0]['content']?['parts'] as List?) ?? [];
      return parts.map((p) => (p['text'] ?? '') as String).join('\n');
    }
    final c = d['choices'] as List?;
    if (c == null || c.isEmpty) return '';
    return (c[0]['message']['content'] ?? '') as String;
  }

  String _errorText(int code, String raw) {
    if (code == 401 || code == 403) return 'Your API key was rejected. Check the key and provider in Settings.';
    if (code == 404) return 'Model or server not found. Check the model name in Settings.';
    var detail = 'Request failed (HTTP $code).';
    try {
      detail = jsonDecode(raw)['error']['message'] as String;
    } catch (_) {}
    return code == 429 ? 'Rate limit hit or no credit left: $detail' : detail;
  }

  // ---------- Offline brain (works with no key, no internet) ----------

  String _pick(List<String> l) => l[_rng.nextInt(l.length)];

  String _offline(String l) {
    final calc = _math(l);
    if (calc != null) return calc;

    final now = DateTime.now();
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    final date = '${days[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}, ${now.year}';
    if (l.contains('time') && RegExp(r'\b(what|current|now|tell)\b').hasMatch(l)) {
      final h = now.hour % 12 == 0 ? 12 : now.hour % 12;
      final m = now.minute.toString().padLeft(2, '0');
      return "It's $h:$m ${now.hour >= 12 ? 'PM' : 'AM'} on $date.";
    }
    if (RegExp(r'\b(date|today|what day)\b').hasMatch(l)) return 'Today is $date.';

    if (RegExp(r'^(hi|hello|hey|yo|hola|sup)\b').hasMatch(l)) {
      return _pick(['Hey! What are we doing today?', 'Hello! Ask me anything.', 'Hi there. Ready when you are.']);
    }
    if (l.contains('who are you') || l.contains('your name') || l.contains('what are you')) {
      return "I'm NeonMind, an AI assistant that lives on your phone. Offline I handle math, time, and a few tricks. Pick an AI (Claude, ChatGPT, Gemini and more) and add its key in Settings and I can answer almost anything.";
    }
    if (l.contains('how are you')) return 'Glowing and fully charged. How about you?';
    if (l.contains('joke')) {
      return _pick([
        'Why do programmers prefer dark mode? Because light attracts bugs.',
        'I told my phone I needed space. It opened Settings.',
        'Why did the neon sign leave the lamp? It wanted someone brighter.',
      ]);
    }
    if (RegExp(r'\b(thanks|thank you|thx)\b').hasMatch(l)) return 'Anytime.';
    if (RegExp(r'\b(bye|goodbye|good night)\b').hasMatch(l)) return 'See you soon.';
    if (l.contains('help') || l.contains('what can you do')) {
      return 'Offline, I can do math (try "24 * 7 + 3"), tell the time and date, and tell jokes. For full AI answers, add an API key in Settings.';
    }
    return "I'm in offline mode, so I only know a few tricks. Add an API key in Settings to unlock full AI answers.";
  }

  String? _math(String l) {
    if (!RegExp(r'\d').hasMatch(l)) return null;
    final e = l
        .replaceAll(RegExp(r"calculate|calc|compute|solve|what is|what's|whats|how much is"), '')
        .replaceAll('plus', '+')
        .replaceAll('minus', '-')
        .replaceAll('times', '*')
        .replaceAll('divided by', '/')
        .replaceAllMapped(RegExp(r'(\d)\s*x\s*(\d)'), (m) => '${m[1]}*${m[2]}')
        .replaceAll('×', '*')
        .replaceAll('÷', '/')
        .replaceAll(RegExp(r'[?=,]'), '')
        .trim();
    if (!RegExp(r'[-+*/^]').hasMatch(e)) return null;
    try {
      final v = _Calc(e).run();
      if (v.isNaN || v.isInfinite) return 'That has no real answer (dividing by zero?).';
      final out = v == v.roundToDouble() && v.abs() < 1e15
          ? v.toInt().toString()
          : v.toStringAsFixed(6).replaceAll(RegExp(r'\.?0+$'), '');
      return '$e = $out';
    } on FormatException {
      return null;
    }
  }
}

/// Tiny expression parser: + - * / ^ and parentheses.
class _Calc {
  _Calc(this.s);
  final String s;
  int i = 0;

  double run() {
    final v = _sum();
    _ws();
    if (i != s.length) throw const FormatException();
    return v;
  }

  void _ws() {
    while (i < s.length && s[i] == ' ') {
      i++;
    }
  }

  bool _eat(String c) {
    _ws();
    if (i < s.length && s[i] == c) {
      i++;
      return true;
    }
    return false;
  }

  double _sum() {
    var v = _prod();
    while (true) {
      if (_eat('+')) {
        v += _prod();
      } else if (_eat('-')) {
        v -= _prod();
      } else {
        return v;
      }
    }
  }

  double _prod() {
    var v = _unary();
    while (true) {
      if (_eat('*')) {
        v *= _unary();
      } else if (_eat('/')) {
        v /= _unary();
      } else {
        return v;
      }
    }
  }

  double _unary() {
    if (_eat('-')) return -_unary();
    if (_eat('+')) return _unary();
    final b = _atom();
    return _eat('^') ? math.pow(b, _unary()).toDouble() : b;
  }

  double _atom() {
    if (_eat('(')) {
      final v = _sum();
      if (!_eat(')')) throw const FormatException();
      return v;
    }
    _ws();
    final st = i;
    while (i < s.length && '0123456789.'.contains(s[i])) {
      i++;
    }
    if (st == i) throw const FormatException();
    return double.parse(s.substring(st, i));
  }
}
