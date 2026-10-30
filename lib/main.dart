import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'admin.dart';
import 'ai_engine.dart';
import 'effects.dart';

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

class _Act {
  const _Act(this.icon, this.label, this.color, this.run);
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback run;
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with TickerProviderStateMixin {
  static const _hints = ['Message NeonMind', 'Ask me anything…', 'Send a photo with +', 'Try /image a neon city'];

  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  final _picker = ImagePicker();
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();
  late final AnimationController _bg = AnimationController(vsync: this, duration: const Duration(seconds: 40))..repeat();
  late final AnimationController _menu = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
  Timer? _hintTimer;

  AiSettings _settings = AiSettings();
  late AiEngine _engine;
  final List<Msg> _msgs = [];
  final List<Attachment> _staged = [];
  final List<String> _steps = [];
  DateTime _start = DateTime.now();
  bool _thinking = false;
  bool _menuOpen = false;
  bool _admin = false;
  int _hint = 0;

  @override
  void initState() {
    super.initState();
    _engine = AiEngine(_settings);
    _focus.addListener(() => setState(() {}));
    _input.addListener(() => setState(() {}));
    _hintTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted && _input.text.isEmpty) setState(() => _hint = (_hint + 1) % _hints.length);
    });
    AiSettings.load().then((s) {
      if (!mounted) return;
      _applyFx(s);
      setState(() {
        _settings = s;
        _engine = AiEngine(s);
      });
    });
  }

  void _applyFx(AiSettings s) {
    gRainbow = s.rainbow;
    gGlass = s.glass;
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _spin.dispose();
    _bg.dispose();
    _menu.dispose();
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ---------- scrolling ----------

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        }
      });

  void _follow() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients && _scroll.position.maxScrollExtent - _scroll.offset < 220) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });

  void _speed(bool fast) {
    _spin.duration = Duration(seconds: fast ? 2 : 6);
    _spin.repeat();
  }

  void _snack(String t) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(t), backgroundColor: kSurface, behavior: SnackBarBehavior.floating));

  // ---------- attachments ----------

  void _toggleMenu() {
    setState(() => _menuOpen = !_menuOpen);
    _menuOpen ? _menu.forward() : _menu.reverse();
    HapticFeedback.selectionClick();
  }

  void _closeMenu() {
    if (!_menuOpen) return;
    setState(() => _menuOpen = false);
    _menu.reverse();
  }

  void _stage(String name, Uint8List bytes) {
    final mime = sniffMime(bytes, name);
    if (mime == 'application/octet-stream') {
      _snack('NeonMind can read photos, PDFs and text or code files.');
    } else if (bytes.length > 12 * 1024 * 1024) {
      _snack('$name is too big (12 MB max).');
    } else if (_staged.length >= 6) {
      _snack('You can attach up to 6 items at once.');
    } else {
      setState(() => _staged.add(Attachment(name, bytes, mime)));
    }
  }

  Future<void> _pickPhoto(ImageSource src) async {
    _closeMenu();
    try {
      final files = <XFile>[];
      if (src == ImageSource.camera) {
        final x = await _picker.pickImage(source: src, maxWidth: 1600, imageQuality: 85);
        if (x != null) files.add(x);
      } else {
        files.addAll(await _picker.pickMultiImage(maxWidth: 1600, imageQuality: 85));
      }
      for (final f in files) {
        _stage(f.name, await f.readAsBytes());
      }
    } catch (_) {
      _snack('Could not open the photo picker.');
    }
  }

  Future<void> _pickFile() async {
    _closeMenu();
    try {
      final r = await FilePicker.platform.pickFiles(withData: true, allowMultiple: true);
      if (r == null) return;
      for (final f in r.files) {
        if (f.bytes != null) _stage(f.name, f.bytes!);
      }
    } catch (_) {
      _snack('Could not open the file picker.');
    }
  }

  // ---------- sending ----------

  Future<void> _send([String? preset]) async {
    if (_thinking) return;
    var text = (preset ?? _input.text).trim();
    if (text.isEmpty && _staged.isEmpty) return;
    if (text.isEmpty) text = 'Please look at the attached file(s).';
    HapticFeedback.lightImpact();
    _closeMenu();
    final atts = List<Attachment>.of(_staged);
    _input.clear();
    _staged.clear();
    setState(() {
      _msgs.add(Msg(true, text, atts: atts));
      _thinking = true;
      _steps.clear();
      _start = DateTime.now();
    });
    _settings.bump('sent');
    if (atts.isNotEmpty) _settings.bump('attachments', atts.length);
    _speed(true);
    _toBottom();

    final res = await _engine.reply(List<Msg>.of(_msgs), (s) {
      if (!mounted) return;
      setState(() => _steps.add(s));
      _toBottom();
    });
    if (!mounted) return;
    final meta = res.error
        ? null
        : '${_settings.provider.name} · ${_settings.online ? _settings.model : 'offline'} · ${res.seconds.toStringAsFixed(1)}s';
    setState(() {
      _msgs.add(Msg(false, res.text, files: res.files, image: res.image, meta: meta, error: res.error));
      _thinking = false;
    });
    if (res.error) {
      _settings.bump('errors');
    } else {
      _settings.bump('replies');
      _settings.bump('provider_${_settings.online ? _settings.providerId : 'offline'}');
      _settings.bump('ms', (res.seconds * 1000).round());
      if (res.files.isNotEmpty) _settings.bump('aiFiles', res.files.length);
      if (res.image != null) _settings.bump('aiImages');
    }
    _settings.saveStats();
    _speed(false);
    HapticFeedback.selectionClick();
    _toBottom();
  }

  Future<void> _openSettings() async {
    _closeMenu();
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SettingsPage(
        settings: _settings,
        adminUnlocked: _admin,
        onAdminUnlocked: () => setState(() => _admin = true),
        onClear: () => setState(_msgs.clear),
        getMsgs: () => _msgs,
      ),
    ));
    if (!mounted) return;
    _applyFx(_settings);
    setState(() => _engine = AiEngine(_settings));
  }

  // ---------- build ----------

  @override
  Widget build(BuildContext context) {
    final online = _settings.online;
    return Scaffold(
      body: Stack(children: [
        Positioned.fill(child: Aurora(t: _bg)),
        Column(children: [
          _header(online),
          RainbowLine(t: _spin),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _closeMenu,
              child: _msgs.isEmpty && !_thinking ? _empty(online) : _list(),
            ),
          ),
          SafeArea(top: false, child: _composer()),
        ]),
      ]),
    );
  }

  Widget _header(bool online) => Glass(
        radius: 0,
        blur: 22,
        padding: EdgeInsets.fromLTRB(18, MediaQuery.of(context).padding.top + 10, 6, 12),
        child: Row(children: [
          Orb(t: _spin),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              RainbowText('NeonMind', t: _spin, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
              Text(online ? '${_settings.provider.name} · ${_settings.model}' : 'Offline brain · no key needed',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: kMuted)),
            ]),
          ),
          if (_admin)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Glass(
                radius: 12,
                blur: 0,
                tint: kYellow,
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.shield_rounded, size: 13, color: kYellow),
                  SizedBox(width: 4),
                  Text('ADMIN', style: TextStyle(color: kYellow, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
                ]),
              ),
            ),
          IconButton(onPressed: _openSettings, icon: const Icon(Icons.tune_rounded, color: kCyan)),
        ]),
      );

  Widget _empty(bool online) {
    final ideas = online
        ? ['Explain black holes simply', '/image a neon city in the rain', 'Make me a packing list file']
        : ['What time is it?', 'Calculate (24 * 7) + 3', 'Tell me a joke'];
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Orb(t: _spin, size: 76),
          const SizedBox(height: 22),
          RainbowText("Hi, I'm NeonMind.", t: _spin, style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          const Text('Ask, send photos and files with the yellow +,\nor pick an idea below.',
              textAlign: TextAlign.center, style: TextStyle(color: kMuted, fontSize: 15, height: 1.4)),
          const SizedBox(height: 24),
          Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [for (final t in ideas) _chip(t)]),
          if (!online) ...[
            const SizedBox(height: 26),
            GestureDetector(
              onTap: _openSettings,
              child: const Text('Pick Claude, ChatGPT or Gemini in Settings for full AI answers',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: kCyan, fontSize: 13.5, decoration: TextDecoration.underline, decorationColor: kCyan)),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _chip(String t) => GestureDetector(
        onTap: () => t.startsWith('/image') && !_settings.online ? _snack('Add a ChatGPT or Gemini key first.') : _send(t),
        child: Glass(
          radius: 20,
          blur: 12,
          tint: kCyan,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(t, style: const TextStyle(color: kText, fontSize: 14)),
        ),
      );

  Widget _list() => ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(10, 14, 10, 8),
        itemCount: _msgs.length + (_thinking ? 1 : 0),
        itemBuilder: (_, i) => i == _msgs.length
            ? ActivityCard(steps: _steps, start: _start, t: _spin)
            : Bubble(
                key: ObjectKey(_msgs[i]),
                msg: _msgs[i],
                typewriter: _settings.typewriter,
                onGrow: _follow,
                onSnack: _snack,
              ),
      );

  // ---------- composer ----------

  Widget _composer() {
    final can = !_thinking && (_input.text.trim().isNotEmpty || _staged.isNotEmpty);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _menuPanel(),
        if (_staged.isNotEmpty) _tray(),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          _plus(),
          const SizedBox(width: 8),
          Expanded(child: _bar()),
          const SizedBox(width: 8),
          _sendButton(can),
        ]),
      ]),
    );
  }

  Widget _plus() => GestureDetector(
        onTap: _toggleMenu,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: kYellow.withValues(alpha: _menuOpen ? .28 : .14),
            border: Border.all(color: kYellow, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: kYellow.withValues(alpha: _menuOpen ? .6 : .35),
                blurRadius: _menuOpen ? 24 : 14,
                spreadRadius: _menuOpen ? 2 : 0,
              ),
            ],
          ),
          child: AnimatedRotation(
            turns: _menuOpen ? .125 : 0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutBack,
            child: const Icon(Icons.add_rounded, color: kYellow, size: 30),
          ),
        ),
      );

  Widget _menuPanel() {
    final items = [
      _Act(Icons.photo_library_rounded, 'Photo', kCyan, () => _pickPhoto(ImageSource.gallery)),
      _Act(Icons.photo_camera_rounded, 'Camera', kPink, () => _pickPhoto(ImageSource.camera)),
      _Act(Icons.insert_drive_file_rounded, 'File', kYellow, _pickFile),
      _Act(Icons.auto_awesome_rounded, 'Image', kRainbow[2], () {
        _closeMenu();
        _input.value = const TextEditingValue(text: '/image ', selection: TextSelection.collapsed(offset: 7));
        _focus.requestFocus();
      }),
    ];
    return AnimatedBuilder(
      animation: _menu,
      builder: (_, __) {
        if (_menu.value == 0) return const SizedBox.shrink();
        return Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (var i = 0; i < items.length; i++) _menuItem(items[i], i),
            ]),
          ),
        );
      },
    );
  }

  Widget _menuItem(_Act a, int i) {
    final v = Curves.easeOutBack.transform(Interval(i * .12, .6 + i * .1).transform(_menu.value));
    return Opacity(
      opacity: v.clamp(0.0, 1.0).toDouble(),
      child: Transform.scale(
        scale: v,
        alignment: Alignment.bottomLeft,
        child: GestureDetector(
          onTap: a.run,
          child: Glass(
            radius: 22,
            blur: 14,
            tint: a.color,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(a.icon, size: 18, color: a.color),
              const SizedBox(width: 7),
              Text(a.label, style: const TextStyle(color: kText, fontSize: 14, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _tray() => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: SizedBox(
          height: 68,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _staged.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final a = _staged[i];
              return Stack(clipBehavior: Clip.none, children: [
                Glass(
                  radius: 14,
                  blur: 10,
                  tint: a.isImage ? kCyan : kYellow,
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: a.isImage
                        ? Image.memory(a.bytes, fit: BoxFit.cover, cacheWidth: 200)
                        : Padding(
                            padding: const EdgeInsets.all(6),
                            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Icon(a.isPdf ? Icons.picture_as_pdf_rounded : Icons.description_rounded, color: kYellow, size: 22),
                              Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kText, fontSize: 10)),
                            ]),
                          ),
                  ),
                ),
                Positioned(
                  top: -6,
                  right: -6,
                  child: GestureDetector(
                    onTap: () => setState(() => _staged.removeAt(i)),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(color: kBlack, shape: BoxShape.circle, border: Border.all(color: kPink)),
                      child: const Icon(Icons.close_rounded, size: 14, color: kPink),
                    ),
                  ),
                ),
              ]);
            },
          ),
        ),
      );

  Widget _bar() {
    final active = _focus.hasFocus || _thinking;
    return RainbowBorder(
      t: _spin,
      radius: 26,
      width: active ? 2.4 : 1.4,
      glow: active ? 1 : .35,
      child: Glass(
        radius: 26,
        blur: 16,
        child: Stack(alignment: Alignment.centerLeft, children: [
          TextField(
            controller: _input,
            focusNode: _focus,
            minLines: 1,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(color: kText, fontSize: 16),
            decoration: const InputDecoration(
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            ),
          ),
          if (_input.text.isEmpty)
            IgnorePointer(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 500),
                  transitionBuilder: (c, a) => FadeTransition(
                    opacity: a,
                    child: SlideTransition(position: Tween(begin: const Offset(0, .4), end: Offset.zero).animate(a), child: c),
                  ),
                  child: Text(_hints[_hint], key: ValueKey(_hint), style: const TextStyle(color: kMuted, fontSize: 16)),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _sendButton(bool can) => GestureDetector(
        onTap: () => _send(),
        child: AnimatedOpacity(
          opacity: can || _thinking ? 1 : .45,
          duration: const Duration(milliseconds: 200),
          child: SizedBox(
            width: 50,
            height: 50,
            child: RainbowBorder(
              t: _spin,
              radius: 25,
              width: 2,
              glow: can || _thinking ? 1 : .2,
              child: Glass(
                radius: 25,
                blur: 12,
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: _thinking
                        ? const SizedBox(key: ValueKey('w'), width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: kCyan))
                        : const Icon(Icons.arrow_upward_rounded, key: ValueKey('s'), color: kText),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

// ======================= Live activity =======================

class ActivityCard extends StatefulWidget {
  const ActivityCard({super.key, required this.steps, required this.start, required this.t});
  final List<String> steps;
  final DateTime start;
  final Animation<double> t;

  @override
  State<ActivityCard> createState() => _ActivityCardState();
}

class _ActivityCardState extends State<ActivityCard> {
  Timer? _tm;

  @override
  void initState() {
    super.initState();
    _tm = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tm?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final secs = DateTime.now().difference(widget.start).inMilliseconds / 1000;
    final steps = widget.steps;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .82),
        child: RainbowBorder(
          t: widget.t,
          radius: 18,
          width: 1.4,
          glow: .6,
          child: Glass(
            radius: 18,
            blur: 14,
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                const Expanded(child: Text('NeonMind is working', style: TextStyle(color: kText, fontWeight: FontWeight.w700, fontSize: 14))),
                Text('${secs.toStringAsFixed(1)}s', style: const TextStyle(color: kMuted, fontSize: 12.5)),
              ]),
              const SizedBox(height: 10),
              for (var i = 0; i < steps.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    i < steps.length - 1
                        ? const Icon(Icons.check_circle_rounded, size: 16, color: kCyan)
                        : const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: kPink)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(steps[i], style: TextStyle(color: i == steps.length - 1 ? kText : kMuted, fontSize: 13.5))),
                  ]),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ======================= Message bubble =======================

class Bubble extends StatefulWidget {
  const Bubble({super.key, required this.msg, required this.typewriter, required this.onGrow, required this.onSnack});
  final Msg msg;
  final bool typewriter;
  final VoidCallback onGrow;
  final void Function(String) onSnack;

  @override
  State<Bubble> createState() => _BubbleState();
}

class _BubbleState extends State<Bubble> with SingleTickerProviderStateMixin {
  AnimationController? _c;
  late final bool _animateIn;

  @override
  void initState() {
    super.initState();
    final m = widget.msg;
    _animateIn = !m.entered;
    m.entered = true;
    if (!m.fromUser && !m.revealed && widget.typewriter && !m.error && m.text.length > 1) {
      final ms = (m.text.length * 14).clamp(500, 3000).toInt();
      _c = AnimationController(vsync: this, duration: Duration(milliseconds: ms))
        ..addListener(() {
          setState(() {});
          widget.onGrow();
        })
        ..addStatusListener((s) {
          if (s == AnimationStatus.completed) m.revealed = true;
        })
        ..forward();
    } else {
      m.revealed = true;
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  Future<void> _save(String name, Uint8List bytes) async {
    try {
      final path = await FilePicker.platform.saveFile(dialogTitle: 'Save file', fileName: name, bytes: bytes);
      if (path != null) widget.onSnack('Saved $name');
    } catch (_) {
      widget.onSnack('Could not save the file.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.msg;
    final color = m.error ? const Color(0xFFFF6B5C) : (m.fromUser ? kPink : kCyan);
    final text = _c == null ? m.text : m.text.substring(0, (m.text.length * _c!.value).floor().clamp(0, m.text.length).toInt());
    final done = _c == null || _c!.isCompleted;
    final big = const Radius.circular(18);
    const small = Radius.circular(4);
    final hh = m.time.hour % 12 == 0 ? 12 : m.time.hour % 12;
    final stamp = '$hh:${m.time.minute.toString().padLeft(2, '0')} ${m.time.hour >= 12 ? 'PM' : 'AM'}';

    final bubble = Align(
      alignment: m.fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .84),
        child: Column(crossAxisAlignment: m.fromUser ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.only(
                topLeft: big,
                topRight: big,
                bottomLeft: m.fromUser ? big : small,
                bottomRight: m.fromUser ? small : big,
              ),
              boxShadow: [BoxShadow(color: color.withValues(alpha: .2), blurRadius: 16)],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.only(
                topLeft: big,
                topRight: big,
                bottomLeft: m.fromUser ? big : small,
                bottomRight: m.fromUser ? small : big,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: gGlass
                        ? [color.withValues(alpha: .22), color.withValues(alpha: .07)]
                        : [color.withValues(alpha: .1), color.withValues(alpha: .1)],
                  ),
                  border: Border.all(color: color.withValues(alpha: .6)),
                  borderRadius: BorderRadius.only(
                    topLeft: big,
                    topRight: big,
                    bottomLeft: m.fromUser ? big : small,
                    bottomRight: m.fromUser ? small : big,
                  ),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  if (m.atts.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Wrap(spacing: 6, runSpacing: 6, children: [
                        for (final a in m.atts)
                          a.isImage
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.memory(a.bytes, width: 110, height: 110, fit: BoxFit.cover, cacheWidth: 300),
                                )
                              : Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Icon(a.isPdf ? Icons.picture_as_pdf_rounded : Icons.description_rounded, size: 16, color: kYellow),
                                    const SizedBox(width: 6),
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(maxWidth: 150),
                                      child: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kText, fontSize: 12.5)),
                                    ),
                                  ]),
                                ),
                      ]),
                    ),
                  if (m.image != null && done)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.memory(m.image!, fit: BoxFit.cover)),
                        const SizedBox(height: 8),
                        _pill(Icons.download_rounded, 'Save image', kCyan, () => _save('neonmind-image.png', m.image!)),
                      ]),
                    ),
                  if (text.isNotEmpty) SelectableText(text, style: const TextStyle(color: kText, fontSize: 15.5, height: 1.4)),
                  if (done)
                    for (final f in m.files)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Glass(
                          radius: 14,
                          blur: 0,
                          tint: kYellow,
                          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.description_rounded, color: kYellow, size: 20),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kText, fontWeight: FontWeight.w600, fontSize: 13.5)),
                                Text('${(f.bytes.length / 1024).toStringAsFixed(1)} KB', style: const TextStyle(color: kMuted, fontSize: 11.5)),
                              ]),
                            ),
                            const SizedBox(width: 8),
                            _pill(Icons.download_rounded, 'Save', kYellow, () => _save(f.name, f.bytes)),
                          ]),
                        ),
                      ),
                ]),
              ),
            ),
          ),
          if (done)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(child: Text(m.fromUser ? stamp : (m.meta ?? stamp), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kMuted, fontSize: 11))),
                if (!m.fromUser && !m.error && m.text.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: m.text));
                      widget.onSnack('Copied');
                    },
                    child: const Icon(Icons.copy_rounded, size: 14, color: kMuted),
                  ),
                ],
              ]),
            ),
        ]),
      ),
    );

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: _animateIn ? const Duration(milliseconds: 380) : Duration.zero,
      curve: Curves.easeOutCubic,
      builder: (_, v, child) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 16 * (1 - v)), child: child)),
      child: bubble,
    );
  }

  Widget _pill(IconData icon, String label, Color c, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: c.withValues(alpha: .14),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 15, color: c),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(color: c, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ]),
        ),
      );
}
