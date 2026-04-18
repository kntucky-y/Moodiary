import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/moodiary_colors.dart';
import '../../utils/transitions.dart';
import '../../widgets/glass.dart';
import '../app_shell.dart';
import '../profile/mbti_test_screen.dart';

const _kPurple = Color(0xFFA076F9);

const _companions = [
  _Companion(
    1,
    'Sparky',
    'An energetic and cheerful friend who finds joy in the smallest things. Sparky helps you celebrate your happy moments.',
  ),
  _Companion(
    2,
    'Gloomy Gus',
    'A thoughtful and empathetic soul who understands that it\'s okay to be sad. Gus is a great listener.',
  ),
  _Companion(
    3,
    'Zen',
    'Calm and centered, Zen helps you find your inner peace and focus on the present moment, even when things feel chaotic.',
  ),
  _Companion(
    4,
    'Rory',
    'A fiery but fiercely loyal protector. Rory helps you acknowledge your anger and channel it constructively.',
  ),
  _Companion(
    5,
    'Anxie',
    'A gentle worrier who is always thinking ahead. Anxie reminds you to be kind to yourself during moments of anxiety.',
  ),
  _Companion(
    6,
    'Joy',
    'Pure, bubbly happiness in doodle form. Joy\'s infectious laughter can brighten even the cloudiest of days.',
  ),
  _Companion(
    7,
    'Dreamer',
    'A sleepy and imaginative companion who encourages you to rest and explore the wonderful world of your dreams.',
  ),
  _Companion(
    8,
    'Witty',
    'Clever and quick with a joke, Witty helps you find the humor and absurdity in everyday situations.',
  ),
  _Companion(
    9,
    'Braveheart',
    'Courageous and supportive, Braveheart stands by your side, giving you the strength to face your fears.',
  ),
  _Companion(
    10,
    'Curio',
    'Endlessly inquisitive, Curio encourages you to ask questions and learn something new about yourself and the world.',
  ),
  _Companion(
    11,
    'Grumbles',
    'A bit grumpy on the outside, but secretly a big softy. Grumbles understands that sometimes you just need to vent.',
  ),
  _Companion(
    12,
    'Shylo',
    'A gentle and reserved companion who appreciates quiet moments and the beauty of introversion.',
  ),
];

const _cardColors = [
  Color(0xFFFBCFE8),
  Color(0xFFBFDBFE),
  Color(0xFFBBF7D0),
  Color(0xFFFEF08A),
  Color(0xFFFECDD3),
];

class _Companion {
  final int id;
  final String name;
  final String description;

  const _Companion(this.id, this.name, this.description);

  String get asset => 'assets/doodle$id.png';
}

class CompanionScreen extends StatelessWidget {
  final String userName;

  const CompanionScreen({super.key, required this.userName});

  Future<void> _continueLater(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final companionId = prefs.getInt('companion_id') ?? _companions.first.id;
    final companion = _companions.firstWhere(
      (entry) => entry.id == companionId,
      orElse: () => _companions.first,
    );

    await prefs.setInt('companion_id', companion.id);
    await prefs.setString('companion_name', companion.name);

    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      FadeSlideRoute(
        page: MoodiaryShell(
          userName: userName,
          companionId: companion.id,
          companionName: companion.name,
          initialTab: MoodiaryTab.home,
        ),
      ),
      (_) => false,
    );
  }

  void _showDetail(BuildContext context, _Companion companion, Color color) {
    showDialog(
      context: context,
      builder: (_) => _CompanionModal(
        companion: companion,
        color: color,
        userName: userName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final crossAxisCount = width >= 820 ? 4 : (width >= 520 ? 3 : 2);

    return Scaffold(
      backgroundColor: context.mdScaffold,
      appBar: AppBar(
        backgroundColor: context.mdScaffold,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () async {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              await _continueLater(context);
            }
          },
        ),
        title: const Text('Choose a Companion'),
        actions: [
          TextButton(
            onPressed: () => _continueLater(context),
            child: const Text('Take later'),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 16),
              GlassContainer(
                blurSigma: context.mdGlassBlurSmall,
                borderRadius: BorderRadius.circular(16),
                backgroundColor: context.mdGlassSurface,
                borderColor: context.mdGlassBorder,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Text(
                  'Select a companion to see its story. You can always change your companion later!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: context.mdSecondaryText,
                    fontStyle: FontStyle.italic,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: GridView.builder(
                  itemCount: _companions.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                  ),
                  itemBuilder: (context, index) {
                    final companion = _companions[index];
                    final color = _cardColors[index % _cardColors.length];
                    return TapScale(
                      onTap: () => _showDetail(context, companion, color),
                      child: GlassContainer(
                        blurSigma: context.mdGlassBlurSmall,
                        borderRadius: BorderRadius.circular(16),
                        backgroundColor: color.withValues(
                          alpha: context.isDarkMode ? 0.28 : 0.42,
                        ),
                        borderColor: context.mdGlassBorder,
                        padding: EdgeInsets.zero,
                        child: Center(
                          child: Image.asset(
                            companion.asset,
                            width: 64,
                            height: 64,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(
                                  Icons.sentiment_satisfied_alt,
                                  size: 48,
                                  color: Color(0xFFCCCCCC),
                                ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompanionModal extends StatelessWidget {
  final _Companion companion;
  final Color color;
  final String userName;

  const _CompanionModal({
    required this.companion,
    required this.color,
    required this.userName,
  });

  Future<void> _choose(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final mbtiLatestType = prefs.getString('mbti_latest_type') ?? '';
    if (mbtiLatestType.isEmpty) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      await Navigator.of(context).push(
        FadeSlideRoute(
          page: MbtiTestScreen(
            userName: userName,
            requireCompanionSelection: true,
          ),
        ),
      );
      return;
    }

    await prefs.setInt('companion_id', companion.id);
    await prefs.setString('companion_name', companion.name);
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        FadeSlideRoute(
          page: MoodiaryShell(
            userName: userName,
            companionId: companion.id,
            companionName: companion.name,
            initialTab: MoodiaryTab.home,
          ),
        ),
        (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: GlassContainer(
        blurSigma: context.mdGlassBlurMedium,
        borderRadius: BorderRadius.circular(24),
        backgroundColor: context.mdGlassSurfaceStrong,
        borderColor: context.mdGlassBorder,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: context.isDarkMode ? 0.78 : 0.9),
              ),
              child: Center(
                child: Image.asset(
                  companion.asset,
                  width: 80,
                  height: 80,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.sentiment_satisfied_alt,
                    size: 60,
                    color: Color(0xFFCCCCCC),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              companion.name,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: context.mdPrimaryText,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              companion.description,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: context.mdSecondaryText,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(50),
                      ),
                      side: BorderSide(color: context.mdInputBorder),
                    ),
                    child: Text(
                      'Close',
                      style: TextStyle(color: context.mdSecondaryText),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _choose(context),
                    style: FilledButton.styleFrom(
                      backgroundColor: _kPurple.withValues(
                        alpha: context.isDarkMode ? 0.58 : 0.64,
                      ),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(50),
                      ),
                    ),
                    child: const Text(
                      'Choose',
                      style: TextStyle(fontWeight: FontWeight.bold),
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
