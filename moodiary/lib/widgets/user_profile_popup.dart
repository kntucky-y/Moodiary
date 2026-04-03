import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../utils/avatar_utils.dart';

Future<void> showUserProfilePopup(
  BuildContext context, {
  required String userId,
}) async {
  await showDialog<void>(
    context: context,
    builder: (context) => _UserProfilePopup(userId: userId),
  );
}

class _UserProfilePopup extends StatelessWidget {
  final String userId;

  const _UserProfilePopup({required this.userId});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      contentPadding: const EdgeInsets.all(16),
      content: SizedBox(
        width: 320,
        child: FutureBuilder<Map<String, dynamic>>(
          future: AuthService.instance.getUserProfile(userId: userId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 180,
                child: Center(child: CircularProgressIndicator()),
              );
            }

            if (snapshot.hasError) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 42),
                  const SizedBox(height: 10),
                  Text(
                    'Unable to load profile',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              );
            }

            final user =
                snapshot.data?['user'] as Map<String, dynamic>? ?? const {};
            final name = (user['name'] as String?) ?? 'User';
            final email = (user['email'] as String?) ?? '';
            final bio = (user['bio'] as String?) ?? '';
            final avatarUrl = (user['avatarUrl'] as String?);

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundImage: avatarImageProvider(avatarUrl),
                  child: avatarImageProvider(avatarUrl) == null
                      ? const Icon(Icons.person, size: 30)
                      : null,
                ),
                const SizedBox(height: 12),
                Text(
                  name,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                ),
                if (email.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    email,
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 10),
                if (bio.isNotEmpty)
                  Text(
                    bio,
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  )
                else
                  Text(
                    'No bio yet',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
