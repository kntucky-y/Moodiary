import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../home/home_screen.dart';
import '../../utils/transitions.dart';

const _kPurple = Color(0xFFA076F9);
const _kDark = Color(0xFF3D3B40);
const _kBg = Color(0xFFFFFBF5);

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
  Color(0xFFFBCFE8), // pink
  Color(0xFFBFDBFE), // blue
  Color(0xFFBBF7D0), // green
  Color(0xFFFEF08A), // yellow
  Color(0xFFFECDD3), // rose
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
    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 32),
              const Text(
                'Choose a Companion',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: _kDark,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Select a companion to see its story. You can always change your companion later!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: Color(0xFF888888),
                  fontStyle: FontStyle.italic,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: GridView.builder(
                  itemCount: _companions.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                  ),
                  itemBuilder: (context, index) {
                    final companion = _companions[index];
                    final color = _cardColors[index % _cardColors.length];
                    return TapScale(
                      onTap: () => _showDetail(context, companion, color),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
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
    await prefs.setInt('companion_id', companion.id);
    await prefs.setString('companion_name', companion.name);
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        FadeSlideRoute(
          page: HomeScreen(
            userName: userName,
            companionId: companion.id,
            companionName: companion.name,
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
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
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
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: _kDark,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              companion.description,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF666666),
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
                      side: const BorderSide(color: Color(0xFFDDDDDD)),
                    ),
                    child: const Text(
                      'Close',
                      style: TextStyle(color: Color(0xFF666666)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _choose(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kPurple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
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
