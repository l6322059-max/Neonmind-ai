import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ai_engine.dart';

const kBlack = Color(0xFF000000);
const kSurface = Color(0xFF0B0B12);
const kCyan = Color(0xFF00F0FF);
const kPink = Color(0xFFFF2BD6);
const kText = Color(0xFFE8F9FF);
const kMuted = Color(0xFF6F7C93);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: kBlack,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(const NeonMindApp());
}

class NeonMindApp extends StatelessWidget {
  const NeonMindApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'NeonMind',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: kBlack,
          colorScheme: const ColorScheme.dark(primary: kCyan, secondary: kPink, surface: kSurface),
          textSelectionTheme: const TextSelectionThemeData(
            cursorColor: kCyan,
            selectionColor: Color(0x5500F0FF),
            selectionHandleColor: kCyan,
          ),
        ),
        home: const ChatPage(),
      );
}

List<Shadow> glow(Color c) => [Shadow(color: c, blurRadius: 14)];

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with SingleTickerProviderStateMixin {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  late final AnimationController _pulse;
  AiSettings _settings = AiSettings();
  late AiEngine _engine;
  final List<Msg> _msgs = [];
  bool _thinking = false;

  @override
  void initState() {
    super.initState();
    _engine = AiEngine(_settings);
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))
      ..repeat(reverse: true);
    _focus.addListener(() => setState(() {}));
    AiSettings.load().then((s) {
      if (!mounted) return;
      setState(() {
        _settings = s;
        _engine = AiEngine(s);
      });
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        }
      });

  void _speed(int ms) {
    _pulse.duration = Duration(milliseconds: ms);
    _pulse.repeat(reverse: true);
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _thinking) return;
    HapticFeedback.lightImpact();
    _input.clear();
    setState(() {
      _msgs.add(Msg(true, text));
      _thinking = true;
    });
    _speed(700);
    _toBottom();
    final answer = await _engine.reply(List<Msg>.of(_msgs));
    if (!mounted) return;
    setState(() {
      _msgs.add(Msg(false, answer));
      _thinking = false;
    });
    _speed(2200);
    _toBottom();
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SettingsPage(settings: _settings, onClear: () => setState(_msgs.clear)),
    ));
    if (mounted) setState(() => _engine = AiEngine(_settings));
  }

  @override
  Widget build(BuildContext context) {
    final online = _settings.apiKey.trim().isNotEmpty;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 6, 12),
            child: Row(children: [
              Orb(animation: _pulse),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('NeonMind',
                      style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: kText, shadows: glow(kCyan))),
                  Text(online ? 'Online · ${_settings.model}' : 'Offline brain · no key needed',
                      style: const TextStyle(fontSize: 12.5, color: kMuted)),
                ]),
              ),
              IconButton(onPressed: _openSettings, icon: const Icon(Icons.tune_rounded, color: kCyan)),
            ]),
          ),
          Container(
            height: 1.5,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [kCyan, kPink]),
              boxShadow: [BoxShadow(color: kCyan.withValues(alpha: .5), blurRadius: 10)],
            ),
          ),
          Expanded(child: _msgs.isEmpty && !_thinking ? _empty(online) : _list()),
          _composer(),
        ]),
      ),
    );
  }

  Widget _empty(bool online) {
    final ideas = online
        ? ['Explain black holes simply', 'Write a 4-line poem about neon', 'Plan my day in 5 steps']
        : ['What time is it?', 'Calculate (24 * 7) + 3', 'Tell me a joke'];
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text("Hi, I'm NeonMind.",
              style: TextStyle(fontSize: 27, fontWeight: FontWeight.w700, color: kText, shadows: glow(kPink))),
          const SizedBox(height: 10),
          const Text('Ask a question or pick one below.', style: TextStyle(color: kMuted, fontSize: 15)),
          const SizedBox(height: 26),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [for (final t in ideas) _chip(t)],
          ),
          if (!online) ...[
            const SizedBox(height: 26),
            GestureDetector(
              onTap: _openSettings,
              child: const Text('Add an API key in Settings for full AI answers',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: kCyan, fontSize: 13.5, decoration: TextDecoration.underline, decorationColor: kCyan)),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _chip(String t) => InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _send(t),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: kCyan.withValues(alpha: .55)),
            boxShadow: [BoxShadow(color: kCyan.withValues(alpha: .15), blurRadius: 10)],
          ),
          child: Text(t, style: const TextStyle(color: kText, fontSize: 14)),
        ),
      );

  Widget _list() => ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(10, 14, 10, 8),
        itemCount: _msgs.length + (_thinking ? 1 : 0),
        itemBuilder: (_, i) => i == _msgs.length ? const TypingBubble() : Bubble(msg: _msgs[i]),
      );

  Widget _composer() {
    final focused = _focus.hasFocus;
    OutlineInputBorder border(double a, double w) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(26),
          borderSide: BorderSide(color: kCyan.withValues(alpha: a), width: w),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              boxShadow: focused ? [BoxShadow(color: kCyan.withValues(alpha: .3), blurRadius: 16)] : const [],
            ),
            child: TextField(
              controller: _input,
              focusNode: _focus,
              minLines: 1,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(color: kText, fontSize: 16),
              decoration: InputDecoration(
                hintText: 'Message NeonMind',
                hintStyle: const TextStyle(color: kMuted),
                filled: true,
                fillColor: kSurface,
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                border: border(.3, 1),
                enabledBorder: border(.3, 1),
                focusedBorder: border(1, 1.4),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: () => _send(),
          child: Opacity(
            opacity: _thinking ? .4 : 1,
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: kCyan.withValues(alpha: .14),
                border: Border.all(color: kCyan, width: 1.4),
                boxShadow: [BoxShadow(color: kCyan.withValues(alpha: .4), blurRadius: 14)],
              ),
              child: const Icon(Icons.arrow_upward_rounded, color: kCyan),
            ),
          ),
        ),
      ]),
    );
  }
}

class Orb extends StatelessWidget {
  const Orb({super.key, required this.animation});
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: animation,
        builder: (_, __) {
          final t = Curves.easeInOut.transform(animation.value);
          return Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                colors: [Colors.white, kCyan, Color(0xFF007C8A)],
                stops: [0.0, 0.35, 1.0],
              ),
              boxShadow: [
                BoxShadow(color: kCyan.withValues(alpha: .35 + .35 * t), blurRadius: 10 + 16 * t, spreadRadius: 1 + 2 * t),
              ],
            ),
          );
        },
      );
}

class Bubble extends StatelessWidget {
  const Bubble({super.key, required this.msg});
  final Msg msg;

  @override
  Widget build(BuildContext context) {
    final c = msg.fromUser ? kPink : kCyan;
    final big = Radius.circular(18);
    final small = Radius.circular(4);
    return Align(
      alignment: msg.fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .82),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: c.withValues(alpha: .08),
          border: Border.all(color: c.withValues(alpha: .75)),
          borderRadius: BorderRadius.only(
            topLeft: big,
            topRight: big,
            bottomLeft: msg.fromUser ? big : small,
            bottomRight: msg.fromUser ? small : big,
          ),
          boxShadow: [BoxShadow(color: c.withValues(alpha: .22), blurRadius: 14)],
        ),
        child: SelectableText(msg.text, style: const TextStyle(color: kText, fontSize: 15.5, height: 1.4)),
      ),
    );
  }
}

class TypingBubble extends StatefulWidget {
  const TypingBubble({super.key});

  @override
  State<TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<TypingBubble> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: kCyan.withValues(alpha: .5)),
          ),
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, __) => Row(mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < 3; i++)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: kCyan.withValues(alpha: .25 + .75 * (math.sin((_c.value - i * .2) * 2 * math.pi) + 1) / 2),
                  ),
                ),
            ]),
          ),
        ),
      );
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.settings, required this.onClear});
  final AiSettings settings;
  final VoidCallback onClear;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final _key = TextEditingController(text: widget.settings.apiKey);
  late final _model = TextEditingController(text: widget.settings.model);
  bool _hide = true;

  InputDecoration _dec(String label, {Widget? suffix}) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: kMuted),
        suffixIcon: suffix,
        filled: true,
        fillColor: kSurface,
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: kCyan.withValues(alpha: .3))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: kCyan, width: 1.4)),
      );

  Future<void> _save() async {
    widget.settings
      ..apiKey = _key.text.trim()
      ..model = _model.text.trim().isEmpty ? kDefaultModel : _model.text.trim();
    await widget.settings.save();
    if (mounted) Navigator.of(context).pop();
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
            'Paste an Anthropic API key to get full AI answers. Leave it empty to use the built-in offline brain.',
            style: TextStyle(color: kMuted, height: 1.4),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _key,
            obscureText: _hide,
            autocorrect: false,
            style: const TextStyle(color: kText),
            decoration: _dec('API key',
                suffix: IconButton(
                  onPressed: () => setState(() => _hide = !_hide),
                  icon: Icon(_hide ? Icons.visibility_off : Icons.visibility, color: kMuted),
                )),
          ),
          const SizedBox(height: 14),
          TextField(controller: _model, autocorrect: false, style: const TextStyle(color: kText), decoration: _dec('Model')),
          const SizedBox(height: 20),
          NeonButton(label: 'Save', color: kCyan, onTap: _save),
          const SizedBox(height: 12),
          NeonButton(
            label: 'Clear chat',
            color: kPink,
            onTap: () {
              widget.onClear();
              Navigator.of(context).pop();
            },
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: kMuted.withValues(alpha: .4))),
            child: const Text(
              'About NeonMind\n\n'
              'NeonMind is an AI assistant and can make mistakes, so double-check anything important. '
              'Chats stay on your phone unless you add an API key; then your messages are sent to the Anthropic API to get answers. '
              'Your key is stored only on this device.',
              style: TextStyle(color: kMuted, height: 1.45, fontSize: 13.5),
            ),
          ),
        ]),
      );
}

class NeonButton extends StatelessWidget {
  const NeonButton({super.key, required this.label, required this.color, required this.onTap});
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: color.withValues(alpha: .3), blurRadius: 16)],
        ),
        child: Material(
          color: color.withValues(alpha: .12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: color, width: 1.2)),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Center(child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 15))),
            ),
          ),
        ),
      );
}
