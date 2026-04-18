import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/auth_service.dart';
import '../../theme/moodiary_colors.dart';
import '../../utils/transitions.dart';
import '../../widgets/glass.dart';
import '../app_shell.dart';

class MbtiTestScreen extends StatefulWidget {
  final String userName;
  final bool requireCompanionSelection;
  final bool forceHomeOnComplete;
  final int? initialCompanionId;
  final String? initialCompanionName;

  const MbtiTestScreen({
    super.key,
    required this.userName,
    this.requireCompanionSelection = false,
    this.forceHomeOnComplete = false,
    this.initialCompanionId,
    this.initialCompanionName,
  });

  @override
  State<MbtiTestScreen> createState() => _MbtiTestScreenState();
}

class _MbtiQuestion {
  final String dimension;
  final String title;
  final String subtitle;

  const _MbtiQuestion({
    required this.dimension,
    required this.title,
    required this.subtitle,
  });
}

class _MbtiTestScreenState extends State<MbtiTestScreen> {
  static const _scaleLabels = [
    'Strongly disagree',
    'Disagree',
    'Neutral',
    'Agree',
    'Strongly agree',
  ];

  final List<int> _answers = List<int>.filled(_questions.length, 0);
  int _index = 0;
  bool _started = false;
  bool _submitting = false;
  bool _matching = false;
  Map<String, dynamic>? _result;
  String? _error;
  Map<String, dynamic>? _selectedCompanion;

  void _showReferencesDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Methodology & References'),
        content: const SingleChildScrollView(
          child: Text(
            'This is an MBTI-style educational assessment built for companion matching in Moodiary. '
            'It is not the official, licensed MBTI instrument.\n\n'
            'Design notes:\n'
            '- 30 Likert-scale items across E/I, S/N, T/F, J/P dimensions.\n'
            '- Deterministic scoring and companion recommendation mapping.\n'
            '- Results are stored as latest type plus test history.\n\n'
            'References used:\n'
            '1. Jung, C. G. (1921). Psychological Types.\n'
            '2. Myers & Briggs Foundation: MBTI Basics — https://www.myersbriggs.org/my-mbti-personality-type/mbti-basics/\n'
            '3. Pittenger, D. J. (2005). Cautionary comments regarding MBTI reliability/validity discussions.\n\n'
            'For implementation details in this project, see docs/mbti_methodology.md.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final userId =
          prefs.getString('user_id') ?? prefs.getString('userId') ?? '';
      final token = prefs.getString('token') ?? '';
      if (userId.isEmpty || token.isEmpty) {
        throw AuthException(
          'You need to sign in again before taking the MBTI test.',
        );
      }

      final payload = await AuthService.instance.submitMbtiTest(
        userId: userId,
        authToken: token,
        answers: _answers,
      );
      final result = payload['result'] as Map<String, dynamic>? ?? const {};

      await prefs.setString(
        'mbti_latest_type',
        (result['type'] ?? '').toString(),
      );

      if (!mounted) return;
      setState(() {
        _matching = true;
      });

      await Future<void>.delayed(const Duration(milliseconds: 1200));

      if (!mounted) return;
      final suggested =
          (result['suggestedCompanions'] as List<dynamic>? ?? const [])
              .cast<Map<String, dynamic>>();
      setState(() {
        _result = result;
        _selectedCompanion = suggested.isNotEmpty ? suggested.first : null;
        _matching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _matching = false;
      });
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _chooseCompanion(Map<String, dynamic> companion) async {
    final prefs = await SharedPreferences.getInstance();
    final companionId = (companion['id'] as num?)?.toInt();
    final companionName = companion['name']?.toString();
    if (companionId == null || companionName == null || companionName.isEmpty) {
      return;
    }

    await prefs.setInt('companion_id', companionId);
    await prefs.setString('companion_name', companionName);

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      FadeSlideRoute(
        page: MoodiaryShell(
          userName: widget.userName,
          companionId: companionId,
          companionName: companionName,
          initialTab: MoodiaryTab.home,
        ),
      ),
      (_) => false,
    );
  }

  void _finishWithoutSelection() {
    if (widget.forceHomeOnComplete &&
        widget.initialCompanionId != null &&
        widget.initialCompanionName != null) {
      Navigator.of(context).pushAndRemoveUntil(
        FadeSlideRoute(
          page: MoodiaryShell(
            userName: widget.userName,
            companionId: widget.initialCompanionId!,
            companionName: widget.initialCompanionName!,
            initialTab: MoodiaryTab.home,
          ),
        ),
        (_) => false,
      );
      return;
    }
    Navigator.of(context).pop(true);
  }

  Future<void> _takeLater() async {
    final suggestions =
        (_result?['suggestedCompanions'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>();
    final fallback =
        widget.initialCompanionId != null && widget.initialCompanionName != null
        ? <String, dynamic>{
            'id': widget.initialCompanionId,
            'name': widget.initialCompanionName,
          }
        : suggestions.isNotEmpty
        ? suggestions.first
        : <String, dynamic>{'id': 1, 'name': 'Sparky'};

    final companionId = (fallback['id'] as num?)?.toInt() ?? 1;
    final companionName =
        (fallback['name']?.toString().trim().isNotEmpty ?? false)
        ? fallback['name'].toString()
        : 'Sparky';

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('companion_id', companionId);
    await prefs.setString('companion_name', companionName);

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      FadeSlideRoute(
        page: MoodiaryShell(
          userName: widget.userName,
          companionId: companionId,
          companionName: companionName,
          initialTab: MoodiaryTab.home,
        ),
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_started) {
      return _buildIntro(context);
    }
    if (_matching) {
      return _buildMatching(context);
    }
    if (_result != null) {
      return _buildResult(context);
    }
    return _buildQuestions(context);
  }

  Widget _buildIntro(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 700;
    final gridCount = width >= 900
        ? 6
        : width >= 700
        ? 4
        : 3;
    const previewColors = [
      Color(0xFFE9D5FF),
      Color(0xFFBFDBFE),
      Color(0xFFBBF7D0),
      Color(0xFFFEF08A),
      Color(0xFFFECACA),
      Color(0xFFDDD6FE),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('MBTI Companion Test')),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(isWide ? 24 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Find your companion match',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(
              'Answer 30 short statements across four personality dimensions. We\'ll match you with companions that fit your result.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: _showReferencesDialog,
              icon: const Icon(Icons.menu_book_outlined, size: 18),
              label: const Text('Methodology & references'),
            ),
            const SizedBox(height: 8),
            Text(
              'Companion preview',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'These are visual previews only. Names appear after you get your result.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            GridView.builder(
              itemCount: 12,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: gridCount,
                crossAxisSpacing: isWide ? 12 : 10,
                mainAxisSpacing: isWide ? 12 : 10,
              ),
              itemBuilder: (context, i) => GlassContainer(
                blurSigma: 0,
                borderRadius: BorderRadius.circular(14),
                backgroundColor: previewColors[i % previewColors.length]
                    .withValues(alpha: context.isDarkMode ? 0.20 : 0.56),
                borderColor: context.mdGlassBorder,
                padding: EdgeInsets.zero,
                child: Center(
                  child: Image.asset(
                    'assets/doodle${i + 1}.png',
                    width: 60,
                    height: 60,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    errorBuilder: (context, error, stackTrace) =>
                        const Icon(Icons.sentiment_satisfied_alt_rounded),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 96),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: EdgeInsets.fromLTRB(
          isWide ? 24 : 20,
          10,
          isWide ? 24 : 20,
          MediaQuery.of(context).padding.bottom > 0 ? 14 : 18,
        ),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => setState(() => _started = true),
            style: ElevatedButton.styleFrom(
              backgroundColor: cs.primary,
              foregroundColor: cs.onPrimary,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('Start MBTI Test'),
          ),
        ),
      ),
    );
  }

  Widget _buildQuestions(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final done = _answers.where((a) => a != 0).length;
    final question = _questions[_index];
    final answeredValue = _answers[_index];

    return Scaffold(
      appBar: AppBar(title: const Text('MBTI Questions')),
      body: Padding(
        padding: EdgeInsets.all(
          MediaQuery.of(context).size.width >= 700 ? 20 : 16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(value: done / _questions.length),
            const SizedBox(height: 8),
            Text(
              'Question ${_index + 1} of ${_questions.length}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: GlassContainer(
                blurSigma: context.mdGlassBlurMedium,
                borderRadius: BorderRadius.circular(14),
                backgroundColor: context.mdGlassSurfaceStrong,
                borderColor: context.mdGlassBorder,
                padding: const EdgeInsets.all(16),
                child: Text(
                  question.title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              question.subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            ...List.generate(5, (i) {
              final value = i + 1;
              final isSelected = answeredValue == value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => _answers[_index] = value),
                  child: GlassContainer(
                    blurSigma: context.mdGlassBlurMedium,
                    borderRadius: BorderRadius.circular(12),
                    backgroundColor: isSelected
                        ? cs.primaryContainer.withValues(alpha: 0.72)
                        : context.mdGlassSurfaceStrong,
                    borderColor: isSelected
                        ? cs.primary
                        : context.mdGlassBorder,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isSelected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: isSelected ? cs.primary : cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_scaleLabels[i]),
                              if (i == 0)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    'Dimension: ${question.dimension}',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(color: cs.onSurfaceVariant),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: TextStyle(color: cs.error)),
              ),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _index == 0
                        ? null
                        : () => setState(() => _index -= 1),
                    child: const Text('Back'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _submitting
                        ? null
                        : () {
                            if (_answers[_index] == 0) {
                              setState(() {
                                _error =
                                    'Please select an answer before continuing.';
                              });
                              return;
                            }
                            if (_index < _questions.length - 1) {
                              setState(() {
                                _index += 1;
                                _error = null;
                              });
                            } else {
                              _submit();
                            }
                          },
                    child: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _index == _questions.length - 1 ? 'Submit' : 'Next',
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMatching(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Matching Companions')),
      body: Center(
        child: GlassContainer(
          blurSigma: context.mdGlassBlurSmall,
          borderRadius: BorderRadius.circular(20),
          backgroundColor: context.mdGlassSurfaceStrong,
          borderColor: context.mdGlassBorder,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Finding the companion who understands you...'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResult(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final type = (_result!['type'] ?? 'Unknown').toString();
    final suggested =
        (_result!['suggestedCompanions'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>();

    int companionIdOf(Map<String, dynamic> companion) {
      final raw = companion['id'];
      if (raw is num) return raw.toInt();
      return int.tryParse(raw?.toString() ?? '') ?? 0;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('You\'re Matched')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GlassContainer(
            blurSigma: context.mdGlassBlurMedium,
            borderRadius: BorderRadius.circular(16),
            backgroundColor: context.mdGlassSurfaceStrong,
            borderColor: context.mdGlassBorder,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your MBTI Type',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    type,
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Suggested companions for your personality:',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (suggested.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Choose 1 of the ${suggested.length} companions to proceed.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          ...suggested.map((companion) {
            final companionId = companionIdOf(companion);
            final isSelected = _selectedCompanion?['id'] == companion['id'];
            return GlassContainer(
              blurSigma: 1,
              borderRadius: BorderRadius.circular(12),
              backgroundColor: isSelected
                  ? cs.primaryContainer.withValues(alpha: 0.72)
                  : context.mdGlassSurfaceStrong,
              borderColor: isSelected ? cs.primary : context.mdGlassBorder,
              padding: EdgeInsets.zero,
              child: ListTile(
                selected: isSelected,
                leading: CircleAvatar(
                  backgroundColor: Colors.white,
                  child: Image.asset(
                    'assets/doodle$companionId.png',
                    width: 34,
                    height: 34,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    errorBuilder: (context, error, stackTrace) => const Icon(
                      Icons.sentiment_satisfied_alt_rounded,
                      size: 20,
                    ),
                  ),
                ),
                trailing: Icon(
                  isSelected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: isSelected ? cs.primary : cs.onSurfaceVariant,
                ),
                title: Text(
                  (companion['name'] ?? 'Companion').toString(),
                  style: TextStyle(color: context.mdPrimaryText),
                ),
                subtitle: Text(
                  (companion['description'] ?? '').toString(),
                  style: TextStyle(color: context.mdSecondaryText),
                ),
                onTap: () => setState(() => _selectedCompanion = companion),
              ),
            );
          }),
          const SizedBox(height: 8),
          if (_selectedCompanion != null)
            GlassContainer(
              blurSigma: 1,
              borderRadius: BorderRadius.circular(12),
              backgroundColor: cs.primaryContainer.withValues(alpha: 0.74),
              borderColor: context.mdGlassBorder,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: Colors.white,
                          child: Image.asset(
                            'assets/doodle${companionIdOf(_selectedCompanion!)}.png',
                            width: 24,
                            height: 24,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(
                                  Icons.sentiment_satisfied_alt_rounded,
                                  size: 14,
                                ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "You're matched with ${_selectedCompanion!['name']}!",
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text((_selectedCompanion!['description'] ?? '').toString()),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: _showReferencesDialog,
            icon: const Icon(Icons.menu_book_outlined, size: 18),
            label: const Text('View methodology & references'),
          ),
          const SizedBox(height: 6),
          if (widget.requireCompanionSelection) ...[
            ElevatedButton(
              onPressed: _selectedCompanion == null
                  ? null
                  : () => _chooseCompanion(_selectedCompanion!),
              child: const Text('Get Started'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _takeLater,
              child: const Text('Take later'),
            ),
          ] else
            ElevatedButton(
              onPressed: _finishWithoutSelection,
              child: Text(
                widget.forceHomeOnComplete ? 'Continue to Home' : 'Done',
              ),
            ),
        ],
      ),
    );
  }
}

const List<_MbtiQuestion> _questions = [
  _MbtiQuestion(
    dimension: 'E/I',
    title: 'I feel energized after spending time with many people.',
    subtitle:
        'Extraversion is about drawing energy from interaction, while introversion is about recharging through quieter reflection.',
  ),
  _MbtiQuestion(
    dimension: 'E/I',
    title: 'I prefer to process my thoughts alone before speaking.',
    subtitle:
        'Introversion often shows up as needing a private moment to organize thoughts before sharing them.',
  ),
  _MbtiQuestion(
    dimension: 'E/I',
    title: 'I usually start conversations in group settings.',
    subtitle:
        'Extraversion tends to feel natural in active, social settings where interaction keeps the energy moving.',
  ),
  _MbtiQuestion(
    dimension: 'E/I',
    title: 'Quiet time is essential for me after social events.',
    subtitle:
        'Introversion often means recovery happens after the social energy is spent.',
  ),
  _MbtiQuestion(
    dimension: 'E/I',
    title: 'I think better by talking ideas out loud.',
    subtitle:
        'Extraversion can show up as thinking through ideas in conversation instead of in silence.',
  ),
  _MbtiQuestion(
    dimension: 'E/I',
    title: 'I often keep my reactions private at first.',
    subtitle:
        'Introversion can look like holding reactions inside until they feel fully formed.',
  ),
  _MbtiQuestion(
    dimension: 'E/I',
    title: 'I enjoy meeting new people more than revisiting familiar plans.',
    subtitle:
        'Extraversion often prefers fresh social energy and new connections.',
  ),
  _MbtiQuestion(
    dimension: 'E/I',
    title: 'I prefer deep one-on-one talks over lively group conversations.',
    subtitle:
        'Introversion often favors fewer, deeper interactions over many simultaneous ones.',
  ),
  _MbtiQuestion(
    dimension: 'S/N',
    title: 'I trust concrete facts more than hunches.',
    subtitle:
        'Sensing focuses on what is observable and grounded in present reality.',
  ),
  _MbtiQuestion(
    dimension: 'S/N',
    title: 'I enjoy imagining future possibilities beyond present reality.',
    subtitle:
        'Intuition looks for patterns, meanings, and what could happen next.',
  ),
  _MbtiQuestion(
    dimension: 'S/N',
    title: 'I focus on what is practical right now.',
    subtitle: 'Sensing tends to favor immediate facts and concrete next steps.',
  ),
  _MbtiQuestion(
    dimension: 'S/N',
    title: 'I often notice hidden patterns and meanings.',
    subtitle:
        'Intuition often connects details into something bigger than the obvious facts.',
  ),
  _MbtiQuestion(
    dimension: 'S/N',
    title: 'I prefer clear instructions over open-ended exploration.',
    subtitle:
        'Sensing usually feels better when expectations are defined and specific.',
  ),
  _MbtiQuestion(
    dimension: 'S/N',
    title: 'I am drawn to ideas that challenge conventional thinking.',
    subtitle:
        'Intuition often enjoys novelty, abstraction, and unconventional possibilities.',
  ),
  _MbtiQuestion(
    dimension: 'S/N',
    title: 'I remember details of past experiences easily.',
    subtitle: 'Sensing tends to retain concrete details and lived examples.',
  ),
  _MbtiQuestion(
    dimension: 'S/N',
    title: 'I naturally connect separate ideas into a bigger picture.',
    subtitle:
        'Intuition is often about joining pieces into a broader meaning or pattern.',
  ),
  _MbtiQuestion(
    dimension: 'T/F',
    title: 'I make decisions by weighing objective logic first.',
    subtitle:
        'Thinking prioritizes consistency, analysis, and objective criteria.',
  ),
  _MbtiQuestion(
    dimension: 'T/F',
    title: 'I consider personal values before making final decisions.',
    subtitle:
        'Feeling often weighs people impact, empathy, and personal values strongly.',
  ),
  _MbtiQuestion(
    dimension: 'T/F',
    title: 'I can separate criticism of ideas from criticism of people.',
    subtitle:
        'Thinking tends to keep the discussion on the idea, not the person.',
  ),
  _MbtiQuestion(
    dimension: 'T/F',
    title: 'I avoid choices that may hurt relationships unnecessarily.',
    subtitle:
        'Feeling often tries to preserve connection and mutual care when deciding.',
  ),
  _MbtiQuestion(
    dimension: 'T/F',
    title: 'I prefer clear criteria over emotional impressions.',
    subtitle:
        'Thinking usually feels best when decisions can be explained logically.',
  ),
  _MbtiQuestion(
    dimension: 'T/F',
    title: 'I value empathy as much as accuracy in tough conversations.',
    subtitle: 'Feeling balances facts with the human impact of the message.',
  ),
  _MbtiQuestion(
    dimension: 'T/F',
    title: 'I prioritize fairness through consistent rules.',
    subtitle:
        'Thinking often leans on principles that stay consistent across situations.',
  ),
  _MbtiQuestion(
    dimension: 'J/P',
    title: 'I prefer planning ahead instead of improvising at the last minute.',
    subtitle:
        'Judging tends to like structure, preparation, and clear outcomes.',
  ),
  _MbtiQuestion(
    dimension: 'J/P',
    title: 'I like keeping options open until the final moment.',
    subtitle:
        'Perceiving often feels better when there is room to adapt later.',
  ),
  _MbtiQuestion(
    dimension: 'J/P',
    title: 'I feel better once decisions are settled.',
    subtitle:
        'Judging usually prefers closure instead of unresolved possibilities.',
  ),
  _MbtiQuestion(
    dimension: 'J/P',
    title: 'I enjoy adapting as new information appears.',
    subtitle: 'Perceiving often stays flexible as circumstances change.',
  ),
  _MbtiQuestion(
    dimension: 'J/P',
    title: 'I usually create structure before starting a task.',
    subtitle: 'Judging often likes a plan before action begins.',
  ),
  _MbtiQuestion(
    dimension: 'J/P',
    title: 'I work best in flexible environments with minimal constraints.',
    subtitle: 'Perceiving often prefers a looser, more adaptable pace.',
  ),
  _MbtiQuestion(
    dimension: 'J/P',
    title: 'I keep to-do lists and schedules consistently.',
    subtitle: 'Judging often uses routines and lists to stay organized.',
  ),
];
