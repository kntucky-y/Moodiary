import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/auth_service.dart';
import '../../utils/transitions.dart';
import '../home/home_screen.dart';

class MbtiTestScreen extends StatefulWidget {
  final String userName;
  final bool requireCompanionSelection;

  const MbtiTestScreen({
    super.key,
    required this.userName,
    this.requireCompanionSelection = false,
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
  bool _submitting = false;
  Map<String, dynamic>? _result;
  String? _error;

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
        _result = result;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final done = _answers.where((a) => a != 0).length;

    if (_result != null) {
      final type = (_result!['type'] ?? 'Unknown').toString();
      final suggested =
          (_result!['suggestedCompanions'] as List<dynamic>? ?? const [])
              .cast<Map<String, dynamic>>();

      return Scaffold(
        appBar: AppBar(title: const Text('MBTI Result')),
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
                    const SizedBox(height: 8),
                    Text(
                      type,
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Companion suggestions based on your result:',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            ...suggested.map((c) {
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text((c['id'] ?? '?').toString()),
                  ),
                  title: Text((c['name'] ?? 'Companion').toString()),
                  subtitle: Text((c['description'] ?? '').toString()),
                  trailing: widget.requireCompanionSelection
                      ? ElevatedButton(
                          onPressed: () => _chooseCompanion(c),
                          child: const Text('Choose'),
                        )
                      : null,
                ),
              );
            }),
            const SizedBox(height: 12),
            if (!widget.requireCompanionSelection)
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Done'),
              ),
          ],
        ),
      );
    }

    final question = _questions[_index];

    return Scaffold(
      appBar: AppBar(title: const Text('MBTI Assessment')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(value: done / _questions.length),
            const SizedBox(height: 8),
            Text('Question ${_index + 1} of ${_questions.length}'),
            const SizedBox(height: 14),
            Text(
              question,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
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
