import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../services/health_profile_service.dart';

/// ---------------------------------------------------------------
/// Gentle, reassuring UI for the PCOS screen + a "Doctor Visit
/// Notes" tool that turns the user's details, notes and questions
/// into a short script she can read out (or show) at the clinic.
/// ---------------------------------------------------------------

/// Everything the doctor script needs from the PCOS form. The screen
/// builds this fresh each time the script is generated.
class PcosVisitData {
  final int? age;
  final double? weightKg;
  final double? heightCm;
  final String? cycleRegularity;
  final int? cycleLengthDays;
  final List<String> symptoms;
  final bool? fastFood;
  final bool? regularExercise;
  final String? screeningSummary;

  const PcosVisitData({
    this.age,
    this.weightKg,
    this.heightCm,
    this.cycleRegularity,
    this.cycleLengthDays,
    this.symptoms = const [],
    this.fastFood,
    this.regularExercise,
    this.screeningSummary,
  });
}

// =====================================================================
// 1. Comfort banner (top of Detection tab)
// =====================================================================
class PcosComfortBanner extends StatelessWidget {
  const PcosComfortBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withValues(alpha: 0.14),
            AppColors.accent.withValues(alpha: 0.18),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
                child: const Center(
                  child: Text('🌸', style: TextStyle(fontSize: 22)),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'You\'re in a safe, judgement-free space',
                  style: AppTextStyles.serif(size: 17),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Take your time with this. There are no wrong answers, and you '
            'can leave anything you don\'t know blank for now. Many people '
            'with PCOS live healthy, full lives once they understand what '
            'their body needs.',
            style: AppTextStyles.sans(
              size: 13,
              color: AppColors.textSecondary,
            ).copyWith(height: 1.55),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [
              _SoftPill('🤍  Go at your own pace'),
              _SoftPill('✨  Not a diagnosis'),
              _SoftPill('🌿  Skip what you don\'t know'),
            ],
          ),
        ],
      ),
    );
  }
}

class _SoftPill extends StatelessWidget {
  final String text;
  const _SoftPill(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: AppTextStyles.sans(
          size: 11.5,
          weight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

// =====================================================================
// 2. Reassurance shown right after a result
// =====================================================================
class PcosAfterResultCard extends StatelessWidget {
  const PcosAfterResultCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.ovulationTeal.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.ovulationTeal.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '💚  Whatever this number says, take a breath',
            style: AppTextStyles.serif(size: 16),
          ),
          const SizedBox(height: 10),
          Text(
            'This is only a screening estimate. It can\'t tell you for sure, '
            'and it doesn\'t define your health. PCOS is common and very '
            'manageable, and a doctor can look at your full picture and '
            'guide you calmly from here.',
            style: AppTextStyles.sans(
              size: 13,
              color: AppColors.textSecondary,
            ).copyWith(height: 1.55),
          ),
          const SizedBox(height: 10),
          Text(
            'A good next step: use the Doctor Visit Notes below to get your '
            'thoughts, worries and questions ready, so you feel prepared '
            'and heard at your appointment.',
            style: AppTextStyles.sans(
              size: 13,
              weight: FontWeight.w600,
              color: AppColors.textPrimary,
            ).copyWith(height: 1.55),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// 3. Doctor Visit Notes + script generator
// =====================================================================
class DoctorVisitNotesCard extends StatefulWidget {
  /// Called when the script is generated, so it always uses the
  /// latest form values.
  final PcosVisitData Function() readData;

  const DoctorVisitNotesCard({super.key, required this.readData});

  @override
  State<DoctorVisitNotesCard> createState() => _DoctorVisitNotesCardState();
}

class _DoctorVisitNotesCardState extends State<DoctorVisitNotesCard> {
  static const _kNotes = 'pcosDoctorNotes';
  static const _kFemale = 'pcosPrefFemaleDoctor';
  static const _kExternal = 'pcosPrefExternalScan';
  static const _kQuestions = 'pcosDoctorQuestions';

  static const _commonQuestions = [
    'Do my symptoms point to PCOS, or could it be something else?',
    'Which tests do I need, and do I have to fast for them?',
    'What lifestyle changes would help me the most?',
    'Are there medicines I may need, and what are their side effects?',
    'How often should I come back for follow-up?',
  ];

  static const _marriedQuestions = [
    'How does PCOS affect my chances of getting pregnant?',
    'Is it safe to try for a baby while on treatment?',
    'Which contraception is suitable for me with PCOS?',
  ];

  static const _unmarriedQuestions = [
    'Which scan is suitable for me, and can it be done externally?',
    'Will PCOS affect my fertility later, and what can I do now?',
    'Can we keep my reports and details private?',
  ];

  final _notesController = TextEditingController();

  /// 'Unmarried', 'Married', or null (prefer not to say / not chosen).
  String? _marital;
  bool _femaleDoctor = false;
  bool _externalScan = false;
  final Set<String> _selectedQuestions = {};
  String? _script;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final profile = await HealthProfileService().loadProfile();
    if (!mounted) return;

    final saved = profile.demographics.maritalStatus;
    setState(() {
      _notesController.text = prefs.getString(_kNotes) ?? '';
      _femaleDoctor = prefs.getBool(_kFemale) ?? false;
      _externalScan = prefs.getBool(_kExternal) ?? false;
      _selectedQuestions
        ..clear()
        ..addAll(prefs.getStringList(_kQuestions) ?? const []);
      if (saved == 'Married') {
        _marital = 'Married';
      } else if (saved != null && saved.isNotEmpty) {
        _marital = 'Unmarried';
      }
    });
  }

  Future<void> _saveLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kNotes, _notesController.text);
    await prefs.setBool(_kFemale, _femaleDoctor);
    await prefs.setBool(_kExternal, _externalScan);
    await prefs.setStringList(_kQuestions, _selectedQuestions.toList());
  }

  Future<void> _setMarital(String value) async {
    setState(() {
      _marital = _marital == value ? null : value;
      _script = null;
    });
    // Keep the shared health profile in sync. Stored as 'Single' for
    // unmarried so it matches the values the AI check-in already uses.
    if (_marital != null) {
      final stored = _marital == 'Married' ? 'Married' : 'Single';
      await HealthProfileService().updateProfile(
        (p) => p.copyWith(
          demographics: p.demographics.copyWith(maritalStatus: stored),
        ),
      );
    }
  }

  List<String> get _questionOptions => [
    ..._commonQuestions,
    if (_marital == 'Married') ..._marriedQuestions,
    if (_marital == 'Unmarried') ..._unmarriedQuestions,
  ];

  String _buildScript() {
    final d = widget.readData();
    final b = StringBuffer();

    b.writeln('Assalam o Alaikum, Doctor.');
    b.writeln();

    final intro = StringBuffer('I\'m');
    intro.write(d.age != null ? ' ${d.age} years old' : ' here for a check-up');
    if (_marital != null) intro.write(' and ${_marital!.toLowerCase()}');
    intro.write('.');
    b.writeln(intro.toString());

    if (d.weightKg != null || d.heightCm != null) {
      final parts = <String>[
        if (d.weightKg != null) '${d.weightKg!.toStringAsFixed(0)} kg',
        if (d.heightCm != null) '${d.heightCm!.toStringAsFixed(0)} cm tall',
      ];
      b.writeln('I am ${parts.join(' and ')}.');
    }

    if (d.cycleRegularity != null) {
      var line = 'My periods are ${d.cycleRegularity!.toLowerCase()}';
      if (d.cycleLengthDays != null) {
        line += ', usually about ${d.cycleLengthDays} days apart';
      }
      b.writeln('$line.');
    }

    if (d.symptoms.isNotEmpty) {
      b.writeln('Things I\'ve noticed: ${d.symptoms.join(', ')}.');
    } else {
      b.writeln('I haven\'t marked any particular symptoms in the app.');
    }

    final lifestyle = <String>[
      if (d.regularExercise == true) 'I exercise regularly',
      if (d.regularExercise == false) 'I don\'t exercise regularly',
      if (d.fastFood == true) 'I eat fast food often',
    ];
    if (lifestyle.isNotEmpty) b.writeln('${lifestyle.join('; ')}.');

    if (d.screeningSummary != null) {
      b.writeln();
      b.writeln(
        'I tried a PCOS screening in an app, which showed: '
        '${d.screeningSummary}. I understand it is not a diagnosis, and I '
        'would like your professional opinion.',
      );
    }

    final notes = _notesController.text.trim();
    if (notes.isNotEmpty) {
      b.writeln();
      b.writeln('What worries me most:');
      b.writeln(notes);
    }

    final prefs = <String>[
      if (_femaleDoctor) 'I would feel more comfortable with a female doctor',
      if (_externalScan)
        'if a scan is needed, I would prefer an external (abdominal) one first',
    ];
    if (prefs.isNotEmpty) {
      b.writeln();
      b.writeln('My preferences: ${prefs.join('; ')}.');
    }

    final qs = _questionOptions.where(_selectedQuestions.contains).toList();
    if (qs.isNotEmpty) {
      b.writeln();
      b.writeln('Questions I\'d like to ask:');
      for (var i = 0; i < qs.length; i++) {
        b.writeln('${i + 1}. ${qs[i]}');
      }
    }

    b.writeln();
    b.write('Thank you for your time.');
    return b.toString();
  }

  Future<void> _generate() async {
    await _saveLocal();
    setState(() => _script = _buildScript());
  }

  Future<void> _copy() async {
    if (_script == null) return;
    await Clipboard.setData(ClipboardData(text: _script!));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied. You can paste it into a message.')),
    );
  }

  // ------------------------------ UI ------------------------------

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('🩺  Doctor Visit Notes', style: AppTextStyles.serif(size: 18)),
          const SizedBox(height: 8),
          Text(
            'Jot down what you want to say, then turn it into a short script '
            'to read out or show at your appointment. It\'s easy to forget '
            'things when you\'re nervous. This helps.',
            style: AppTextStyles.sans(
              size: 12.5,
              color: AppColors.textSecondary,
            ).copyWith(height: 1.55),
          ),
          const SizedBox(height: 22),

          _label('ABOUT YOU (OPTIONAL)'),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _choice('Unmarried', _marital == 'Unmarried')),
              const SizedBox(width: 10),
              Expanded(child: _choice('Married', _marital == 'Married')),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'This only tailors the questions and your script. Skip it if '
            'you prefer.',
            style: AppTextStyles.sans(size: 11, color: AppColors.textSecondary),
          ),

          const SizedBox(height: 22),
          _label('WHAT WORRIES YOU? (YOUR NOTES)'),
          const SizedBox(height: 10),
          TextField(
            controller: _notesController,
            minLines: 4,
            maxLines: 8,
            onChanged: (_) => _saveLocal(),
            style: AppTextStyles.sans(size: 13.5),
            decoration: _inputDecoration(
              'e.g. My periods have been late for 3 months, and I\'ve been '
              'feeling very tired...',
            ),
          ),

          const SizedBox(height: 22),
          _label('MY PREFERENCES'),
          const SizedBox(height: 6),
          _switchRow('I\'d prefer a female doctor', _femaleDoctor, (v) {
            setState(() => _femaleDoctor = v);
            _saveLocal();
          }),
          _switchRow('I\'d prefer an external (abdominal) scan first', _externalScan, (
            v,
          ) {
            setState(() => _externalScan = v);
            _saveLocal();
          }),

          const SizedBox(height: 18),
          _label('QUESTIONS TO ASK (TAP TO ADD)'),
          const SizedBox(height: 10),
          ..._questionOptions.map(_questionTile),

          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _generate,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: Text(
                'Create my doctor script',
                style: AppTextStyles.sans(
                  size: 14,
                  weight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),

          if (_script != null) ...[
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '📝  Your script',
                    style: AppTextStyles.sans(
                      size: 13,
                      weight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SelectableText(
                    _script!,
                    style: AppTextStyles.sans(size: 13.5).copyWith(height: 1.65),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _copy,
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: const Text('Copy script'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: BorderSide(
                          color: AppColors.primary.withValues(alpha: 0.5),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 14),
          Text(
            'This script helps you communicate. It is not medical advice or '
            'a diagnosis.',
            style: AppTextStyles.sans(
              size: 11,
              color: AppColors.textSecondary,
            ).copyWith(fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Text(
    text,
    style: AppTextStyles.sans(
      size: 11,
      weight: FontWeight.w600,
      color: AppColors.textSecondary,
    ),
  );

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: AppTextStyles.sans(size: 12.5, color: AppColors.textSecondary),
      filled: true,
      fillColor: AppColors.background,
      contentPadding: const EdgeInsets.all(14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppColors.cardBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppColors.cardBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppColors.primary, width: 1.4),
      ),
    );
  }

  Widget _choice(String label, bool selected) {
    return GestureDetector(
      onTap: () => _setMarital(label),
      child: Container(
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.16)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.7)
                : AppColors.cardBorder,
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.sans(
            size: 13,
            weight: FontWeight.w600,
            color: selected ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _switchRow(String text, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      activeThumbColor: AppColors.primary,
      title: Text(text, style: AppTextStyles.sans(size: 13)),
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _questionTile(String q) {
    final selected = _selectedQuestions.contains(q);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () {
          setState(() {
            selected ? _selectedQuestions.remove(q) : _selectedQuestions.add(q);
          });
          _saveLocal();
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accent.withValues(alpha: 0.14)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? AppColors.accent.withValues(alpha: 0.6)
                  : AppColors.cardBorder,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.add_circle_outline_rounded,
                size: 20,
                color: selected ? AppColors.accent : AppColors.textSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  q,
                  style: AppTextStyles.sans(size: 13).copyWith(height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
