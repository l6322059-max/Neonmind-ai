import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ai_engine.dart';
import 'effects.dart';

// ======================= Shared helpers =======================

Future<T?> neonDialog<T>(BuildContext context, Widget child) => showDialog<T>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .7),
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: Glass(radius: 24, blur: 24, tint: kCyan, padding: const EdgeInsets.all(22), child: child),
      ),
    );

InputDecoration neonField(String label, {String? hint, Widget? suffix, String? error}) => InputDecoration(
      labelText: label,
      hintText: hint,
      errorText: error,
      hintStyle: TextStyle(color: kMuted.withValues(alpha: .6)),
      labelStyle: const TextStyle(color: kMuted),
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.white.withValues(alpha: .05),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: kCyan.withValues(alpha: .3))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: kCyan, width: 1.4)),
    );

/// Runs the key check and shows the result (and the credit, when the provider shares it).
Future<void> showKeyCheck(BuildContext context, AiSettings s) => neonDialog<void>(
      context,
      FutureBuilder<KeyCheck>(
        future: checkKey(s),
        builder: (ctx, snap) {
          if (!snap.hasData) {
            return const Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(width: 30, height: 30, child: CircularProgressIndicator(strokeWidth: 2.5, color: kCyan)),
              SizedBox(height: 16),
              Text('Checking your key…', style: TextStyle(color: kText)),
            ]);
          }
          final r = snap.data!;
          final c = r.ok ? const Color(0xFF3DFF9E) : kPink;
          return Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(r.ok ? Icons.check_circle_rounded : Icons.error_rounded, color: c, size: 44),
            const SizedBox(height: 12),
            Text(r.title, style: TextStyle(color: c, fontSize: 20, fontWeight: FontWeight.w700, shadows: glow(c))),
            const SizedBox(height: 8),
            Text(r.detail, textAlign: TextAlign.center, style: const TextStyle(color: kText, height: 1.4)),
            const SizedBox(height: 18),
            NeonButton(label: 'OK', color: kCyan, onTap: () => Navigator.of(ctx).pop()),
          ]);
        },
      ),
    );

/// Asks for the admin PIN (or creates one the first time). Returns true when unlocked.
Future<bool> askPin(BuildContext context, AiSettings s) async {
  final creating = s.adminPin.isEmpty;
  final c = TextEditingController();
  String? err;
  final ok = await neonDialog<bool>(
    context,
    StatefulBuilder(
      builder: (ctx, set) => Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.shield_rounded, color: kYellow, size: 40),
        const SizedBox(height: 10),
        Text(creating ? 'Create your admin PIN' : 'Admin PIN',
            style: TextStyle(color: kText, fontSize: 19, fontWeight: FontWeight.w700, shadows: glow(kYellow))),
        const SizedBox(height: 6),
        Text(creating ? 'Choose 4 to 8 digits. It locks the Admin panel on this phone.' : 'Enter your PIN to continue.',
            textAlign: TextAlign.center, style: const TextStyle(color: kMuted, fontSize: 13)),
        const SizedBox(height: 16),
        TextField(
          controller: c,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 8,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textAlign: TextAlign.center,
          style: const TextStyle(color: kText, fontSize: 22, letterSpacing: 8),
          decoration: neonField('PIN', error: err).copyWith(counterText: ''),
        ),
        const SizedBox(height: 14),
        NeonButton(
          label: creating ? 'Create PIN' : 'Unlock',
          color: kYellow,
          onTap: () {
            if (creating) {
              if (c.text.length < 4) return set(() => err = 'Use at least 4 digits');
              s.adminPin = pinHash(c.text);
              s.save();
              Navigator.of(ctx).pop(true);
            } else if (pinHash(c.text) == s.adminPin) {
              Navigator.of(ctx).pop(true);
            } else {
              HapticFeedback.heavyImpact();
              set(() => err = 'Wrong PIN');
            }
          },
        ),
      ]),
    ),
  );
  c.dispose();
  return ok == true;
}

// ======================= Settings =======================

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.settings,
    required this.adminUnlocked,
    required this.onAdminUnlocked,
    required this.onClear,
    required this.getMsgs,
  });
  final AiSettings settings;
  final bool adminUnlocked;
  final VoidCallback onAdminUnlocked;
  final VoidCallback onClear;
  final List<Msg> Function() getMsgs;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late String _pid = widget.settings.providerId;
  late final Map<String, String> _keys = Map.of(widget.settings.keys);
  late final Map<String, String> _models = Map.of(widget.settings.models);
  late final _key = TextEditingController(text: _keys[_pid] ?? '');
  late final _model = TextEditingController(text: _models[_pid] ?? '');
  late final _url = TextEditingController(text: widget.settings.customUrl);
  bool _hide = true;

  AiProvider get _p => kProviders.firstWhere((p) => p.id == _pid);

  @override
  void dispose() {
    _key.dispose();
    _model.dispose();
    _url.dispose();
    super.dispose();
  }

  void _pick(String id) {
    _keys[_pid] = _key.text;
    _models[_pid] = _model.text;
    setState(() {
      _pid = id;
      _key.text = _keys[id] ?? '';
      _model.text = _models[id] ?? '';
    });
  }

  Future<void> _apply() async {
    _keys[_pid] = _key.text.trim();
    _models[_pid] = _model.text.trim();
    final s = widget.settings;
    s.providerId = _pid;
    s.customUrl = _url.text.trim();
    s.keys
      ..clear()
      ..addAll(_keys);
    s.models
      ..clear()
      ..addAll(_models);
    await s.save();
  }

  Future<void> _save() async {
    final oldKey = (widget.settings.keys[_pid] ?? '').trim();
    final newKey = _key.text.trim();
    await _apply();
    if (!mounted) return;
    if (newKey.isNotEmpty && newKey != oldKey) await showKeyCheck(context, widget.settings);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _check() async {
    await _apply();
    if (mounted) await showKeyCheck(context, widget.settings);
  }

  Future<void> _admin() async {
    final s = widget.settings;
    final ok = widget.adminUnlocked || await askPin(context, s);
    if (!ok || !mounted) return;
    widget.onAdminUnlocked();
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => AdminPage(settings: s, onClear: widget.onClear, getMsgs: widget.getMsgs),
    ));
    if (mounted) setState(() {});
  }

  Widget _chip(AiProvider p) {
    final on = p.id == _pid;
    final hasKey = (_keys[p.id] ?? '').trim().isNotEmpty;
    return GestureDetector(
      onTap: () => _pick(p.id),
      child: Glass(
        radius: 20,
        blur: 0,
        tint: on ? kCyan : null,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(p.name, style: TextStyle(color: on ? kText : kMuted, fontSize: 14, fontWeight: on ? FontWeight.w700 : FontWeight.w400)),
          if (hasKey) ...[
            const SizedBox(width: 6),
            const Icon(Icons.check_circle, size: 14, color: kPink),
          ],
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          backgroundColor: kBlack,
          scrolledUnderElevation: 0,
          title: Text('Settings', style: TextStyle(color: kText, shadows: glow(kCyan))),
        ),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          const Text(
            'Choose an AI and paste its API key. Each AI keeps its own key and model. With no key, the offline brain answers.',
            style: TextStyle(color: kMuted, height: 1.4),
          ),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: [for (final p in kProviders) _chip(p)]),
          const SizedBox(height: 18),
          if (_pid == 'custom') ...[
            TextField(
              controller: _url,
              autocorrect: false,
              keyboardType: TextInputType.url,
              style: const TextStyle(color: kText),
              decoration: neonField('Server URL', hint: 'https://your-server.com/v1'),
            ),
            const SizedBox(height: 14),
          ],
          TextField(
            controller: _key,
            obscureText: _hide,
            autocorrect: false,
            enableSuggestions: false,
            style: const TextStyle(color: kText),
            decoration: neonField('${_p.name} API key',
                suffix: IconButton(
                  onPressed: () => setState(() => _hide = !_hide),
                  icon: Icon(_hide ? Icons.visibility_off : Icons.visibility, color: kMuted),
                )),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text('Get a key: ${_p.keyHelp}', style: const TextStyle(color: kCyan, fontSize: 12.5)),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _model,
            autocorrect: false,
            style: const TextStyle(color: kText),
            decoration: neonField('Model', hint: _p.model.isEmpty ? 'model name' : _p.model),
          ),
          const SizedBox(height: 20),
          NeonButton(label: 'Save', color: kCyan, icon: Icons.check_rounded, onTap: _save),
          const SizedBox(height: 12),
          NeonButton(label: 'Check key and credit', color: const Color(0xFF3DFF9E), icon: Icons.verified_rounded, onTap: _check),
          const SizedBox(height: 12),
          NeonButton(
            label: 'Clear chat',
            color: kPink,
            icon: Icons.delete_sweep_rounded,
            onTap: () {
              widget.onClear();
              Navigator.of(context).pop();
            },
          ),
          const SizedBox(height: 12),
          NeonButton(label: widget.adminUnlocked ? 'Admin panel (unlocked)' : 'Admin panel', color: kYellow, icon: Icons.shield_rounded, onTap: _admin),
          const SizedBox(height: 26),
          Glass(
            radius: 16,
            blur: 0,
            padding: const EdgeInsets.all(16),
            child: const Text(
              'About NeonMind\n\n'
              'NeonMind is an AI assistant and can make mistakes, so double-check anything important. '
              'Chats stay on your phone unless you add an API key; then your messages, photos and files are sent to the AI company you picked to get answers. '
              'Your keys are stored only on this device.',
              style: TextStyle(color: kMuted, height: 1.45, fontSize: 13.5),
            ),
          ),
        ]),
      );
}

// ======================= Admin panel =======================

class AdminPage extends StatefulWidget {
  const AdminPage({super.key, required this.settings, required this.onClear, required this.getMsgs});
  final AiSettings settings;
  final VoidCallback onClear;
  final List<Msg> Function() getMsgs;

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  AiSettings get s => widget.settings;
  late final _persona = TextEditingController(text: s.persona);
  late final _imgOpenai = TextEditingController(text: s.imageModelOpenai);
  late final _imgGemini = TextEditingController(text: s.imageModelGemini);

  @override
  void dispose() {
    _persona.dispose();
    _imgOpenai.dispose();
    _imgGemini.dispose();
    super.dispose();
  }

  void _snack(String t) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(t), backgroundColor: kSurface, behavior: SnackBarBehavior.floating));

  Future<void> _savePrompt() async {
    s.persona = _persona.text.trim().isEmpty ? kPersona : _persona.text.trim();
    s.imageModelOpenai = _imgOpenai.text.trim().isEmpty ? 'gpt-image-1' : _imgOpenai.text.trim();
    s.imageModelGemini = _imgGemini.text.trim().isEmpty ? 'gemini-3.1-flash-image' : _imgGemini.text.trim();
    await s.save();
    _snack('Saved');
  }

  Future<void> _export() async {
    final b = StringBuffer('NeonMind chat export\n\n');
    for (final m in widget.getMsgs()) {
      b.writeln('[${m.time.toIso8601String()}] ${m.fromUser ? 'You' : 'AI'}: ${m.text}');
      for (final a in m.atts) {
        b.writeln('   (attached: ${a.name})');
      }
      for (final f in m.files) {
        b.writeln('   (AI file: ${f.name})');
      }
      b.writeln();
    }
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Export chat',
        fileName: 'neonmind-chat.txt',
        bytes: Uint8List.fromList(utf8.encode(b.toString())),
      );
      if (path != null) _snack('Exported');
    } catch (_) {
      _snack('Could not export.');
    }
  }

  Future<void> _changePin() async {
    s.adminPin = '';
    final ok = await askPin(context, s);
    if (ok) _snack('PIN changed');
  }

  Future<void> _wipe() async {
    final yes = await neonDialog<bool>(
      context,
      Builder(
        builder: (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.warning_rounded, color: kPink, size: 40),
          const SizedBox(height: 10),
          const Text('Erase everything?', style: TextStyle(color: kText, fontSize: 19, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text('This deletes all keys, settings, stats, your PIN and the chat on this phone.',
              textAlign: TextAlign.center, style: TextStyle(color: kMuted, height: 1.4)),
          const SizedBox(height: 18),
          NeonButton(label: 'Erase', color: kPink, onTap: () => Navigator.of(ctx).pop(true)),
          const SizedBox(height: 10),
          NeonButton(label: 'Cancel', color: kCyan, onTap: () => Navigator.of(ctx).pop(false)),
        ]),
      ),
    );
    if (yes != true) return;
    await s.wipe();
    gRainbow = true;
    gGlass = true;
    widget.onClear();
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Widget _stat(String label, String value, Color c) => SizedBox(
        width: (MediaQuery.of(context).size.width - 40 - 20) / 3,
        child: Glass(
          radius: 16,
          blur: 0,
          tint: c,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Column(children: [
            Text(value, style: TextStyle(color: c, fontSize: 22, fontWeight: FontWeight.w800, shadows: glow(c))),
            const SizedBox(height: 4),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(color: kMuted, fontSize: 11.5)),
          ]),
        ),
      );

  Widget _switch(String title, String sub, bool v, void Function(bool) on) => SwitchListTile(
        value: v,
        onChanged: (x) {
          on(x);
          gRainbow = s.rainbow;
          gGlass = s.glass;
          s.save();
          setState(() {});
        },
        activeColor: kCyan,
        contentPadding: EdgeInsets.zero,
        title: Text(title, style: const TextStyle(color: kText, fontSize: 15)),
        subtitle: Text(sub, style: const TextStyle(color: kMuted, fontSize: 12.5)),
      );

  Widget _title(String t) => Padding(
        padding: const EdgeInsets.only(top: 26, bottom: 10),
        child: Text(t, style: TextStyle(color: kYellow, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1.4, shadows: glow(kYellow))),
      );

  @override
  Widget build(BuildContext context) {
    final st = s.stats;
    final replies = st['replies'] ?? 0;
    final avg = replies == 0 ? '—' : '${((st['ms'] ?? 0) / replies / 1000).toStringAsFixed(1)}s';
    final perProvider = [
      for (final e in st.entries)
        if (e.key.startsWith('provider_')) '${e.key.substring(9)}: ${e.value}'
    ];
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kBlack,
        scrolledUnderElevation: 0,
        title: Row(children: [
          const Icon(Icons.shield_rounded, color: kYellow),
          const SizedBox(width: 10),
          Text('Admin', style: TextStyle(color: kText, shadows: glow(kYellow))),
        ]),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 30), children: [
        _title('USAGE'),
        Wrap(spacing: 10, runSpacing: 10, children: [
          _stat('Messages sent', '${st['sent'] ?? 0}', kCyan),
          _stat('AI replies', '$replies', kPink),
          _stat('Avg reply', avg, kYellow),
          _stat('Attachments', '${st['attachments'] ?? 0}', kCyan),
          _stat('AI files', '${st['aiFiles'] ?? 0}', kPink),
          _stat('AI images', '${st['aiImages'] ?? 0}', kYellow),
        ]),
        const SizedBox(height: 10),
        Text('Errors: ${st['errors'] ?? 0}${perProvider.isEmpty ? '' : '   ·   ${perProvider.join('   ')}'}',
            style: const TextStyle(color: kMuted, fontSize: 12.5)),
        _title('EFFECTS'),
        _switch('Rainbow light', 'Animated rainbow borders and glow', s.rainbow, (x) => s.rainbow = x),
        _switch('Liquid glass', 'Frosted blur and the drifting aurora', s.glass, (x) => s.glass = x),
        _switch('Typewriter replies', 'AI answers appear letter by letter', s.typewriter, (x) => s.typewriter = x),
        _title('AI DECLARATION (SYSTEM PROMPT)'),
        TextField(
          controller: _persona,
          minLines: 5,
          maxLines: 10,
          style: const TextStyle(color: kText, fontSize: 13.5, height: 1.4),
          decoration: neonField('Who the AI is and how it behaves'),
        ),
        const SizedBox(height: 10),
        NeonButton(
          label: 'Reset to default',
          color: kMuted,
          onTap: () => setState(() => _persona.text = kPersona),
        ),
        _title('IMAGE MODELS (for /image)'),
        TextField(controller: _imgOpenai, autocorrect: false, style: const TextStyle(color: kText), decoration: neonField('ChatGPT image model')),
        const SizedBox(height: 12),
        TextField(controller: _imgGemini, autocorrect: false, style: const TextStyle(color: kText), decoration: neonField('Gemini image model')),
        const SizedBox(height: 14),
        NeonButton(label: 'Save prompt and models', color: kCyan, icon: Icons.check_rounded, onTap: _savePrompt),
        _title('TOOLS'),
        NeonButton(label: 'Export chat (.txt)', color: kCyan, icon: Icons.ios_share_rounded, onTap: _export),
        const SizedBox(height: 12),
        NeonButton(label: 'Change PIN', color: kYellow, icon: Icons.pin_rounded, onTap: _changePin),
        const SizedBox(height: 12),
        NeonButton(label: 'Erase all data', color: kPink, icon: Icons.delete_forever_rounded, onTap: _wipe),
        const SizedBox(height: 24),
        const Text(
          'The admin PIN only locks this panel on this phone. It is not an online account.',
          style: TextStyle(color: kMuted, fontSize: 12, height: 1.4),
        ),
      ]),
    );
  }
}
