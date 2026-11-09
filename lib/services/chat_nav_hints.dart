import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Where the chat can send the user. `target` matches the tab names used by
/// HomeShell._navigateToTab, plus 'diary' which opens HealthDiaryScreen as a
/// pushed page (it is not a tab).
class ChatNavHint {
  final String target;
  final String labelEn;
  final String labelUr;
  final String reasonEn;
  final String reasonUr;
  final IconData icon;
  final Color color;

  const ChatNavHint({
    required this.target,
    required this.labelEn,
    required this.labelUr,
    required this.reasonEn,
    required this.reasonUr,
    required this.icon,
    required this.color,
  });

  String label(String language) => language == 'ur' ? labelUr : labelEn;
  String reason(String language) => language == 'ur' ? reasonUr : reasonEn;
}

const _pcos = ChatNavHint(
  target: 'pcos',
  labelEn: 'PCOS Screening',
  labelUr: 'پی سی او ایس اسکریننگ',
  reasonEn: 'You can run a quick PCOS screening and see your result.',
  reasonUr: 'آپ تیزی سے پی سی او ایس اسکریننگ کر کے نتیجہ دیکھ سکتی ہیں۔',
  icon: Icons.bubble_chart_outlined,
  color: AppColors.periodRed,
);

const _endo = ChatNavHint(
  target: 'endo',
  labelEn: 'Endometriosis',
  labelUr: 'اینڈومیٹریوسس',
  reasonEn: 'Learn about endometriosis signs and check your symptoms.',
  reasonUr: 'اینڈومیٹریوسس کی علامات کے بارے میں جانیں اور اپنی علامات دیکھیں۔',
  icon: Icons.local_florist_outlined,
  color: AppColors.accent,
);

const _diary = ChatNavHint(
  target: 'diary',
  labelEn: 'Health Diary',
  labelUr: 'ہیلتھ ڈائری',
  reasonEn: 'Log your mood and symptoms so you can spot patterns over time.',
  reasonUr: 'اپنا موڈ اور علامات درج کریں تاکہ وقت کے ساتھ پیٹرن نظر آئیں۔',
  icon: Icons.edit_note_rounded,
  color: AppColors.primary,
);

const _protection = ChatNavHint(
  target: 'protection',
  labelEn: 'Contraception & Protection',
  labelUr: 'مانعِ حمل اور تحفظ',
  reasonEn: 'Explore contraception options and check which suit you.',
  reasonUr: 'مانعِ حمل کے طریقے دیکھیں اور جانیں کون سا آپ کے لیے موزوں ہے۔',
  icon: Icons.shield_outlined,
  color: AppColors.ovulationTeal,
);

const _ovulation = ChatNavHint(
  target: 'ovulation',
  labelEn: 'Ovulation',
  labelUr: 'اوولیشن',
  reasonEn: 'See your fertile window and ovulation estimate.',
  reasonUr: 'اپنی زرخیزی کی مدت اور اوولیشن کا اندازہ دیکھیں۔',
  icon: Icons.egg_outlined,
  color: AppColors.moodYellow,
);

const _cycle = ChatNavHint(
  target: 'cycle',
  labelEn: 'Cycle Tracker',
  labelUr: 'ماہواری ٹریکر',
  reasonEn: 'Open your calendar to log or review your cycle.',
  reasonUr: 'اپنی ماہواری درج کرنے یا دیکھنے کے لیے کیلنڈر کھولیں۔',
  icon: Icons.nightlight_round,
  color: AppColors.primary,
);

const _learn = ChatNavHint(
  target: 'learn',
  labelEn: 'Learn',
  labelUr: 'سیکھیں',
  reasonEn: 'Read simple guides about your body and cycle.',
  reasonUr: 'اپنے جسم اور ماہواری کے بارے میں آسان گائیڈز پڑھیں۔',
  icon: Icons.menu_book_outlined,
  color: AppColors.symptomOrange,
);

/// Hint for a tab name the server may suggest (`suggested_tab`).
ChatNavHint? chatNavHintForTab(String? tab) {
  switch (tab) {
    case 'pcos':
      return _pcos;
    case 'endo':
      return _endo;
    case 'diary':
      return _diary;
    case 'protection':
      return _protection;
    case 'ovulation':
      return _ovulation;
    case 'cycle':
      return _cycle;
    case 'learn':
      return _learn;
  }
  return null;
}

// Order matters: the first rule that matches wins, so specific topics come
// before broad ones (e.g. "diary" before "cycle").
final List<(RegExp, ChatNavHint)> _rules = [
  (RegExp(r'\b(diary|journal|log my|write (it )?down)\b|ڈائری'), _diary),
  (
    RegExp(
      r'\b(pcos|pcod|polycystic|hirsut\w*|facial hair|excess hair)\b|پی سی او|پولی سسٹک',
    ),
    _pcos,
  ),
  (
    RegExp(
      r'\bendo\w*|painful periods?|severe (period )?(pain|cramps?)|pelvic pain|اینڈو',
    ),
    _endo,
  ),
  (
    RegExp(
      r'\b(contracepti\w*|birth control|condoms?|iud|implant|the pill|emergency pill)\b|مانع حمل|مانعِ حمل',
    ),
    _protection,
  ),
  (
    RegExp(
      r'\b(ovulat\w*|fertile|fertility|conceive|conception|trying to (get )?pregnant)\b|اوولیشن|بیضہ',
    ),
    _ovulation,
  ),
  (
    RegExp(
      r'\b(irregular (period|cycle)s?|(periods?|cycles?) (are|is|have been|been) irregular|skipped periods?)\b',
    ),
    _pcos,
  ),
  (
    RegExp(
      r'\b(late period|missed period|next period|cycle day|period tracker|my calendar)\b',
    ),
    _cycle,
  ),
  (RegExp(r'\b(articles?|guides?|learn (more )?about)\b|سیکھ'), _learn),
];

/// Looks at what the user typed first, then at the assistant's reply, and
/// returns the first matching navigation hint (or null if nothing relevant).
ChatNavHint? detectChatNavHint({required String userText, String? replyText}) {
  for (final source in [userText, replyText ?? '']) {
    final text = source.toLowerCase();
    if (text.trim().isEmpty) continue;
    for (final (pattern, hint) in _rules) {
      if (pattern.hasMatch(text)) return hint;
    }
  }
  return null;
}
