import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/app_brand.dart';
import '../widgets/app_card.dart';

class QAItem {
  final String question;
  final String answer;
  const QAItem(this.question, this.answer);
}

class TopicItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final List<QAItem> qa;

  const TopicItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.qa,
  });
}

class LearnScreen extends StatelessWidget {
  const LearnScreen({super.key});

  static final List<TopicItem> _topics = [
    TopicItem(
      icon: Icons.accessibility_rounded,
      title: 'Anatomy',
      subtitle: 'Reproductive system basics',
      color: AppColors.accent,
      qa: const [
        QAItem(
          'What are the main internal reproductive organs?',
          'The ovaries produce eggs and hormones. The fallopian tubes carry eggs from the ovaries to the uterus. The uterus is where a fetus develops. The cervix connects the uterus to the vagina.',
        ),
        QAItem(
          'What does the vagina actually do?',
          'The vagina is the muscular canal connecting the cervix to the outside of the body. It serves as the birth canal, the pathway for menstrual blood, and the entry point for sexual intercourse. It is self-cleaning and produces natural discharge.',
        ),
        QAItem(
          'What is the hymen?',
          'The hymen is a thin membrane that partially covers the vaginal opening. It varies widely in shape and size. It does not indicate virginity and may stretch or tear through exercise, tampon use, or sexual activity.',
        ),
      ],
    ),
    TopicItem(
      icon: Icons.biotech_rounded,
      title: 'Hormones',
      subtitle: 'How they affect your cycle',
      color: AppColors.primary,
      qa: const [
        QAItem(
          'What hormones control my cycle?',
          'Estrogen and progesterone rise and fall through the month, while FSH and LH from the pituitary gland trigger egg development and ovulation. Together they drive every phase of the cycle.',
        ),
        QAItem(
          'Why do I feel different in each phase?',
          'Estrogen tends to lift energy and mood in the first half of the cycle, while progesterone in the second half can cause fatigue, bloating, and mood changes as it eventually drops before your period.',
        ),
        QAItem(
          'Can hormone levels be tested?',
          'Yes. Blood tests can measure estrogen, progesterone, LH, FSH, and thyroid hormones, which are often checked together when investigating irregular cycles.',
        ),
      ],
    ),
    TopicItem(
      icon: Icons.health_and_safety_rounded,
      title: 'STIs',
      subtitle: 'Common infections & prevention',
      color: AppColors.textPrimary,
      qa: const [
        QAItem(
          'How are STIs usually transmitted?',
          'Most STIs spread through vaginal, anal, or oral sex, and some, like herpes and HPV, can spread through skin-to-skin contact even without penetration.',
        ),
        QAItem(
          'Can you have an STI with no symptoms?',
          'Yes. Many STIs, including chlamydia and gonorrhea, often cause no symptoms at all, which is why regular screening matters even if you feel fine.',
        ),
        QAItem(
          'How can risk be reduced?',
          'Condoms significantly lower the risk of most STIs, and regular testing with new or multiple partners helps catch infections early, when they are easiest to treat.',
        ),
      ],
    ),
    TopicItem(
      icon: Icons.water_drop_rounded,
      title: 'Menstruation',
      subtitle: "What's normal, what's not",
      color: AppColors.periodRed,
      qa: const [
        QAItem(
          'What counts as a "normal" cycle?',
          "A typical cycle ranges from 21 to 35 days, with bleeding lasting 2 to 7 days. Some variation month to month is normal and doesn't necessarily indicate a problem.",
        ),
        QAItem(
          'When is bleeding considered too heavy?',
          'Soaking through a pad or tampon every hour for several hours, passing large clots, or bleeding for more than 7 days can indicate heavy menstrual bleeding worth discussing with a doctor.',
        ),
        QAItem(
          'Is period pain always normal?',
          "Mild cramping is common, but pain that stops you from daily activities, doesn't respond to over-the-counter painkillers, or worsens over time can be a sign of an underlying condition like endometriosis.",
        ),
      ],
    ),
    TopicItem(
      icon: Icons.sentiment_very_dissatisfied_rounded,
      title: 'Myths',
      subtitle: 'Debunking common myths',
      color: AppColors.primary,
      qa: const [
        QAItem(
          "Myth: You can't get pregnant during your period.",
          'False. Sperm can survive up to 5 days, so if you ovulate early or have a short cycle, sex during your period can still lead to pregnancy.',
        ),
        QAItem(
          'Myth: Irregular periods always mean something is wrong.',
          "Not necessarily. Cycles can vary due to stress, travel, or weight changes. Consistently irregular cycles over several months are what's worth checking with a doctor.",
        ),
        QAItem(
          'Myth: You lose a lot of blood during your period.',
          'Most people lose only 2 to 3 tablespoons of blood across an entire period, even though it can feel like more.',
        ),
      ],
    ),
  ];

  String _formattedDate() {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final now = DateTime.now();
    return '${weekdays[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.gutter,
          vertical: AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppWordmark(
              trailing: Text(
                _formattedDate(),
                style: AppTextStyles.sans(
                  size: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const AppSectionHeader(label: 'Topics'),
            _buildTopicGrid(context),
          ],
        ),
      ),
    );
  }

  Widget _buildTopicGrid(BuildContext context) {
    // Sized off the incoming constraint, not `MediaQuery.size.width`. The shell
    // caps content at 640px, so on a wide window the viewport width made each
    // card wider than the box it sat in and it overflowed.
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = AppSpacing.sm;
        final cardWidth = (constraints.maxWidth - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: _topics
              .map(
                (topic) => SizedBox(
                  width: cardWidth,
                  child: _topicCard(context, topic),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _topicCard(BuildContext context, TopicItem topic) {
    return AppCard(
      onTap: () => _showTopicSheet(context, topic),
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 14),
      child: Column(
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: topic.color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(topic.icon, size: 23, color: topic.color),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            topic.title,
            textAlign: TextAlign.center,
            style: AppTextStyles.sans(size: 14, weight: FontWeight.w700),
          ),
          const SizedBox(height: 3),
          Text(
            topic.subtitle,
            textAlign: TextAlign.center,
            style: AppTextStyles.sans(
              size: 11.5,
              color: AppColors.textSecondary,
            ).copyWith(height: 1.3),
          ),
        ],
      ),
    );
  }

  void _showTopicSheet(BuildContext context, TopicItem topic) {
    showModalBottomSheet(
      context: context,
      // Shape, background and drag handle all come from `bottomSheetTheme`
      // now, instead of being re-specified per sheet.
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.85,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: topic.color.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(topic.icon, size: 18, color: topic.color),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          topic.title == 'Anatomy'
                              ? 'Reproductive Anatomy'
                              : topic.title,
                          style: AppTextStyles.serif(size: 19),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: const Icon(Icons.close, size: 20),
                        color: AppColors.textSecondary,
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  for (int i = 0; i < topic.qa.length; i++) ...[
                    _qaBlock(topic.qa[i], topic.color),
                    if (i != topic.qa.length - 1)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Divider(height: 1, color: AppColors.cardBorder),
                      ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _qaBlock(QAItem qa, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          qa.question,
          style: AppTextStyles.sans(
            size: 14,
            weight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(height: 6),
        Text(qa.answer, style: AppTextStyles.body()),
      ],
    );
  }
}
