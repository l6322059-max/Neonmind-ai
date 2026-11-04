import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Turns the AI's simple text format into a real .pptx / .docx / .xlsx file.
/// Any other extension is saved as plain text.
Uint8List buildFile(String name, String body) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  if (ext == 'pptx') return _zip(_pptx(body));
  if (ext == 'docx') return _zip(_docx(body));
  if (ext == 'xlsx') return _zip(_xlsx(body));
  return Uint8List.fromList(utf8.encode(body));
}

Uint8List _zip(Map<String, String> parts) {
  final a = Archive();
  parts.forEach((path, xml) {
    final b = utf8.encode(xml);
    a.addFile(ArchiveFile(path, b.length, b));
  });
  return Uint8List.fromList(ZipEncoder().encode(a)!);
}

const _hdr = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';
const _nsA = 'http://schemas.openxmlformats.org/drawingml/2006/main';
const _nsR = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _nsP = 'http://schemas.openxmlformats.org/presentationml/2006/main';
const _nsW = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _nsS = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const _pkg = 'http://schemas.openxmlformats.org/package/2006/relationships';
const _ct = 'http://schemas.openxmlformats.org/package/2006/content-types';
const _oo = 'application/vnd.openxmlformats-officedocument';

String _x(String s) => s
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

bool _rtl(String s) => RegExp(r'[\u0590-\u08FF]').hasMatch(s);

String _rels(List<List<String>> r) =>
    '$_hdr<Relationships xmlns="$_pkg">${[for (final e in r) '<Relationship Id="${e[0]}" Type="$_nsR/${e[1]}" Target="${e[2]}"/>'].join()}</Relationships>';

// ======================= PowerPoint (neon theme) =======================

class _Slide {
  String title = '';
  String sub = '';
  final List<String> bullets = [];
}

List<_Slide> _parseSlides(String body) {
  final out = <_Slide>[];
  var cur = _Slide();
  void flush() {
    if (cur.title.isNotEmpty || cur.sub.isNotEmpty || cur.bullets.isNotEmpty) out.add(cur);
    cur = _Slide();
  }

  for (final raw in body.split('\n')) {
    final t = raw.trim();
    if (RegExp(r'^-{3,}$').hasMatch(t)) {
      flush();
    } else if (t.startsWith('## ')) {
      cur.sub = t.substring(3).trim();
    } else if (t.startsWith('# ')) {
      if (cur.title.isNotEmpty) flush();
      cur.title = t.substring(2).trim();
    } else if (RegExp(r'^[-*•]\s+').hasMatch(t)) {
      cur.bullets.add(t.replaceFirst(RegExp(r'^[-*•]\s+'), ''));
    } else if (t.isNotEmpty) {
      cur.bullets.add(t);
    }
  }
  flush();
  if (out.isEmpty) out.add(_Slide()..title = 'Untitled');
  return out;
}

String _para(String text, {required int sz, required String color, bool b = false, bool glow = false, bool bullet = false, bool center = false}) {
  final rtl = _rtl(text);
  final algn = center ? 'ctr' : (rtl ? 'r' : 'l');
  final r = rtl ? ' rtl="1"' : '';
  final ppr = bullet
      ? '<a:pPr marL="342900" indent="-342900" algn="$algn"$r><a:spcBef><a:spcPts val="900"/></a:spcBef><a:buClr><a:srgbClr val="FF2BD6"/></a:buClr><a:buFont typeface="Arial"/><a:buChar char="•"/></a:pPr>'
      : '<a:pPr algn="$algn"$r><a:buNone/></a:pPr>';
  final eff = glow ? '<a:effectLst><a:glow rad="127000"><a:srgbClr val="00F0FF"><a:alpha val="55000"/></a:srgbClr></a:glow></a:effectLst>' : '';
  return '<a:p>$ppr<a:r><a:rPr lang="en-US" sz="$sz" b="${b ? 1 : 0}" dirty="0"><a:solidFill><a:srgbClr val="$color"/></a:solidFill>$eff<a:latin typeface="Calibri"/><a:cs typeface="Arial"/></a:rPr><a:t>${_x(text)}</a:t></a:r></a:p>';
}

String _box(int id, int x, int y, int w, int h, String paras, {String anchor = 't'}) =>
    '<p:sp><p:nvSpPr><p:cNvPr id="$id" name="Text $id"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="$x" y="$y"/><a:ext cx="$w" cy="$h"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/></p:spPr><p:txBody><a:bodyPr wrap="square" lIns="91440" tIns="45720" rIns="91440" bIns="45720" anchor="$anchor"><a:normAutofit/></a:bodyPr><a:lstStyle/>$paras</p:txBody></p:sp>';

String _slideXml(_Slide s) {
  const cols = ['00F0FF', '4D7CFF', '9B5CFF', 'FF2BD6', 'FF9A3D', 'FFE600', '3DFF9E', '00F0FF'];
  final b = StringBuffer();
  for (var i = 0; i < 8; i++) {
    b.write('<p:sp><p:nvSpPr><p:cNvPr id="${i + 2}" name="Bar ${i + 1}"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="${i * 1524000}" y="0"/><a:ext cx="1524000" cy="91440"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:solidFill><a:srgbClr val="${cols[i]}"/></a:solidFill><a:ln><a:noFill/></a:ln></p:spPr></p:sp>');
  }
  if (s.bullets.isEmpty) {
    b.write(_box(20, 914400, 2057400, 10363200, 1600200, _para(s.title, sz: 5000, color: 'FFFFFF', b: true, glow: true, center: true), anchor: 'b'));
    if (s.sub.isNotEmpty) {
      b.write(_box(21, 914400, 3810000, 10363200, 1000000, _para(s.sub, sz: 2600, color: '00F0FF', center: true)));
    }
  } else {
    b.write(_box(20, 609600, 381000, 10972800, 1143000, _para(s.title, sz: 4000, color: '00F0FF', b: true, glow: true), anchor: 'ctr'));
    final n = s.bullets.length;
    final sz = n > 8 ? 1600 : (n > 6 ? 1800 : (n > 4 ? 2200 : 2600));
    final body = StringBuffer();
    if (s.sub.isNotEmpty) body.write(_para(s.sub, sz: sz + 200, color: 'FF2BD6', b: true));
    for (final t in s.bullets) {
      body.write(_para(t, sz: sz, color: 'FFFFFF', bullet: true));
    }
    b.write(_box(21, 609600, 1676400, 10972800, 4724400, body.toString()));
  }
  return '$_hdr<p:sld xmlns:a="$_nsA" xmlns:r="$_nsR" xmlns:p="$_nsP"><p:cSld><p:bg><p:bgPr><a:solidFill><a:srgbClr val="000000"/></a:solidFill><a:effectLst/></p:bgPr></p:bg><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>$b</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>';
}

const _emptyTree =
    '<p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr></p:spTree>';

const _fillLst = '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>';
const _theme =
    '$_hdr<a:theme xmlns:a="$_nsA" name="Neon"><a:themeElements><a:clrScheme name="Neon"><a:dk1><a:srgbClr val="000000"/></a:dk1><a:lt1><a:srgbClr val="FFFFFF"/></a:lt1><a:dk2><a:srgbClr val="0B0B12"/></a:dk2><a:lt2><a:srgbClr val="E8F9FF"/></a:lt2><a:accent1><a:srgbClr val="00F0FF"/></a:accent1><a:accent2><a:srgbClr val="4D7CFF"/></a:accent2><a:accent3><a:srgbClr val="9B5CFF"/></a:accent3><a:accent4><a:srgbClr val="FF2BD6"/></a:accent4><a:accent5><a:srgbClr val="FF9A3D"/></a:accent5><a:accent6><a:srgbClr val="FFE600"/></a:accent6><a:hlink><a:srgbClr val="00F0FF"/></a:hlink><a:folHlink><a:srgbClr val="9B5CFF"/></a:folHlink></a:clrScheme>'
    '<a:fontScheme name="Neon"><a:majorFont><a:latin typeface="Calibri"/><a:ea typeface=""/><a:cs typeface=""/></a:majorFont><a:minorFont><a:latin typeface="Calibri"/><a:ea typeface=""/><a:cs typeface=""/></a:minorFont></a:fontScheme>'
    '<a:fmtScheme name="Neon"><a:fillStyleLst>$_fillLst$_fillLst$_fillLst</a:fillStyleLst>'
    '<a:lnStyleLst><a:ln w="9525"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln><a:ln w="19050"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln><a:ln w="28575"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln></a:lnStyleLst>'
    '<a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst>'
    '<a:bgFillStyleLst>$_fillLst$_fillLst$_fillLst</a:bgFillStyleLst></a:fmtScheme></a:themeElements></a:theme>';

Map<String, String> _pptx(String body) {
  final slides = _parseSlides(body);
  final n = slides.length;
  final p = <String, String>{};
  p['[Content_Types].xml'] =
      '$_hdr<Types xmlns="$_ct"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/ppt/presentation.xml" ContentType="$_oo.presentationml.presentation.main+xml"/>'
      '<Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="$_oo.presentationml.slideMaster+xml"/>'
      '<Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="$_oo.presentationml.slideLayout+xml"/>'
      '<Override PartName="/ppt/theme/theme1.xml" ContentType="$_oo.theme+xml"/>'
      '${[for (var i = 1; i <= n; i++) '<Override PartName="/ppt/slides/slide$i.xml" ContentType="$_oo.presentationml.slide+xml"/>'].join()}</Types>';
  p['_rels/.rels'] = _rels([
    ['rId1', 'officeDocument', 'ppt/presentation.xml']
  ]);
  p['ppt/presentation.xml'] =
      '$_hdr<p:presentation xmlns:a="$_nsA" xmlns:r="$_nsR" xmlns:p="$_nsP"><p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>'
      '<p:sldIdLst>${[for (var i = 0; i < n; i++) '<p:sldId id="${256 + i}" r:id="rId${i + 2}"/>'].join()}</p:sldIdLst>'
      '<p:sldSz cx="12192000" cy="6858000"/><p:notesSz cx="6858000" cy="9144000"/></p:presentation>';
  p['ppt/_rels/presentation.xml.rels'] = _rels([
    ['rId1', 'slideMaster', 'slideMasters/slideMaster1.xml'],
    for (var i = 0; i < n; i++) ['rId${i + 2}', 'slide', 'slides/slide${i + 1}.xml'],
    ['rId${n + 2}', 'theme', 'theme/theme1.xml'],
  ]);
  p['ppt/slideMasters/slideMaster1.xml'] =
      '$_hdr<p:sldMaster xmlns:a="$_nsA" xmlns:r="$_nsR" xmlns:p="$_nsP"><p:cSld><p:bg><p:bgPr><a:solidFill><a:srgbClr val="000000"/></a:solidFill><a:effectLst/></p:bgPr></p:bg>$_emptyTree</p:cSld>'
      '<p:clrMap bg1="dk1" tx1="lt1" bg2="dk2" tx2="lt2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>'
      '<p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst></p:sldMaster>';
  p['ppt/slideMasters/_rels/slideMaster1.xml.rels'] = _rels([
    ['rId1', 'slideLayout', '../slideLayouts/slideLayout1.xml'],
    ['rId2', 'theme', '../theme/theme1.xml'],
  ]);
  p['ppt/slideLayouts/slideLayout1.xml'] =
      '$_hdr<p:sldLayout xmlns:a="$_nsA" xmlns:r="$_nsR" xmlns:p="$_nsP" type="blank" preserve="1"><p:cSld name="Blank">$_emptyTree</p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>';
  p['ppt/slideLayouts/_rels/slideLayout1.xml.rels'] = _rels([
    ['rId1', 'slideMaster', '../slideMasters/slideMaster1.xml']
  ]);
  p['ppt/theme/theme1.xml'] = _theme;
  for (var i = 0; i < n; i++) {
    p['ppt/slides/slide${i + 1}.xml'] = _slideXml(slides[i]);
    p['ppt/slides/_rels/slide${i + 1}.xml.rels'] = _rels([
      ['rId1', 'slideLayout', '../slideLayouts/slideLayout1.xml']
    ]);
  }
  return p;
}

// ======================= Word =======================

String _runs(String text, {bool boldAll = false}) {
  final rtl = _rtl(text);
  final parts = text.split('**');
  final b = StringBuffer();
  for (var i = 0; i < parts.length; i++) {
    if (parts[i].isEmpty) continue;
    final bold = boldAll || i.isOdd;
    b.write('<w:r><w:rPr>${bold ? '<w:b/>' : ''}${rtl ? '<w:rtl/>' : ''}</w:rPr><w:t xml:space="preserve">${_x(parts[i])}</w:t></w:r>');
  }
  return b.toString();
}

String _wp(String text, {String? style, bool bullet = false, bool boldAll = false}) {
  final rtl = _rtl(text);
  final ppr = '<w:pPr>${style != null ? '<w:pStyle w:val="$style"/>' : ''}${rtl ? '<w:bidi/>' : ''}${bullet ? '<w:ind w:left="540" w:hanging="270"/>' : ''}</w:pPr>';
  return '<w:p>$ppr${_runs(bullet ? '•  $text' : text, boldAll: boldAll)}</w:p>';
}

String _wTable(List<String> rows) {
  final data = <List<String>>[];
  for (final r in rows) {
    final cells = r.trim().replaceAll(RegExp(r'^\||\|$'), '').split('|').map((c) => c.trim()).toList();
    if (cells.every((c) => RegExp(r'^:?-{2,}:?$').hasMatch(c))) continue;
    data.add(cells);
  }
  if (data.isEmpty) return '';
  final cols = data.map((r) => r.length).reduce(math.max);
  final w = 9000 ~/ cols;
  const bd = '<w:{0} w:val="single" w:sz="4" w:space="0" w:color="999999"/>';
  final borders = ['top', 'left', 'bottom', 'right', 'insideH', 'insideV'].map((e) => bd.replaceAll('{0}', e)).join();
  final b = StringBuffer('<w:tbl><w:tblPr><w:tblW w:w="9000" w:type="dxa"/><w:tblBorders>$borders</w:tblBorders></w:tblPr><w:tblGrid>${'<w:gridCol w:w="$w"/>' * cols}</w:tblGrid>');
  for (var r = 0; r < data.length; r++) {
    b.write('<w:tr>');
    for (var c = 0; c < cols; c++) {
      final t = c < data[r].length ? data[r][c] : '';
      b.write('<w:tc><w:tcPr><w:tcW w:w="$w" w:type="dxa"/>${r == 0 ? '<w:shd w:val="clear" w:color="auto" w:fill="DDF8FF"/>' : ''}</w:tcPr>${_wp(t, boldAll: r == 0)}</w:tc>');
    }
    b.write('</w:tr>');
  }
  b.write('</w:tbl><w:p/>');
  return b.toString();
}

Map<String, String> _docx(String body) {
  final b = StringBuffer();
  final lines = body.split('\n');
  var i = 0;
  while (i < lines.length) {
    final t = lines[i].trim();
    if (t.isEmpty) {
      i++;
    } else if (t.startsWith('|')) {
      final rows = <String>[];
      while (i < lines.length && lines[i].trim().startsWith('|')) {
        rows.add(lines[i]);
        i++;
      }
      b.write(_wTable(rows));
    } else {
      if (t.startsWith('## ')) {
        b.write(_wp(t.substring(3), style: 'Heading2'));
      } else if (t.startsWith('# ')) {
        b.write(_wp(t.substring(2), style: 'Heading1'));
      } else if (RegExp(r'^[-*•]\s+').hasMatch(t)) {
        b.write(_wp(t.replaceFirst(RegExp(r'^[-*•]\s+'), ''), bullet: true));
      } else {
        b.write(_wp(t));
      }
      i++;
    }
  }
  const style =
      '<w:style w:type="paragraph" w:styleId="{0}"><w:name w:val="{1}"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:keepNext/><w:spacing w:before="{2}" w:after="120"/><w:outlineLvl w:val="{3}"/></w:pPr><w:rPr><w:b/><w:color w:val="{4}"/><w:sz w:val="{5}"/><w:szCs w:val="{5}"/></w:rPr></w:style>';
  String st(List<String> v) {
    var s = style;
    for (var k = 0; k < v.length; k++) {
      s = s.replaceAll('{$k}', v[k]);
    }
    return s;
  }

  return {
    '[Content_Types].xml':
        '$_hdr<Types xmlns="$_ct"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="$_oo.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="$_oo.wordprocessingml.styles+xml"/></Types>',
    '_rels/.rels': _rels([
      ['rId1', 'officeDocument', 'word/document.xml']
    ]),
    'word/_rels/document.xml.rels': _rels([
      ['rId1', 'styles', 'styles.xml']
    ]),
    'word/styles.xml':
        '$_hdr<w:styles xmlns:w="$_nsW"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="Calibri" w:cs="Arial"/><w:sz w:val="22"/><w:szCs w:val="22"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="120" w:line="276" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>'
        '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>'
        '${st(['Heading1', 'heading 1', '360', '0', '007C8A', '40'])}${st(['Heading2', 'heading 2', '240', '1', 'A0148C', '30'])}</w:styles>',
    'word/document.xml':
        '$_hdr<w:document xmlns:w="$_nsW"><w:body>$b<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr></w:body></w:document>',
  };
}

// ======================= Excel =======================

List<String> _csv(String line) {
  final out = <String>[];
  final cur = StringBuffer();
  var q = false;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (q) {
      if (c == '"') {
        if (i + 1 < line.length && line[i + 1] == '"') {
          cur.write('"');
          i++;
        } else {
          q = false;
        }
      } else {
        cur.write(c);
      }
    } else if (c == '"') {
      q = true;
    } else if (c == ',') {
      out.add(cur.toString());
      cur.clear();
    } else {
      cur.write(c);
    }
  }
  out.add(cur.toString());
  return out;
}

String _col(int c) {
  var n = c;
  var s = '';
  do {
    s = String.fromCharCode(65 + n % 26) + s;
    n = n ~/ 26 - 1;
  } while (n >= 0);
  return s;
}

String _sheetXml(List<List<String>> rows) {
  final maxCols = rows.map((r) => r.length).reduce(math.max);
  final b = StringBuffer(
      '$_hdr<worksheet xmlns="$_nsS"><sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><cols><col min="1" max="$maxCols" width="20" customWidth="1"/></cols><sheetData>');
  for (var r = 0; r < rows.length; r++) {
    b.write('<row r="${r + 1}">');
    for (var c = 0; c < rows[r].length; c++) {
      final v = rows[r][c].trim();
      if (v.isEmpty) continue;
      final ref = '${_col(c)}${r + 1}';
      final s = r == 0 ? ' s="1"' : '';
      if (v.startsWith('=') && v.length > 1) {
        b.write('<c r="$ref"$s><f>${_x(v.substring(1))}</f></c>');
      } else if (r > 0 && RegExp(r'^-?\d+(\.\d+)?$').hasMatch(v)) {
        b.write('<c r="$ref"$s><v>$v</v></c>');
      } else {
        b.write('<c r="$ref"$s t="inlineStr"><is><t xml:space="preserve">${_x(rows[r][c])}</t></is></c>');
      }
    }
    b.write('</row>');
  }
  b.write('</sheetData></worksheet>');
  return b.toString();
}

Map<String, String> _xlsx(String body) {
  final names = <String>[];
  final sheets = <List<List<String>>>[];
  var name = 'Sheet1';
  var rows = <List<String>>[];
  void flush() {
    if (rows.isNotEmpty) {
      var n = name.replaceAll(RegExp(r'[\[\]:*?/\\]'), '').trim();
      if (n.isEmpty) n = 'Sheet${sheets.length + 1}';
      if (n.length > 31) n = n.substring(0, 31);
      while (names.contains(n)) {
        n = '${n.length > 28 ? n.substring(0, 28) : n}-${names.length + 1}';
      }
      names.add(n);
      sheets.add(rows);
    }
    rows = [];
  }

  for (final line in body.split('\n')) {
    if (line.startsWith('# ')) {
      flush();
      name = line.substring(2).trim();
    } else if (line.trim().isNotEmpty) {
      rows.add(_csv(line));
    }
  }
  flush();
  if (sheets.isEmpty) {
    names.add('Sheet1');
    sheets.add([
      ['']
    ]);
  }
  final k = sheets.length;
  return {
    '[Content_Types].xml':
        '$_hdr<Types xmlns="$_ct"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="$_oo.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="$_oo.spreadsheetml.styles+xml"/>${[for (var i = 1; i <= k; i++) '<Override PartName="/xl/worksheets/sheet$i.xml" ContentType="$_oo.spreadsheetml.worksheet+xml"/>'].join()}</Types>',
    '_rels/.rels': _rels([
      ['rId1', 'officeDocument', 'xl/workbook.xml']
    ]),
    'xl/workbook.xml':
        '$_hdr<workbook xmlns="$_nsS" xmlns:r="$_nsR"><sheets>${[for (var i = 0; i < k; i++) '<sheet name="${_x(names[i])}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'].join()}</sheets><calcPr calcId="191029" fullCalcOnLoad="1"/></workbook>',
    'xl/_rels/workbook.xml.rels': _rels([
      for (var i = 0; i < k; i++) ['rId${i + 1}', 'worksheet', 'worksheets/sheet${i + 1}.xml'],
      ['rId${k + 1}', 'styles', 'styles.xml'],
    ]),
    'xl/styles.xml':
        '$_hdr<styleSheet xmlns="$_nsS"><fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font></fonts><fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF0B0B12"/><bgColor indexed="64"/></patternFill></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>',
    for (var i = 0; i < k; i++) 'xl/worksheets/sheet${i + 1}.xml': _sheetXml(sheets[i]),
  };
}
