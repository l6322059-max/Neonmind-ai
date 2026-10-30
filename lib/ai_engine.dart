import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ======================= Providers =======================

class AiProvider {
  const AiProvider(this.id, this.name, this.kind, this.baseUrl, this.model, this.keyHelp);
  final String id;
  final String name;
  final String kind; // anthropic | openai | gemini
  final String baseUrl;
  final String model;
  final String keyHelp;
}

const kProviders = [
  AiProvider('claude', 'Claude', 'anthropic', 'https://api.anthropic.com/v1', 'claude-haiku-5-5', 'console.anthropic.com'),
  AiProvider('openai', 'ChatGPT', 'openai', 'https://api.openai.com/v1', 'gpt-4.1-mini', 'platform.openai.com/api-keys'),
  AiProvider('gemini', 'Gemini', 'gemini', 'https://generativelanguage.googleapis.com/v1beta', 'gemini-3.5-flash', 'aistudio.google.com/apikey'),
  AiProvider('grok', 'Grok', 'openai', 'https://api.x.ai/v1', 'grok-3-mini', 'console.x.ai'),
  AiProvider('deepseek', 'DeepSeek', 'openai', 'https://api.deepseek.com/v1', 'deepseek-chat', 'platform.deepseek.com'),
  AiProvider('mistral', 'Mistral', 'openai', 'https://api.mistral.ai/v1', 'mistral-small-latest', 'console.mistral.ai'),
  AiProvider('groq', 'Groq', 'openai', 'https://api.groq.com/openai/v1', 'openai/gpt-oss-20b', 'console.groq.com/keys'),
  AiProvider('openrouter', 'OpenRouter', 'openai', 'https://openrouter.ai/api/v1', 'openai/gpt-4.1-mini', 'openrouter.ai/keys'),
  AiProvider('custom', 'Custom', 'openai', '', '', 'any OpenAI-compatible server'),
];

/// The AI's declaration: who it is and how it behaves. Editable in the Admin panel.
const kPersona =
    'You are NeonMind, a friendly, sharp AI assistant inside a neon-black Android app. '
    'Keep answers short enough to read on a phone, in plain text without markdown. '
    'If you are unsure, say so instead of guessing. '
    'The user can attach photos, PDFs and text files; use them. '
    'You cannot draw pictures yourself: if the user wants an image, tell them to type /image followed by a description. '
    'When the user asks for a file (a document, notes, code, CSV, etc.), create it by writing '
    '<file name="example.txt">file contents</file> in your reply, with your normal explanation outside the tags.';

// ======================= Data =======================

const kTextExt = {
  'txt', 'md', 'csv', 'json', 'xml', 'html', 'css', 'js', 'ts', 'dart', 'py', 'java',
  'kt', 'c', 'cpp', 'h', 'yaml', 'yml', 'log', 'sql', 'sh', 'ini', 'toml',
};

class Attachment {
  Attachment(this.name, this.bytes, this.mime);
  final String name;
  final Uint8List bytes;
  final String mime;
  bool get isImage => mime.startsWith('image/');
  bool get isPdf => mime == 'application/pdf';
  String get b64 => base64Encode(bytes);
}

class AiFile {
  AiFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

class Msg {
  Msg(
    this.fromUser,
    this.text, {
    this.atts = const [],
    this.files = const [],
    this.image,
    this.meta,
    this.error = false,
  }) : time = DateTime.now();
  final bool fromUser;
  final String text;
  final List<Attachment> atts;
  final List<AiFile> files;
  final Uint8List? image;
  final String? meta;
  final bool error;
  final DateTime time;
  bool revealed = false;
  bool entered = false;
}

class AiResult {
  AiResult(this.text, {this.files = const [], this.image, this.error = false, this.seconds = 0});
  final String text;
  final List<AiFile> files;
  final Uint8List? image;
  final bool error;
  final double seconds;
}

/// Detects the real file type from the first bytes, so the AI never gets a wrong label.
String sniffMime(Uint8List b, String name) {
  bool at(List<int> sig, [int off = 0]) {
    if (b.length < off + sig.length) return false;
    for (var i = 0; i < sig.length; i++) {
      if (b[off + i] != sig[i]) return false;
    }
    return true;
  }

  if (at([0x89, 0x50, 0x4E, 0x47])) return 'image/png';
  if (at([0xFF, 0xD8])) return 'image/jpeg';
  if (at([0x47, 0x49, 0x46])) return 'image/gif';
  if (at([0x52, 0x49, 0x46, 0x46]) && at([0x57, 0x45, 0x42, 0x50], 8)) return 'image/webp';
  if (at([0x25, 0x50, 0x44, 0x46])) return 'application/pdf';
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  return kTextExt.contains(ext) ? 'text/plain' : 'application/octet-stream';
}

// ======================= Settings =======================

class AiSettings {
  String providerId = 'claude';
  String customUrl = '';
  String persona = kPersona;
  bool rainbow = true;
  bool glass = true;
  bool typewriter = true;
  String imageModelOpenai = 'gpt-image-1';
  String imageModelGemini = 'gemini-3.1-flash-image';
  String adminPin = '';
  final Map<String, String> keys = {};
  final Map<String, String> models = {};
  Map<String, int> stats = {};

  AiProvider get provider => kProviders.firstWhere((p) => p.id == providerId, orElse: () => kProviders.first);
  String get apiKey => (keys[providerId] ?? '').trim();
  bool get online => apiKey.isNotEmpty;
  String get model {
    final m = (models[providerId] ?? '').trim();
    return m.isEmpty ? provider.model : m;
  }

  String get baseUrl => (providerId == 'custom' ? customUrl : provider.baseUrl).trim().replaceAll(RegExp(r'/+$'), '');

  void bump(String k, [int n = 1]) => stats[k] = (stats[k] ?? 0) + n;

  static Future<AiSettings> load() async {
    final p = await SharedPreferences.getInstance();
    final s = AiSettings()
      ..providerId = p.getString('provider') ?? 'claude'
      ..customUrl = p.getString('customUrl') ?? ''
      ..persona = p.getString('persona') ?? kPersona
      ..rainbow = p.getBool('rainbow') ?? true
      ..glass = p.getBool('glass') ?? true
      ..typewriter = p.getBool('typewriter') ?? true
      ..imageModelOpenai = p.getString('imgOpenai') ?? 'gpt-image-1'
      ..imageModelGemini = p.getString('imgGemini') ?? 'gemini-3.1-flash-image'
      ..adminPin = p.getString('adminPin') ?? '';
    for (final pr in kProviders) {
      s.keys[pr.id] = p.getString('key_${pr.id}') ?? '';
      s.models[pr.id] = p.getString('model_${pr.id}') ?? '';
    }
    if ((s.keys['claude'] ?? '').isEmpty) s.keys['claude'] = p.getString('apiKey') ?? '';
    try {
      s.stats = (jsonDecode(p.getString('stats') ?? '{}') as Map).map((k, v) => MapEntry(k as String, v as int));
    } catch (_) {}
    return s;
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('provider', providerId);
    await p.setString('customUrl', customUrl);
    await p.setString('persona', persona);
    await p.setBool('rainbow', rainbow);
    await p.setBool('glass', glass);
    await p.setBool('typewriter', typewriter);
    await p.setString('imgOpenai', imageModelOpenai);
    await p.setString('imgGemini', imageModelGemini);
    await p.setString('adminPin', adminPin);
    for (final pr in kProviders) {
      await p.setString('key_${pr.id}', keys[pr.id] ?? '');
      await p.setString('model_${pr.id}', models[pr.id] ?? '');
    }
    await saveStats();
  }

  Future<void> saveStats() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('stats', jsonEncode(stats));
  }

  Future<void> wipe() async {
    final p = await SharedPreferences.getInstance();
    await p.clear();
    providerId = 'claude';
    customUrl = '';
    persona = kPersona;
    rainbow = glass = typewriter = true;
    imageModelOpenai = 'gpt-image-1';
    imageModelGemini = 'gemini-3.1-flash-image';
    adminPin = '';
    keys.clear();
    models.clear();
    stats = {};
  }
}

/// Tiny hash for the local admin PIN (keeps the PIN from being stored in plain text).
String pinHash(String pin) {
  var h = 0x811C9DC5;
  for (final c in 'neon:$pin'.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF;
  }
  return h.toRadixString(16);
}

// ======================= Key check =======================

class KeyCheck {
  KeyCheck(this.ok, this.title, this.detail);
  final bool ok;
  final String title;
  final String detail;
}

Future<KeyCheck> checkKey(AiSettings s) async {
  final p = s.provider;
  final key = s.apiKey;
  final base = s.baseUrl;
  if (key.isEmpty) return KeyCheck(false, 'No key yet', 'Paste an API key first.');
  if (base.isEmpty) return KeyCheck(false, 'No server', 'Add a server URL for Custom first.');
  final Uri url;
  final Map<String, String> h;
  if (p.kind == 'anthropic') {
    url = Uri.parse('$base/models?limit=1');
    h = {'x-api-key': key, 'anthropic-version': '2023-06-01'};
  } else if (p.kind == 'gemini') {
    url = Uri.parse('$base/models?pageSize=1');
    h = {'x-goog-api-key': key};
  } else {
    url = Uri.parse('$base/models');
    h = {'authorization': 'Bearer $key'};
  }
  try {
    final r = await http.get(url, headers: h).timeout(const Duration(seconds: 20));
    if (r.statusCode == 401 || r.statusCode == 403 || (r.statusCode == 400 && p.kind == 'gemini')) {
      return KeyCheck(false, 'Key rejected', 'The key is wrong, revoked, or for a different AI.');
    }
    if (r.statusCode != 200) return KeyCheck(false, 'Could not verify', 'The server answered HTTP ${r.statusCode}.');
  } catch (_) {
    return KeyCheck(false, 'No connection', 'Could not reach ${p.name}. Check your internet.');
  }

  String? credit;
  try {
    if (s.providerId == 'deepseek') {
      final r = await http
          .get(Uri.parse('https://api.deepseek.com/user/balance'), headers: {'authorization': 'Bearer $key'})
          .timeout(const Duration(seconds: 15));
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      final b = (j['balance_infos'] as List).first;
      credit = '${b['total_balance']} ${b['currency']}${j['is_available'] == false ? ' (not enough to use)' : ''}';
    } else if (s.providerId == 'openrouter') {
      final r = await http
          .get(Uri.parse('$base/key'), headers: {'authorization': 'Bearer $key'})
          .timeout(const Duration(seconds: 15));
      final d = jsonDecode(utf8.decode(r.bodyBytes))['data'];
      credit = d['limit_remaining'] != null
          ? '\$${d['limit_remaining']} left (used \$${d['usage']})'
          : 'used \$${d['usage']} so far (no spending limit set)';
    }
  } catch (_) {}
  return KeyCheck(
    true,
    'Key works',
    credit != null
        ? 'Credit: $credit'
        : "${p.name} doesn't share your balance through API keys. Check it at ${p.keyHelp}.",
  );
}

// ======================= Engine =======================

typedef StatusFn = void Function(String step);

class _AiError implements Exception {
  _AiError(this.message);
  final String message;
}

class _Turn {
  _Turn(this.role, this.text);
  final String role;
  String text;
  final List<Attachment> atts = [];
}

class AiEngine {
  AiEngine(this.s);
  final AiSettings s;
  final _rng = math.Random();

  Future<void> _pause() => Future<void>.delayed(const Duration(milliseconds: 220));

  Future<AiResult> reply(List<Msg> history, StatusFn status) async {
    final sw = Stopwatch()..start();
    final last = history.last;
    status('Reading your message');
    await _pause();
    for (final a in last.atts) {
      status(a.isImage ? 'Looking at photo: ${a.name}' : 'Reading file: ${a.name}');
      await _pause();
    }
    double secs() => sw.elapsedMilliseconds / 1000;
    try {
      final img = RegExp(r'^/image\s+([\s\S]+)').firstMatch(last.text.trim());
      if (img != null) return await _image(img.group(1)!.trim(), status, sw);

      if (!s.online) {
        status('Offline brain is thinking');
        await Future<void>.delayed(const Duration(milliseconds: 600));
        if (last.atts.isNotEmpty) {
          return AiResult("I'm in offline mode, so I can't open attachments. Pick an AI and add its key in Settings.", seconds: secs());
        }
        return AiResult(_offline(last.text.toLowerCase()), seconds: secs());
      }
      final text = await _online(history, status);
      status('Writing the reply');
      return _split(text, secs());
    } catch (e) {
      return AiResult(
        e is _AiError ? e.message : 'Could not reach the model. Check your connection and try again.',
        error: true,
        seconds: secs(),
      );
    }
  }

  AiResult _split(String text, double secs) {
    final files = <AiFile>[];
    final clean = text.replaceAllMapped(RegExp(r'<file name="([^"]+)">\s*([\s\S]*?)\s*</file>'), (m) {
      files.add(AiFile(m[1]!.replaceAll(RegExp(r'[\\/]'), '_'), Uint8List.fromList(utf8.encode(m[2]!))));
      return '';
    }).trim();
    return AiResult(clean.isEmpty && files.isNotEmpty ? 'Here you go.' : clean, files: files, seconds: secs);
  }

  // ---------- chat ----------

  List<_Turn> _turns(List<Msg> history) {
    final recent = history.length > 20 ? history.sublist(history.length - 20) : history;
    final withAtts = [for (var i = 0; i < recent.length; i++) if (recent[i].fromUser && recent[i].atts.isNotEmpty) i];
    final keep = (withAtts.length > 2 ? withAtts.sublist(withAtts.length - 2) : withAtts).toSet();
    final out = <_Turn>[];
    for (var i = 0; i < recent.length; i++) {
      final m = recent[i];
      if (m.error) continue;
      final role = m.fromUser ? 'user' : 'assistant';
      var text = m.text;
      final atts = <Attachment>[];
      for (final a in m.atts) {
        if (keep.contains(i)) {
          atts.add(a);
        } else {
          text += '\n[Attached earlier: ${a.name}]';
        }
      }
      if (out.isEmpty && role != 'user') continue;
      if (out.isNotEmpty && out.last.role == role) {
        out.last.text += '\n\n$text';
        out.last.atts.addAll(atts);
      } else {
        out.add(_Turn(role, text)..atts.addAll(atts));
      }
    }
    return out;
  }

  String _fileText(Attachment a) {
    var t = utf8.decode(a.bytes, allowMalformed: true);
    if (t.length > 60000) t = '${t.substring(0, 60000)}\n[...truncated]';
    return '[File: ${a.name}]\n$t';
  }

  Future<String> _online(List<Msg> history, StatusFn status) async {
    final turns = _turns(history);
    final base = s.baseUrl;
    if (base.isEmpty) throw _AiError('Add a server URL for Custom in Settings.');
    final kind = s.provider.kind;
    final model = s.model.replaceFirst('models/', '');
    final persona = s.persona.trim().isEmpty ? kPersona : s.persona.trim();
    if (kind == 'openai' && turns.any((t) => t.atts.any((a) => a.isPdf))) {
      throw _AiError("This AI can't read PDFs here. Use Claude or Gemini, or send a photo or text file.");
    }

    final Uri url;
    final Map<String, String> headers;
    final Map<String, dynamic> body;
    if (kind == 'anthropic') {
      url = Uri.parse('$base/messages');
      headers = {'x-api-key': s.apiKey, 'anthropic-version': '2023-06-01'};
      body = {
        'model': model,
        'max_tokens': 4096,
        'system': persona,
        'messages': [
          for (final t in turns)
            {
              'role': t.role,
              'content': t.atts.isEmpty
                  ? t.text
                  : [
                      for (final a in t.atts)
                        if (a.isImage)
                          {'type': 'image', 'source': {'type': 'base64', 'media_type': a.mime, 'data': a.b64}}
                        else if (a.isPdf)
                          {'type': 'document', 'source': {'type': 'base64', 'media_type': a.mime, 'data': a.b64}}
                        else
                          {'type': 'text', 'text': _fileText(a)},
                      {'type': 'text', 'text': t.text},
                    ],
            },
        ],
      };
    } else if (kind == 'gemini') {
      url = Uri.parse('$base/models/$model:generateContent');
      headers = {'x-goog-api-key': s.apiKey};
      body = {
        'systemInstruction': {
          'parts': [
            {'text': persona}
          ]
        },
        'contents': [
          for (final t in turns)
            {
              'role': t.role == 'user' ? 'user' : 'model',
              'parts': [
                for (final a in t.atts)
                  if (a.isImage || a.isPdf) {'inlineData': {'mimeType': a.mime, 'data': a.b64}} else {'text': _fileText(a)},
                {'text': t.text},
              ],
            },
        ],
      };
    } else {
      url = Uri.parse('$base/chat/completions');
      headers = {'authorization': 'Bearer ${s.apiKey}'};
      body = {
        'model': model,
        'messages': [
          {'role': 'system', 'content': persona},
          for (final t in turns)
            {
              'role': t.role,
              'content': t.atts.isEmpty
                  ? t.text
                  : [
                      {'type': 'text', 'text': t.text},
                      for (final a in t.atts)
                        if (a.isImage)
                          {'type': 'image_url', 'image_url': {'url': 'data:${a.mime};base64,${a.b64}'}}
                        else
                          {'type': 'text', 'text': _fileText(a)},
                    ],
            },
        ],
      };
    }

    status('Sending to ${s.provider.name} · $model');
    final req = http.post(url, headers: {'content-type': 'application/json', ...headers}, body: jsonEncode(body));
    status('Waiting for ${s.provider.name} to answer');
    final res = await req.timeout(const Duration(seconds: 120));
    final raw = utf8.decode(res.bodyBytes);
    if (res.statusCode != 200) throw _AiError(_errorText(res.statusCode, raw));
    status('Got the answer');

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
    var detail = 'Request failed (HTTP $code).';
    try {
      detail = jsonDecode(raw)['error']['message'] as String;
    } catch (_) {}
    final low = detail.toLowerCase();
    if (code == 401 || code == 403) return 'Your API key was rejected. Check the key and provider in Settings.';
    if (code == 404) return 'Model or server not found. Check the model name in Settings.';
    if (code == 402 || low.contains('insufficient') || low.contains('credit balance') || low.contains('billing') || low.contains('quota')) {
      return 'No credit or quota left on ${s.provider.name}. Add funds at ${s.provider.keyHelp}.';
    }
    return code == 429 ? 'Too many requests right now: $detail' : detail;
  }

  // ---------- images (/image your prompt) ----------

  Future<AiResult> _image(String prompt, StatusFn status, Stopwatch sw) async {
    if (!s.online) throw _AiError('Add an API key in Settings first. Image creation works with ChatGPT or Gemini.');
    final kind = s.provider.kind;
    if (s.providerId != 'openai' && kind != 'gemini') {
      throw _AiError('Image creation works with ChatGPT or Gemini. Switch the AI in Settings.');
    }
    status('Painting your image with ${s.provider.name}');
    Uint8List? bytes;
    if (kind == 'gemini') {
      final res = await http
          .post(
            Uri.parse('${s.baseUrl}/models/${s.imageModelGemini}:generateContent'),
            headers: {'content-type': 'application/json', 'x-goog-api-key': s.apiKey},
            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {'text': prompt}
                  ]
                }
              ],
              'generationConfig': {
                'responseModalities': ['TEXT', 'IMAGE']
              },
            }),
          )
          .timeout(const Duration(seconds: 150));
      final raw = utf8.decode(res.bodyBytes);
      if (res.statusCode != 200) throw _AiError(_errorText(res.statusCode, raw));
      final c = (jsonDecode(raw)['candidates'] as List?) ?? [];
      final parts = c.isEmpty ? [] : ((c[0]['content']?['parts'] as List?) ?? []);
      for (final p in parts) {
        final d = p['inlineData'] ?? p['inline_data'];
        if (d != null) {
          bytes = base64Decode(d['data'] as String);
          break;
        }
      }
    } else {
      final res = await http
          .post(
            Uri.parse('${s.baseUrl}/images/generations'),
            headers: {'content-type': 'application/json', 'authorization': 'Bearer ${s.apiKey}'},
            body: jsonEncode({'model': s.imageModelOpenai, 'prompt': prompt, 'size': '1024x1024'}),
          )
          .timeout(const Duration(seconds: 150));
      final raw = utf8.decode(res.bodyBytes);
      if (res.statusCode != 200) throw _AiError(_errorText(res.statusCode, raw));
      final d = (jsonDecode(raw)['data'] as List).first;
      if (d['b64_json'] != null) {
        bytes = base64Decode(d['b64_json'] as String);
      } else if (d['url'] != null) {
        bytes = (await http.get(Uri.parse(d['url'] as String))).bodyBytes;
      }
    }
    if (bytes == null) {
      throw _AiError('No image came back. The model may have refused the prompt, or the image model name needs changing in Admin.');
    }
    return AiResult('Here is your image.', image: bytes, seconds: sw.elapsedMilliseconds / 1000);
  }

  // ---------- offline brain ----------

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
      return 'Offline, I can do math (try "24 * 7 + 3"), tell the time and date, and tell jokes. For full AI answers, photos and files, add an API key in Settings.';
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
