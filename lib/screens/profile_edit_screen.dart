import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import '../l10n/app_text.dart';
import '../services/health_profile_service.dart';
import '../theme/app_theme.dart';

/// Direct editor for the Health Profile (SRS FR-84).
///
/// Before this screen the Profile tab was read-only: demographics,
/// lifestyle, reproductive-history and wellbeing values could only be
/// filled indirectly (AI updates, the PCOS form). The fields here are
/// the same ones the Profile tab displays; every field is optional and
/// empty input clears the stored value.
///
/// Deliberately NOT editable here:
/// - cycle length, which is a written copy of the Cycle tracker's
///   setting (task 3.6; edit it in Settings -> Cycle Data),
/// - the current contraception method, owned by the Protection tab's
///   "I'm using this method" tracker,
/// - last check-in, which is a timestamp written by the AI check-in.
///
/// Numeric bounds mirror the PCOS form's server-matched ranges where a
/// field overlaps (age 10-100, weight 20-350 kg, height 100-250 cm);
/// sleep is the plain 0-24 sanity range and stress is the 1-5 scale
/// the Profile tab already displays.
class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _service = HealthProfileService();
  final _formKey = GlobalKey<FormState>();

  final _ageController = TextEditingController();
  final _weightController = TextEditingController();
  final _heightController = TextEditingController();
  final _sleepController = TextEditingController();
  final _lifestyleNotesController = TextEditingController();
  final _wellbeingNotesController = TextEditingController();

  bool? _regularExercise;
  bool? _fastFoodFrequent;
  String? _maritalStatus;
  String? _exerciseFrequency;
  String? _dietQuality;
  String? _cycleRegularity;
  int? _stressLevel;

  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ageController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    _sleepController.dispose();
    _lifestyleNotesController.dispose();
    _wellbeingNotesController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final profile = await _service.loadProfile();
    if (!mounted) return;
    setState(() {
      _ageController.text = profile.demographics.ageYrs?.toString() ?? '';
      _weightController.text = profile.demographics.weightKg?.toString() ?? '';
      _heightController.text = profile.demographics.heightCm?.toString() ?? '';
      _sleepController.text =
          profile.lifestyle.averageSleepHours?.toString() ?? '';
      _lifestyleNotesController.text = profile.lifestyle.notes ?? '';
      _wellbeingNotesController.text = profile.mentalHealth.notes ?? '';
      _regularExercise = profile.lifestyle.regularExercise;
      _fastFoodFrequent = profile.lifestyle.fastFoodFrequent;
      _maritalStatus = profile.demographics.maritalStatus;
      _exerciseFrequency = profile.lifestyle.exerciseFrequency;
      _dietQuality = profile.lifestyle.dietQuality;
      _cycleRegularity = profile.reproductiveHistory.cycleRegularity;
      _stressLevel = profile.mentalHealth.selfReportedStressLevel;
      _loading = false;
    });
  }

  int? _intOrNull(TextEditingController c) {
    final text = c.text.trim();
    if (text.isEmpty) return null;
    return int.tryParse(text);
  }

  double? _doubleOrNull(TextEditingController c) {
    final text = c.text.trim();
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }

  String? _stringOrNull(TextEditingController c) {
    final text = c.text.trim();
    return text.isEmpty ? null : text;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);

    await _service.updateProfile(
      (p) => p.copyWith(
        demographics: p.demographics.copyWith(
          ageYrs: _intOrNull(_ageController),
          weightKg: _doubleOrNull(_weightController),
          heightCm: _doubleOrNull(_heightController),
          maritalStatus: _maritalStatus,
        ),
        lifestyle: p.lifestyle.copyWith(
          regularExercise: _regularExercise,
          exerciseFrequency: _exerciseFrequency,
          dietQuality: _dietQuality,
          fastFoodFrequent: _fastFoodFrequent,
          averageSleepHours: _doubleOrNull(_sleepController),
          notes: _stringOrNull(_lifestyleNotesController),
        ),
        reproductiveHistory: p.reproductiveHistory.copyWith(
          cycleRegularity: _cycleRegularity,
        ),
        mentalHealth: p.mentalHealth.copyWith(
          selfReportedStressLevel: _stressLevel,
          notes: _stringOrNull(_wellbeingNotesController),
        ),
      ),
    );

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Health profile saved')));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _header(context),
                      const SizedBox(height: 20),
                      _section('Demographics', '👤', AppColors.primary, [
                        _numberField(
                          _ageController,
                          'Age',
                          'e.g. 24',
                          key: const ValueKey('profile-age'),
                          min: 10,
                          max: 100,
                          decimals: false,
                        ),
                        _numberField(
                          _weightController,
                          'Weight (kg)',
                          'e.g. 58',
                          key: const ValueKey('profile-weight'),
                          min: 20,
                          max: 350,
                        ),
                        _numberField(
                          _heightController,
                          'Height (cm)',
                          'e.g. 162',
                          key: const ValueKey('profile-height'),
                          min: 100,
                          max: 250,
                        ),
                        _dropdown(
                          label: 'Marital status',
                          value: _maritalStatus,
                          options: const ['Single', 'Married', 'Other'],
                          onChanged: (v) => setState(() => _maritalStatus = v),
                        ),
                      ]),
                      const SizedBox(height: 12),
                      _section('Lifestyle', '🌿', AppColors.ovulationTeal, [
                        _switchRow(
                          'Regular exercise',
                          _regularExercise,
                          (v) => setState(() => _regularExercise = v),
                        ),
                        _dropdown(
                          label: 'Exercise frequency',
                          value: _exerciseFrequency,
                          options: const ['Never', '1-2x/week', '3+/week'],
                          onChanged: (v) =>
                              setState(() => _exerciseFrequency = v),
                        ),
                        _dropdown(
                          label: 'Diet quality',
                          value: _dietQuality,
                          options: const ['Poor', 'Average', 'Good'],
                          onChanged: (v) => setState(() => _dietQuality = v),
                        ),
                        _switchRow(
                          'Frequent fast food',
                          _fastFoodFrequent,
                          (v) => setState(() => _fastFoodFrequent = v),
                        ),
                        _numberField(
                          _sleepController,
                          'Average sleep (hours)',
                          'e.g. 7.5',
                          min: 0,
                          max: 24,
                        ),
                        _textField(
                          _lifestyleNotesController,
                          'Notes (optional)',
                          maxLines: 3,
                        ),
                      ]),
                      const SizedBox(height: 12),
                      _section(
                        'Reproductive Health',
                        '🩷',
                        AppColors.periodRed,
                        [
                          _dropdown(
                            label: 'Cycle regularity',
                            value: _cycleRegularity,
                            options: const ['Regular', 'Irregular'],
                            onChanged: (v) =>
                                setState(() => _cycleRegularity = v),
                          ),
                          // These two are owned elsewhere; shown so the
                          // user knows where they come from.
                          _hintRow(
                            'Cycle length is set in Settings → Cycle Data.',
                          ),
                          _hintRow(
                            'Current method is set from the Protection tab.',
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _section(
                        'Wellbeing (self-reported)',
                        '💛',
                        AppColors.moodYellow,
                        [
                          _stressDropdown(),
                          _textField(
                            _wellbeingNotesController,
                            'Notes (optional)',
                            maxLines: 3,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          key: const ValueKey('profile-save'),
                          onPressed: _saving ? null : _save,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Save profile'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: 'Back',
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          color: AppColors.textSecondary,
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: 2),
        Text('Edit profile', style: AppTextStyles.serif(size: 22)),
      ],
    );
  }

  Widget _section(
    String title,
    String emoji,
    Color color,
    List<Widget> children,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$emoji  $title',
            style: AppTextStyles.sans(
              size: 13,
              weight: FontWeight.w600,
              color: color,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _numberField(
    TextEditingController controller,
    String label,
    String hint, {
    required double min,
    required double max,
    bool decimals = true,
    Key? key,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        key: key,
        controller: controller,
        keyboardType: TextInputType.numberWithOptions(decimal: decimals),
        inputFormatters: [
          FilteringTextInputFormatter.allow(
            decimals ? RegExp(r'[0-9.]') : RegExp(r'[0-9]'),
          ),
        ],
        decoration: _decoration(hint).copyWith(labelText: tr(label)),
        validator: (value) {
          final text = value?.trim() ?? '';
          if (text.isEmpty) return null; // optional field
          final parsed = double.tryParse(text);
          if (parsed == null || !parsed.isFinite) return 'Enter a number';
          if (parsed < min || parsed > max) {
            return 'Must be between ${min.toInt()} and ${max.toInt()}';
          }
          return null;
        },
      ),
    );
  }

  Widget _textField(
    TextEditingController controller,
    String hint, {
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        decoration: _decoration(
          '',
        ).copyWith(hintText: tr(hint), labelText: tr(hint)),
      ),
    );
  }

  Widget _dropdown({
    required String label,
    required String? value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
  }) {
    // A value written by the AI or an older build may not be one of the
    // suggestions; keep it selectable instead of asserting on a
    // non-matching DropdownButton value.
    final legacy =
        (value != null && value.isNotEmpty && !options.contains(value))
        ? value
        : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<String>(
        initialValue: value == null || value.isEmpty ? '' : value,
        isExpanded: true,
        decoration: _decoration('').copyWith(labelText: tr(label)),
        items: [
          DropdownMenuItem<String>(value: '', child: Text(tr('Not set'))),
          ...options.map(
            (o) => DropdownMenuItem<String>(value: o, child: Text(o)),
          ),
          if (legacy != null)
            DropdownMenuItem<String>(value: legacy, child: Text(legacy)),
        ],
        onChanged: (v) => onChanged(v == null || v.isEmpty ? null : v),
      ),
    );
  }

  Widget _stressDropdown() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<int>(
        initialValue: _stressLevel ?? 0,
        isExpanded: true,
        decoration: _decoration(
          '',
        ).copyWith(labelText: tr('Stress level (1-5)')),
        items: [
          DropdownMenuItem<int>(value: 0, child: Text(tr('Not set'))),
          for (var i = 1; i <= 5; i++)
            DropdownMenuItem<int>(value: i, child: Text('$i')),
        ],
        onChanged: (v) =>
            setState(() => _stressLevel = (v == null || v == 0) ? null : v),
      ),
    );
  }

  Widget _switchRow(String label, bool? value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              tr(label),
              style: AppTextStyles.sans(size: 13, color: AppColors.textPrimary),
            ),
          ),
          Switch(value: value ?? false, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _hintRow(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 6),
      child: Text(
        tr(text),
        style: AppTextStyles.sans(
          size: 11,
          color: AppColors.textSecondary,
        ).copyWith(height: 1.4),
      ),
    );
  }

  InputDecoration _decoration(String hint) {
    return InputDecoration(
      hintText: hint.isEmpty ? null : tr(hint),
      hintStyle: AppTextStyles.sans(
        size: 12,
        color: AppColors.textSecondary.withValues(alpha: 0.7),
      ),
      labelStyle: AppTextStyles.sans(size: 12, color: AppColors.textSecondary),
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppColors.cardBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppColors.cardBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppColors.ovulationTeal),
      ),
    );
  }
}
