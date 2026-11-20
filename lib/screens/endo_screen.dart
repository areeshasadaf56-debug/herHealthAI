import 'package:flutter/material.dart' hide Text;
import '../l10n/app_text.dart';
import '../theme/app_theme.dart';
import '../utils/app_dates.dart';
import '../models/health_profile.dart';
import '../services/health_profile_service.dart';
import '../widgets/app_animations.dart';
import '../widgets/pcos_card.dart';

class EndoScreen extends StatefulWidget {
  const EndoScreen({super.key});

  @override
  State<EndoScreen> createState() => _EndoScreenState();
}

class _EndoScreenState extends State<EndoScreen> {
  int _activeTab = 0;

  String _formattedDate() => formatShortDateStamp(DateTime.now());

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            const SizedBox(height: 20),
            _buildTabs(),
            const SizedBox(height: 20),
            if (_activeTab == 0)
              AppSwitcher(
                tabKey: _activeTab,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _buildInformationTab(),
                ),
              )
            else
              AppSwitcher(tabKey: _activeTab, child: _buildDetectionTab()),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        // Task 8.1: pushed as a full-screen tool now, so it carries its
        // own back affordance when it can pop.
        if (Navigator.canPop(context)) ...[
          IconButton(
            tooltip: 'Back',
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            color: AppColors.textSecondary,
            icon: const Icon(Icons.arrow_back_ios_new, size: 18),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 2),
        ],
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: 'Wellness ',
                style: AppTextStyles.serif(
                  size: 22,
                  weight: FontWeight.w600,
                  color: AppColors.accent,
                ).copyWith(fontStyle: FontStyle.italic),
              ),
              TextSpan(
                text: 'Saheli',
                style: AppTextStyles.serif(
                  size: 22,
                  weight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        Text(
          _formattedDate(),
          style: AppTextStyles.sans(size: 11, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildTabs() {
    return Row(
      children: [
        Expanded(
          child: _tabButton('ℹ️', 'Information', 0, AppColors.ovulationTeal),
        ),
        const SizedBox(width: 10),
        Expanded(child: _tabButton('🩺', 'Detection', 1, AppColors.primary)),
      ],
    );
  }

  Widget _tabButton(String emoji, String label, int index, Color activeColor) {
    final isActive = _activeTab == index;
    return GestureDetector(
      onTap: () => setState(() => _activeTab = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isActive
              ? activeColor.withValues(alpha: 0.18)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isActive
                ? activeColor.withValues(alpha: 0.6)
                : AppColors.cardBorder,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTextStyles.sans(
                size: 13,
                weight: FontWeight.w600,
                color: isActive
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildInformationTab() {
    return [
      _heroCard(),
      const SizedBox(height: 24),
      _sectionLabel('WHAT IS ENDOMETRIOSIS?'),
      const SizedBox(height: 12),
      PcosCard(
        emoji: '💡',
        badgeColor: AppColors.moodYellow,
        title: 'Overview',
        subtitle: '',
        initiallyExpanded: true,
        lines: const [
          PcosLine(
            text:
                'Endometriosis occurs when endometrial-like tissue implants on organs outside the uterus — most commonly the ovaries, fallopian tubes, and pelvic lining. This tissue responds to hormonal changes just like the uterine lining, causing inflammation, scarring, and pain.',
          ),
        ],
      ),
      const SizedBox(height: 20),
      _sectionLabel('SYMPTOMS'),
      const SizedBox(height: 12),
      PcosCard(
        emoji: '🩺',
        badgeColor: AppColors.periodRed,
        title: 'Common Symptoms',
        subtitle: 'How endometriosis presents',
        initiallyExpanded: true,
        lines: const [
          PcosLine(
            boldLead: 'Dysmenorrhoea',
            text:
                'Severely painful periods that worsen over time, often not relieved by standard painkillers.',
          ),
          PcosLine(
            boldLead: 'Dyspareunia',
            text:
                'Pain during or after sexual intercourse, particularly deep penetration.',
          ),
          PcosLine(
            boldLead: 'Chronic pelvic pain',
            text: 'Persistent lower abdominal pain outside of periods.',
          ),
          PcosLine(
            boldLead: 'Bowel & bladder symptoms',
            text:
                'Pain during bowel movements or urination, especially during menstruation.',
          ),
          PcosLine(
            boldLead: 'Infertility',
            text:
                'Present in up to 50% of people with endometriosis, often the first presenting complaint.',
          ),
        ],
        tags: const [
          PcosTag('Severe period pain', AppColors.symptomOrange),
          PcosTag('Painful sex', AppColors.symptomOrange),
          PcosTag('Chronic pelvic pain', AppColors.symptomOrange),
          PcosTag('Infertility', AppColors.periodRed),
        ],
      ),
      const SizedBox(height: 20),
      _sectionLabel('DIAGNOSIS'),
      const SizedBox(height: 12),
      PcosCard(
        emoji: '🔬',
        badgeColor: AppColors.ovulationTeal,
        title: 'Stages & Diagnosis',
        subtitle: 'Classification and how it is confirmed',
        initiallyExpanded: true,
        lines: const [
          PcosLine(
            text:
                'Endometriosis is staged I–IV (minimal to severe) based on the extent and location of lesions. Staging does not always correlate with symptom severity — Stage I can cause intense pain while Stage IV may be asymptomatic.',
          ),
          PcosLine(
            boldLead: 'Definitive diagnosis',
            text:
                'requires laparoscopy (keyhole surgery) with biopsy. Ultrasound and MRI can detect endometriomas (ovarian cysts) and deep infiltrating disease but cannot confirm all forms.',
          ),
        ],
        tags: const [
          PcosTag('Laparoscopy (gold standard)', AppColors.ovulationTeal),
          PcosTag('Ultrasound', AppColors.moodYellow),
          PcosTag('MRI', AppColors.symptomOrange),
        ],
      ),
      const SizedBox(height: 20),
      _sectionLabel('TREATMENT'),
      const SizedBox(height: 12),
      PcosCard(
        emoji: '💊',
        badgeColor: AppColors.periodRed,
        title: 'Medical & Surgical Options',
        subtitle: 'Managing pain and fertility',
        initiallyExpanded: true,
        lines: const [
          PcosLine(
            boldLead: 'Hormonal therapies',
            text:
                'The combined OCP, progestogens, GnRH agonists, and the levonorgestrel IUD all suppress menstruation and reduce lesion activity.',
          ),
          PcosLine(
            boldLead: 'Pain management',
            text:
                'NSAIDs (ibuprofen, naproxen) taken at the start of a period can reduce prostaglandin-driven pain.',
          ),
          PcosLine(
            boldLead: 'Surgery',
            text:
                'Laparoscopic excision removes lesions and adhesions, providing significant pain relief. Recurrence rates vary. Hysterectomy is a last resort and does not guarantee cure if ovaries are retained.',
          ),
        ],
        tags: const [
          PcosTag('OCP / progestogens', AppColors.ovulationTeal),
          PcosTag('Excision surgery', AppColors.primary),
          PcosTag('GnRH agonists', AppColors.symptomOrange),
          PcosTag('NSAIDs', AppColors.periodRed),
        ],
      ),
    ];
  }

  // ==== Symptom checker (Detection tab) ====
  final Map<String, int> _answers = {};
  bool _showResult = false;
  bool _savedToDiary = false;

  void _resetCheck() {
    setState(() {
      _answers.clear();
      _showResult = false;
      _savedToDiary = false;
    });
  }

  void _saveCheckSummaryToDiary() {
    if (_savedToDiary) return;
    final summary = _diarySummaryText();
    final entry = DiaryEntry(
      date: DateTime.now(),
      text: summary,
      symptomTags: const ['Endo check'],
    );

    HealthProfileService().updateProfile((p) {
      final updated = List<DiaryEntry>.from(p.diaryEntries)..add(entry);
      return p.copyWith(diaryEntries: updated);
    });

    setState(() => _savedToDiary = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          tr('Saved to your diary'),
          style: const TextStyle(color: Colors.white),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildDetectionTab() {
    if (_showResult) return _buildResultView();
    return _buildCheckerView();
  }

  Widget _buildCheckerView() {
    final answered = _answers.length;
    final allAnswered = answered == _endoQuestions.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _detectionIntroCard(),
        const SizedBox(height: 14),
        Text(
          tr('Answer all 10 questions to see your result'),
          style: AppTextStyles.sans(
            size: 12,
            weight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < _endoQuestions.length; i++)
          _questionCard(i, questions: _endoQuestions),
        const SizedBox(height: 18),
        AppTapScale(
          onTap: allAnswered ? () => setState(() => _showResult = true) : null,
          child: Container(
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: allAnswered
                  ? AppColors.primary
                  : AppColors.primary.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              tr('See my results'),
              style: AppTextStyles.sans(
                size: 14,
                weight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _detectionIntroCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withValues(alpha: 0.15),
            ),
            child: const Center(
              child: Text('🩺', style: TextStyle(fontSize: 24)),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            tr('Symptom Checker'),
            style: AppTextStyles.sans(size: 14, weight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            tr(
              'Answer a few quick questions about your pain and cycle to see '
              'if it may be worth discussing endometriosis with a doctor.',
            ),
            textAlign: TextAlign.center,
            style: AppTextStyles.sans(
              size: 12,
              color: AppColors.textSecondary,
            ).copyWith(height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _questionCard(int index, {required List<_EndoQuestion> questions}) {
    final q = questions[index];
    final selected = _answers['q$index'] ?? -1;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected >= 0
              ? AppColors.primary.withValues(alpha: 0.45)
              : AppColors.cardBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(q.emoji, style: const TextStyle(fontSize: 15)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr(q.question),
                  style: AppTextStyles.sans(
                    size: 13,
                    weight: FontWeight.w600,
                  ).copyWith(height: 1.35),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var oi = 0; oi < q.options.length; oi++)
                _optionChip(
                  q.options[oi].label,
                  selected: oi == selected,
                  onTap: () => setState(() => _answers['q$index'] = oi),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _optionChip(
    String label, {
    required bool selected,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.7)
                : AppColors.cardBorder,
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.sans(
            size: 11.5,
            weight: selected ? FontWeight.w700 : FontWeight.w400,
            color: selected ? AppColors.primary : AppColors.textSecondary,
          ).copyWith(height: 1.25),
        ),
      ),
    );
  }

  // ---- scoring ----

  int get _totalScore {
    var sum = 0;
    for (var i = 0; i < _endoQuestions.length; i++) {
      final sel = _answers['q$i'];
      if (sel == null) continue;
      if (sel < 0 || sel >= _endoQuestions[i].options.length) continue;
      sum += _endoQuestions[i].options[sel].score;
    }
    return sum;
  }

  /// Keeps "some of each" answers from never reaching the discussion tier
  /// on their own: a convincing endo pattern needs real period pain plus
  /// a cyclical/positional sign, or a high overall score.
  bool get _doctorsDiscussionTier {
    int sel(int i) => _answers['q$i'] ?? -1;
    final periodPainScore =
        sel(0) >= 0 && sel(0) < _endoQuestions[0].options.length
        ? _endoQuestions[0].options[sel(0)].score
        : -1;
    final hasUrgentOrSeverePain = periodPainScore >= 2;
    final cyclicalSign =
        sel(3) >= 0 || sel(6) >= 1; // toilet pain OR nausea often
    final positionalSign = sel(2) >= 2; // deep pain with sex, sometimes/most
    final painBetweenPeriods = sel(1) >= 1;
    final longStanding = sel(7) >= 1; // 6+ months
    final highScore = _totalScore >= 8;

    return highScore ||
        (hasUrgentOrSeverePain &&
            longStanding &&
            (cyclicalSign || positionalSign)) ||
        (hasUrgentOrSeverePain && painBetweenPeriods && longStanding);
  }

  String get _verdictTitle {
    if (_doctorsDiscussionTier) return tr('Worth discussing with a doctor');
    if (_totalScore >= 4) return tr('Some signs — keep tracking');
    return tr('Few typical signs right now');
  }

  String get _verdictBody {
    if (_doctorsDiscussionTier) {
      return tr(
        'Your answers match several signs commonly reported with '
        'endometriosis. This is not a diagnosis — only a specialist exam '
        'and usually laparoscopy can confirm it — but please make an '
        'appointment and take this summary with you.',
      );
    }
    if (_totalScore >= 4) {
      return tr(
        'You reported a few signs linked with endometriosis. Track for '
        'another cycle or two (note the days pain peaks) and mention it '
        'at your next checkup if it continues.',
      );
    }
    return tr(
      'Your answers do not show many typical endometriosis signs right '
      'now. If your pain pattern changes later, you can retake this '
      'check any time.',
    );
  }

  Color get _verdictColor {
    if (_doctorsDiscussionTier) return AppColors.periodRed;
    if (_totalScore >= 4) return AppColors.symptomOrange;
    return AppColors.ovulationTeal;
  }

  List<String> get _reportedSigns {
    final out = <String>[];
    for (var i = 0; i < _endoQuestions.length; i++) {
      final sel = _answers['q$i'];
      if (sel == null || sel < 0 || sel >= _endoQuestions[i].options.length) {
        continue;
      }
      out.add(
        '${_endoQuestions[i].question} → ${_endoQuestions[i].options[sel].label}',
      );
    }
    return out;
  }

  String _diarySummaryText() {
    final now = DateTime.now();
    final date = '${now.day}/${now.month}/${now.year}';
    final signs = _reportedSigns.map((s) => '• $s').join('\n');
    return 'Endo check ($date) — score $_totalScore/19: '
        '$_verdictTitle\n$signs';
  }

  Widget _buildResultView() {
    final signs = _reportedSigns;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _verdictColor.withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _verdictColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${tr('Score')} $_totalScore/19',
                      style: AppTextStyles.sans(
                        size: 12,
                        weight: FontWeight.w700,
                        color: _verdictColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _verdictTitle,
                style: AppTextStyles.serif(
                  size: 18,
                  weight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _verdictBody,
                style: AppTextStyles.sans(
                  size: 12.5,
                  color: AppColors.textSecondary,
                ).copyWith(height: 1.55),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (signs.isNotEmpty) ...[
          _sectionLabel('WHAT YOU REPORTED'),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final s in signs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('• ', style: TextStyle(fontSize: 12.5)),
                        Expanded(
                          child: Text(
                            tr(s),
                            style: AppTextStyles.sans(
                              size: 12.5,
                              color: AppColors.textPrimary,
                            ).copyWith(height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        _sectionLabel('WHAT TO ASK YOUR DOCTOR'),
        const SizedBox(height: 10),
        PcosCard(
          emoji: '🗣️',
          badgeColor: AppColors.ovulationTeal,
          title: tr('Tips for your appointment'),
          subtitle: '',
          initiallyExpanded: true,
          lines: [
            PcosLine(
              text: tr(
                'Describe where and when the pain hits — especially if it '
                'shows up around your period.',
              ),
            ),
            PcosLine(
              text: tr(
                'Ask whether a pelvic ultrasound or a gynaecologist '
                'referral makes sense for you.',
              ),
            ),
            PcosLine(
              text: tr(
                'Ask which pain-relief or hormonal options are safe for '
                'your situation.',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          tr(
            'This checker is educational — it cannot confirm or rule out '
            'endometriosis.',
          ),
          style: AppTextStyles.sans(
            size: 11,
            color: AppColors.textSecondary,
          ).copyWith(height: 1.4),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: AppTapScale(
                onTap: _savedToDiary ? null : _saveCheckSummaryToDiary,
                child: Container(
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _savedToDiary
                        ? AppColors.ovulationTeal.withValues(alpha: 0.4)
                        : AppColors.primary,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    tr(_savedToDiary ? 'Saved ✓' : 'Save to my diary'),
                    style: AppTextStyles.sans(
                      size: 13,
                      weight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: AppTapScale(
                onTap: _resetCheck,
                child: Container(
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: Text(
                    tr('Retake check'),
                    style: AppTextStyles.sans(
                      size: 13,
                      weight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: AppTextStyles.sans(
        size: 11,
        weight: FontWeight.w600,
        color: AppColors.textSecondary,
      ),
    );
  }

  Widget _heroCard() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppColors.ovulationTeal.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
            child: const Center(
              child: Text('🔭', style: TextStyle(fontSize: 24)),
            ),
          ),
          const SizedBox(height: 14),
          Text('Endometriosis Guide', style: AppTextStyles.serif(size: 19)),
          const SizedBox(height: 8),
          Text(
            'A condition where tissue similar to the uterine lining grows outside the uterus, affecting roughly 1 in 10 people with ovaries.',
            textAlign: TextAlign.center,
            style: AppTextStyles.sans(
              size: 12,
              color: AppColors.textSecondary,
            ).copyWith(height: 1.5),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Symptom-checker data. Scores are heuristics (roughly weighted by
// how typical each sign is of endometriosis), used only to decide
// "worth a doctor visit now / track first" — never a diagnosis.
// ============================================================

class _EndoOption {
  final String label;
  final int score;
  const _EndoOption(this.label, [this.score = 0]);
}

class _EndoQuestion {
  final String emoji;
  final String question;
  final List<_EndoOption> options;
  const _EndoQuestion(this.emoji, this.question, this.options);
}

const List<_EndoQuestion> _endoQuestions = [
  _EndoQuestion('🩸', 'How painful do most of your periods feel?', [
    _EndoOption('Barely painful or no period pain', 0),
    _EndoOption('Painful, but painkillers usually handle it', 1),
    _EndoOption('Severe — painkillers only partly help, affects my day', 2),
    _EndoOption('Very severe — vomiting, fainting, or nothing helps', 3),
  ]),
  _EndoQuestion(
    '📅',
    'Between periods, how often does your lower belly hurt?',
    [
      _EndoOption('Rarely or never', 0),
      _EndoOption('Some days each month', 1),
      _EndoOption('Most days', 2),
    ],
  ),
  _EndoQuestion('💞', 'Do you feel deep pain during or after sex?', [
    _EndoOption('Does not apply to me', 0),
    _EndoOption('Not really', 0),
    _EndoOption('Sometimes', 2),
    _EndoOption('Most of the time', 3),
  ]),
  _EndoQuestion('🚽', 'During your period, is it painful to use the toilet?', [
    _EndoOption('No', 0),
    _EndoOption('Yes — pain passing stool or urine', 2),
  ]),
  _EndoQuestion(
    '🌊',
    'Is your bleeding very heavy (soaking a pad hourly) or longer than 7 days?',
    [_EndoOption('No', 0), _EndoOption('Yes', 1)],
  ),
  _EndoQuestion('🔋', 'Is there crushing tiredness that is hard to explain?', [
    _EndoOption('No', 0),
    _EndoOption('Yes', 1),
  ]),
  _EndoQuestion(
    '🤢',
    'With your periods do you feel nauseated, vomit, or have diarrhoea?',
    [
      _EndoOption('None of these', 0),
      _EndoOption('Sometimes', 1),
      _EndoOption('Often or severe', 2),
    ],
  ),
  _EndoQuestion('⏳', 'How long have you had these symptoms?', [
    _EndoOption('A few months', 0),
    _EndoOption('6 months to 2 years', 1),
    _EndoOption('More than 2 years, gradually worsening', 2),
  ]),
  _EndoQuestion(
    '👪',
    'Any close family member (mother, sister) with endometriosis?',
    [_EndoOption('No, or I don\'t know', 0), _EndoOption('Yes', 1)],
  ),
  _EndoQuestion(
    '🤰',
    'Trying for a pregnancy for 12+ months without success, or fertility is a major worry?',
    [_EndoOption('Not applicable to me', 0), _EndoOption('Yes', 2)],
  ),
];
