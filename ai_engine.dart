import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const kDefaultModel = 'claude-haiku-5-5';

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
  String apiKey = '';
  String model = kDefaultModel;

  static Future<AiSettings> load() async {
    final p = await SharedPreferences.getInstance();
    return AiSettings()
      ..apiKey = p.getString('apiKey') ?? ''
      ..model = p.getString('model') ?? kDefaultModel;
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('apiKey', apiKey);
    await p.setString('model', model);
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
    final recent =
        history.length > 20 ? history.sublist(history.length - 20) : history;
    final msgs = <Map<String, String>>[];
    for (final m in recent) {
      final role = m.fromUser ? 'user' : 'assistant';
      if (msgs.isEmpty && role != 'user') continue;
      if (msgs.isNotEmpty && msgs.last['role'] == role) {
        msgs.last['content'] = '${msgs.last['content']}\n\n${m.text}';
      } else {
        msgs.add({'role': role, 'content': m.text});
      }
    }
    final res = await http
        .post(
          Uri.parse('https://api.anthropic.com/v1/messages'),
          headers: {
            'content-type': 'application/json',
            'x-api-key': s.apiKey.trim(),
            'anthropic-version': '2023-06-01',
          },
          body: jsonEncode({
            'model': s.model,
            'max_tokens': 1024,
            'system': kPersona,
            'messages': msgs,
          }),
        )
        .timeout(const Duration(seconds: 60));
    final body = utf8.decode(res.bodyBytes);
    if (res.statusCode != 200) {
      var detail = 'Request failed (HTTP ${res.statusCode}).';
      if (res.statusCode == 401) {
        detail = 'Your API key was rejected. Check it in Settings.';
      } else {
        try {
          detail = jsonDecode(body)['error']['message'] as String;
        } catch (_) {}
      }
      throw _AiError(detail);
    }
    final blocks = jsonDecode(body)['content'] as List;
    final text = blocks
        .where((b) => b['type'] == 'text')
        .map((b) => b['text'] as String)
        .join('\n')
        .trim();
    if (text.isEmpty) throw _AiError('The model sent an empty answer.');
    return text;
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
      return "I'm NeonMind, an AI assistant that lives on your phone. Offline I handle math, time, and a few tricks. Add an API key in Settings and I can answer almost anything.";
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
