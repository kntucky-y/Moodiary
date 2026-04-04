import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/auth_service.dart';
import '../../utils/transitions.dart';
import '../home/home_screen.dart';

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
            '- 60 Likert-scale items across E/I, S/N, T/F, J/P dimensions.\n'
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
        page: HomeScreen(
          userName: widget.userName,
          companionId: companionId,
          companionName: companionName,
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
          page: HomeScreen(
            userName: widget.userName,
            companionId: widget.initialCompanionId!,
            companionName: widget.initialCompanionName!,
          ),
        ),
        (_) => false,
      );
      return;
    }
    Navigator.of(context).pop(true);
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
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Let\'s find your perfect companion',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(
              'Answer a real 60-question personality assessment. We\'ll match you with companions that fit your MBTI result.',
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
              'Meet all companions',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            GridView.builder(
              itemCount: 12,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemBuilder: (context, i) => Container(
                decoration: BoxDecoration(
                  color: previewColors[i % previewColors.length],
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Image.asset(
                    'assets/doodle${i + 1}.png',
                    width: 52,
                    height: 52,
                    fit: BoxFit.contain,
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
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 12),
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

    return Scaffold(
      appBar: AppBar(title: const Text('MBTI Questions')),
      body: Padding(
        padding: const EdgeInsets.all(16),
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
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                question,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 14),
            ...List.generate(5, (i) {
              final value = i + 1;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: RadioListTile<int>(
                  value: value,
                  groupValue: _answers[_index],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _answers[_index] = v);
                  },
                  title: Text(_scaleLabels[i]),
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
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Finding the companion who understands you...'),
          ],
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

    int _companionIdOf(Map<String, dynamic> companion) {
      final raw = companion['id'];
      if (raw is num) return raw.toInt();
      return int.tryParse(raw?.toString() ?? '') ?? 0;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('You\'re Matched')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
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
          ...suggested.map(
            (companion) {
              final companionId = _companionIdOf(companion);
              final isSelected = _selectedCompanion?['id'] == companion['id'];
              return Card(
                color: isSelected ? cs.primaryContainer : null,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isSelected ? cs.primary : Colors.transparent,
                    width: 1.2,
                  ),
                ),
                child: ListTile(
                  selected: isSelected,
                  leading: CircleAvatar(
                    backgroundColor: Colors.white,
                    child: Image.asset(
                      'assets/doodle$companionId.png',
                      width: 30,
                      height: 30,
                      fit: BoxFit.contain,
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
                  title: Text((companion['name'] ?? 'Companion').toString()),
                  subtitle: Text((companion['description'] ?? '').toString()),
                  onTap: () => setState(() => _selectedCompanion = companion),
                ),
              );
            },
              ),
          ),
          const SizedBox(height: 8),
          if (_selectedCompanion != null)
            Card(
              color: cs.primaryContainer,
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
                            'assets/doodle${_companionIdOf(_selectedCompanion!)}.png',
                            width: 20,
                            height: 20,
                            fit: BoxFit.contain,
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
                            style: Theme.of(
                              context,
                            ).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
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
          if (widget.requireCompanionSelection && _selectedCompanion != null)
            ElevatedButton(
              onPressed: () => _chooseCompanion(_selectedCompanion!),
              child: const Text('Get Started'),
            )
          else
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

const List<String> _questions = [
  'I feel energized after spending time with many people.',
  'I prefer to process my thoughts alone before speaking.',
  'I usually start conversations in group settings.',
  'Quiet time is essential for me after social events.',
  'I think better by talking ideas out loud.',
  'I often keep my reactions private at first.',
  'I enjoy meeting new people more than revisiting familiar plans.',
  'I prefer deep one-on-one talks over lively group conversations.',
  'I tend to act first and reflect later.',
  'I usually observe first before joining in.',
  'I feel motivated when the room is active and interactive.',
  'I recharge best in calm, low-stimulation environments.',
  'I enjoy sharing updates as things happen.',
  'I prefer to share once I have fully formed my thoughts.',
  'I usually feel comfortable being the center of attention.',
  'I trust concrete facts more than hunches.',
  'I enjoy imagining future possibilities beyond present reality.',
  'I focus on what is practical right now.',
  'I often notice hidden patterns and meanings.',
  'I prefer clear instructions over open-ended exploration.',
  'I am drawn to ideas that challenge conventional thinking.',
  'I remember details of past experiences easily.',
  'I naturally connect separate ideas into a bigger picture.',
  'I trust experience more than theory.',
  'I enjoy discussing what could be, even if it is uncertain.',
  'I prefer examples with real-world evidence.',
  'I rely on intuition when data is incomplete.',
  'I value consistency and proven methods.',
  'I quickly spot opportunities for innovation.',
  'I feel more comfortable with specifics than abstractions.',
  'I make decisions by weighing objective logic first.',
  'I consider personal values before making final decisions.',
  'I can separate criticism of ideas from criticism of people.',
  'I avoid choices that may hurt relationships unnecessarily.',
  'I prefer clear criteria over emotional impressions.',
  'I value empathy as much as accuracy in tough conversations.',
  'I prioritize fairness through consistent rules.',
  'I adapt decisions based on individual circumstances.',
  'I am comfortable giving direct critical feedback.',
  'I naturally notice emotional undercurrents in group decisions.',
  'I trust rational debate to find the best answer.',
  'I ask how decisions will affect people before finalizing them.',
  'I value competence over harmony when priorities conflict.',
  'I care deeply about preserving mutual respect during conflict.',
  'I usually evaluate options with a pros-and-cons lens.',
  'I prefer planning ahead instead of improvising at the last minute.',
  'I like keeping options open until the final moment.',
  'I feel better once decisions are settled.',
  'I enjoy adapting as new information appears.',
  'I usually create structure before starting a task.',
  'I work best in flexible environments with minimal constraints.',
  'I keep to-do lists and schedules consistently.',
  'I dislike committing too early when plans may change.',
  'I prefer clear closure over open-ended timelines.',
  'I am comfortable with uncertainty while exploring choices.',
  'I usually complete tasks before relaxing.',
  'I often start tasks close to deadlines and still perform well.',
  'I get stressed when plans are vague for too long.',
  'I prefer spontaneity over strict routines on most days.',
  'I feel most productive with a defined process.',
];
