import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

const kBlack = Color(0xFF000000);
const kSurface = Color(0xFF0B0B12);
const kCyan = Color(0xFF00F0FF);
const kPink = Color(0xFFFF2BD6);
const kYellow = Color(0xFFFFE600);
const kText = Color(0xFFE8F9FF);
const kMuted = Color(0xFF8B97AD);
const kRainbow = [
  Color(0xFF00F0FF),
  Color(0xFF4D7CFF),
  Color(0xFF9B5CFF),
  Color(0xFFFF2BD6),
  Color(0xFFFF9A3D),
  Color(0xFFFFE600),
  Color(0xFF3DFF9E),
  Color(0xFF00F0FF),
];

/// Effect switches (changed from the Admin panel).
bool gRainbow = true;
bool gGlass = true;

List<Shadow> glow(Color c) => [Shadow(color: c, blurRadius: 14)];

/// Slow drifting colour clouds. The glass panels blur these.
class Aurora extends StatelessWidget {
  const Aurora({super.key, required this.t});
  final Animation<double> t;

  @override
  Widget build(BuildContext context) => gGlass
      ? AnimatedBuilder(
          animation: t,
          builder: (_, __) => CustomPaint(painter: _AuroraPainter(t.value), size: Size.infinite),
        )
      : const SizedBox.shrink();
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size s) {
    for (var i = 0; i < 4; i++) {
      final a = t * 2 * math.pi + i * 1.7;
      final c = Offset(s.width * (.5 + .45 * math.cos(a + i)), s.height * (.5 + .4 * math.sin(a + i * 2)));
      final r = s.shortestSide * (.75 + .1 * math.sin(a));
      final col = kRainbow[(i * 2) % 7];
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(colors: [col.withValues(alpha: .26), col.withValues(alpha: 0)])
              .createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }
  }

  @override
  bool shouldRepaint(_AuroraPainter o) => o.t != t;
}

/// Frosted liquid-glass panel.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = 20,
    this.blur = 18,
    this.tint,
    this.padding = EdgeInsets.zero,
  });
  final Widget child;
  final double radius;
  final double blur;
  final Color? tint;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    final c = tint ?? Colors.white;
    final body = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: r,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gGlass
              ? [c.withValues(alpha: tint == null ? .13 : .20), c.withValues(alpha: tint == null ? .04 : .06)]
              : const [kSurface, kSurface],
        ),
        border: Border.all(color: c.withValues(alpha: tint == null ? .22 : .55)),
      ),
      child: child,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: tint == null ? null : [BoxShadow(color: tint!.withValues(alpha: .22), blurRadius: 16)],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: (gGlass && blur > 0) ? BackdropFilter(filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur), child: body) : body,
      ),
    );
  }
}

/// Animated rainbow outline with a soft glow (the Gemini-style light).
class RainbowBorder extends StatelessWidget {
  const RainbowBorder({super.key, required this.t, required this.child, this.radius = 26, this.width = 2, this.glow = 1});
  final Animation<double> t;
  final Widget child;
  final double radius;
  final double width;
  final double glow;

  @override
  Widget build(BuildContext context) {
    if (!gRainbow) {
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: kCyan.withValues(alpha: .5), width: width),
          boxShadow: [BoxShadow(color: kCyan.withValues(alpha: .25 * glow), blurRadius: 14)],
        ),
        child: child,
      );
    }
    return AnimatedBuilder(
      animation: t,
      builder: (_, c) => CustomPaint(
        painter: _RainbowPainter(t.value, radius, width, glow, false),
        foregroundPainter: _RainbowPainter(t.value, radius, width, glow, true),
        child: c,
      ),
      child: child,
    );
  }
}

class _RainbowPainter extends CustomPainter {
  _RainbowPainter(this.t, this.radius, this.width, this.glow, this.front);
  final double t;
  final double radius;
  final double width;
  final double glow;
  final bool front;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rr = RRect.fromRectAndRadius(rect.deflate(width / 2), Radius.circular(radius));
    final rot = GradientRotation(t * 2 * math.pi);
    if (front) {
      canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..shader = SweepGradient(colors: kRainbow, transform: rot).createShader(rect),
      );
    } else if (glow > 0) {
      final cols = [for (final c in kRainbow) c.withValues(alpha: .55 * glow.clamp(0.0, 1.0))];
      canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width * 3
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 8 + 6 * glow)
          ..shader = SweepGradient(colors: cols, transform: rot).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(_RainbowPainter o) => o.t != t || o.glow != glow || o.width != width;
}

class Orb extends StatelessWidget {
  const Orb({super.key, required this.t, this.size = 38});
  final Animation<double> t;
  final double size;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: t,
        builder: (_, __) => Container(
          width: size,
          height: size,
          padding: EdgeInsets.all(size * .1),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: SweepGradient(colors: kRainbow, transform: GradientRotation(t.value * 2 * math.pi)),
            boxShadow: [
              BoxShadow(color: kPink.withValues(alpha: .35), blurRadius: size * .5),
              BoxShadow(color: kCyan.withValues(alpha: .3), blurRadius: size * .5, offset: Offset(size * .1, 0)),
            ],
          ),
          child: const DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                center: Alignment(-.35, -.4),
                colors: [Color(0xFFFFFFFF), Color(0x33FFFFFF), Color(0xFF05050A)],
                stops: [0, .25, 1],
              ),
            ),
          ),
        ),
      );
}

LinearGradient _flow(double v) => LinearGradient(
      colors: gRainbow ? kRainbow : const [kCyan, kPink, kCyan],
      tileMode: TileMode.repeated,
      begin: Alignment(-1 + 2 * v, 0),
      end: Alignment(1 + 2 * v, 0),
    );

class RainbowText extends StatelessWidget {
  const RainbowText(this.text, {super.key, required this.t, this.style});
  final String text;
  final Animation<double> t;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: t,
        builder: (_, __) => ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (r) => _flow(t.value).createShader(r),
          child: Text(text, style: (style ?? const TextStyle()).copyWith(color: Colors.white)),
        ),
      );
}

class RainbowLine extends StatelessWidget {
  const RainbowLine({super.key, required this.t});
  final Animation<double> t;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: t,
        builder: (_, __) => Container(
          height: 2,
          decoration: BoxDecoration(
            gradient: _flow(t.value),
            boxShadow: [BoxShadow(color: kPink.withValues(alpha: .5), blurRadius: 10)],
          ),
        ),
      );
}

class NeonButton extends StatelessWidget {
  const NeonButton({super.key, required this.label, required this.color, required this.onTap, this.icon});
  final String label;
  final Color color;
  final VoidCallback onTap;
  final IconData? icon;

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
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                if (icon != null) ...[Icon(icon, color: color, size: 18), const SizedBox(width: 8)],
                Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 15)),
              ]),
            ),
          ),
        ),
      );
}
