import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'language_provider.dart';

/// A fixed "EN | اردو" pill pinned to the top-right of EVERY screen.
///
/// Tapping it flips the whole app between English and Urdu: layouts
/// mirror right-to-left, material widgets localize, and every screen's
/// Text re-translates via the shared translation dictionary. The chat
/// language stays in sync (LanguageProvider writes the same preference
/// the AI screen used to manage itself).
///
/// Fixed position on purpose: the previous version was draggable, and a
/// language switch that can wander around (and can be dropped anywhere,
/// including out of sight) is worse than one that's always where you
/// expect it.
class LanguageFab extends StatelessWidget {
  const LanguageFab({super.key});

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();
    final pad = MediaQuery.paddingOf(context);

    return Positioned(
      top: pad.top + 6,
      right: 12,
      child: Material(
        color: Colors.transparent,
        child: Container(
          height: 30,
          padding: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.97),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFF1D3DF)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF912260).withValues(alpha: 0.18),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _side(context, 'EN', !lang.isUrdu),
              _side(context, 'اردو', lang.isUrdu),
            ],
          ),
        ),
      ),
    );
  }

  Widget _side(BuildContext context, String label, bool active) {
    final target = label == 'EN' ? 'en' : 'ur';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        final lang = context.read<LanguageProvider>();
        if (lang.code != target) lang.setLanguage(target);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF912260) : Colors.transparent,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: active ? Colors.white : const Color(0xFF7D4A65),
              height: 1.0,
              textBaseline: TextBaseline.alphabetic,
              fontFamilyFallback: const ['Noto Naskh Arabic', 'sans-serif'],
            ),
          ),
        ),
      ),
    );
  }
}
