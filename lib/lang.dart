import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Lang {
  const Lang(this.code, this.name, this.native, this.rtl);
  final String code;
  final String name;
  final String native;
  final bool rtl;
}

const _raw = 'en|English|English;es|Spanish|Español;fr|French|Français;de|German|Deutsch;it|Italian|Italiano;'
    'pt|Portuguese|Português;ru|Russian|Русский;uk|Ukrainian|Українська;pl|Polish|Polski;nl|Dutch|Nederlands;'
    'sv|Swedish|Svenska;no|Norwegian|Norsk;da|Danish|Dansk;fi|Finnish|Suomi;cs|Czech|Čeština;sk|Slovak|Slovenčina;'
    'hu|Hungarian|Magyar;ro|Romanian|Română;bg|Bulgarian|Български;el|Greek|Ελληνικά;tr|Turkish|Türkçe;'
    'ar|Arabic|العربية;he|Hebrew|עברית;fa|Persian|فارسی;ur|Urdu|اردو;hi|Hindi|हिन्दी;bn|Bengali|বাংলা;'
    'ta|Tamil|தமிழ்;te|Telugu|తెలుగు;mr|Marathi|मराठी;gu|Gujarati|ગુજરાતી;kn|Kannada|ಕನ್ನಡ;ml|Malayalam|മലയാളം;'
    'pa|Punjabi|ਪੰਜਾਬੀ;ne|Nepali|नेपाली;si|Sinhala|සිංහල;th|Thai|ไทย;vi|Vietnamese|Tiếng Việt;'
    'id|Indonesian|Bahasa Indonesia;ms|Malay|Bahasa Melayu;fil|Filipino|Filipino;zh-CN|Chinese (Simplified)|简体中文;'
    'zh-TW|Chinese (Traditional)|繁體中文;ja|Japanese|日本語;ko|Korean|한국어;my|Burmese|မြန်မာ;km|Khmer|ខ្មែរ;'
    'lo|Lao|ລາວ;mn|Mongolian|Монгол;kk|Kazakh|Қазақша;uz|Uzbek|Oʻzbekcha;az|Azerbaijani|Azərbaycanca;'
    'ka|Georgian|ქართული;hy|Armenian|Հայերեն;sw|Swahili|Kiswahili;am|Amharic|አማርኛ;zu|Zulu|isiZulu;'
    'xh|Xhosa|isiXhosa;af|Afrikaans|Afrikaans;so|Somali|Soomaali;ha|Hausa|Hausa;yo|Yoruba|Yorùbá;ig|Igbo|Igbo;'
    'mg|Malagasy|Malagasy;rw|Kinyarwanda|Ikinyarwanda;hr|Croatian|Hrvatski;sr|Serbian|Српски;'
    'sl|Slovenian|Slovenščina;bs|Bosnian|Bosanski;mk|Macedonian|Македонски;sq|Albanian|Shqip;'
    'lt|Lithuanian|Lietuvių;lv|Latvian|Latviešu;et|Estonian|Eesti;is|Icelandic|Íslenska;ga|Irish|Gaeilge;'
    'cy|Welsh|Cymraeg;mt|Maltese|Malti;eu|Basque|Euskara;ca|Catalan|Català;gl|Galician|Galego;'
    'lb|Luxembourgish|Lëtzebuergesch;be|Belarusian|Беларуская;tg|Tajik|Тоҷикӣ;ky|Kyrgyz|Кыргызча;'
    'tk|Turkmen|Türkmençe;ps|Pashto|پښتو;ku|Kurdish|Kurdî;sd|Sindhi|سنڌي;ceb|Cebuano|Cebuano;'
    'jv|Javanese|Basa Jawa;su|Sundanese|Basa Sunda;haw|Hawaiian|ʻŌlelo Hawaiʻi;mi|Maori|Te Reo Māori;'
    'sm|Samoan|Gagana Samoa;ht|Haitian Creole|Kreyòl ayisyen;la|Latin|Latina;eo|Esperanto|Esperanto;yi|Yiddish|ייִדיש';

const _rtlCodes = {'ar', 'he', 'fa', 'ur', 'ps', 'sd', 'yi'};

final List<Lang> kLanguages = [
  for (final e in _raw.split(';'))
    Lang(e.split('|')[0], e.split('|')[1], e.split('|')[2], _rtlCodes.contains(e.split('|')[0])),
];

/// English text -> translated text for the chosen app language.
Map<String, String> gTr = {};
bool gRtl = false;
final ValueNotifier<int> gLangTick = ValueNotifier(0);

String tr(String s) => gTr[s] ?? s;

Future<Map<String, String>> loadTr(String key) async {
  try {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('tr_$key');
    if (raw == null) return {};
    return (jsonDecode(raw) as Map).map((k, v) => MapEntry(k as String, v as String));
  } catch (_) {
    return {};
  }
}

Future<void> saveTr(String key, Map<String, String> m) async {
  final p = await SharedPreferences.getInstance();
  await p.setString('tr_$key', jsonEncode(m));
}

/// Text that follows the chosen app language (works inside const widgets too).
class T extends StatelessWidget {
  const T(this.text, {super.key, this.style, this.textAlign, this.maxLines, this.overflow});
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: gLangTick,
        builder: (_, __, ___) => Text(tr(text), style: style, textAlign: textAlign, maxLines: maxLines, overflow: overflow),
      );
}

/// Every interface string that gets translated (generated from the source code).
const kUiStrings = <String>[
  'Reading your message',
  'Offline brain is thinking',
  'Writing the reply',
  'Painting an image',
  'I could not paint the image.',
  'Here you go.',
  'Sending to',
  'thinking…',
  'Got the answer',
  'Add an API key in Settings first. Image creation works with ChatGPT or Gemini.',
  'Image creation works with ChatGPT or Gemini. Switch the AI in Settings.',
  'Painting your image with',
  'Here is your image.',
  'Auto (match my message)',
  'Get a key',
  'Add an API key to translate the app itself. The AI will still answer in this language.',
  'The app stays in English',
  'Ask, send photos and files with the yellow +,\nor pick an idea below.',
  'Pick Claude, ChatGPT or Gemini in Settings for full AI answers',
  'NeonMind is working',
  'Checking your key…',
  'Language',
  'Settings',
  'Choose an AI and paste its API key. Each AI keeps its own key and model. With no key, the offline brain answers.',
  'Translating the app…',
  'The AI answers in your language, and the app translates itself when an AI key is set.',
  'NeonMind',
  "Hi, I'm NeonMind.",
  'OK',
  'Save',
  'Check key and credit',
  'Clear chat',
  'Use',
  'Translate the app again',
  'NeonMind can read photos, PDFs and text or code files.',
  'You can attach up to 6 items at once.',
  'Could not open the photo picker.',
  'Could not open the file picker.',
  'Add a ChatGPT or Gemini key first.',
  'Could not save the file.',
  'Copied',
  'PIN',
  'Server URL',
  'Model',
  'Search languages',
  'Any other language',
  'Message NeonMind',
  'Ask me anything…',
  'Send a photo with +',
  'Try /image a neon city',
  'Offline brain · no key needed',
  'Explain black holes simply',
  'Make a PowerPoint about space',
  'Write a Word report about the ocean',
  'What time is it?',
  'Calculate (24 * 7) + 3',
  'Tell me a joke',
  'Photo',
  'Camera',
  'File',
  'Image',
  'Slides',
  'Save image',
  'Admin panel',
  'Admin panel (unlocked)',
  'Looking at photo',
  'Reading file',
];
