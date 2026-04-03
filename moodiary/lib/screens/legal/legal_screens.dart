import 'package:flutter/material.dart';

class LegalScreens {
  static Widget privacyPolicy() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Privacy Policy',
            style: Theme.of(_context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          _buildSection(
            'Introduction',
            'Moodiary ("we" or "us" or "our") operates the Moodiary mobile application (the "Service"). This page informs you of our policies regarding the collection, use, and disclosure of personal data when you use our Service and the choices you have associated with that data.',
          ),
          _buildSection(
            'Information Collection and Use',
            'We collect several different types of information for various purposes to provide and improve our Service to you.',
          ),
          _buildSection(
            'Types of Data Collected:',
            '• Account Information: Name, email address, password\n'
                '• Profile Data: Bio, avatar image, location\n'
                '• Mood & Journal Data: Mood entries, journal posts, activity logs\n'
                '• Device Information: Device type, OS version, unique device identifiers\n'
                '• Usage Data: Pages visited, time spent, features used\n'
                '• Push Notification Tokens: For delivering notifications',
          ),
          _buildSection(
            'Use of Data',
            'Moodiary uses the collected data for various purposes:\n'
                '• To provide and maintain our Service\n'
                '• To notify you about changes to our Service\n'
                '• To allow you to participate in interactive features\n'
                '• To provide customer support\n'
                '• To gather analysis or valuable information for improving the Service\n'
                '• To monitor the usage of our Service',
          ),
          _buildSection(
            'Security of Data',
            'The security of your data is important to us but remember that no method of transmission over the Internet or method of electronic storage is 100% secure. While we strive to use commercially acceptable means to protect your Personal Data, we cannot guarantee its absolute security.',
          ),
          _buildSection(
            'Contact Us',
            'If you have any questions about this Privacy Policy, please contact us at: support@moodiary.app',
          ),
        ],
      ),
    );
  }

  static Widget termsOfService() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Terms of Service',
            style: Theme.of(_context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          _buildSection(
            'Introduction',
            'Welcome to Moodiary. These Terms of Service ("Terms") are a binding agreement between you and Moodiary regarding your use of our mobile application and services.',
          ),
          _buildSection(
            'Acceptance of Terms',
            'By accessing and using Moodiary, you accept and agree to be bound by the terms and provision of this agreement. If you do not agree to abide by the above, please do not use this service.',
          ),
          _buildSection(
            'Use License',
            'Permission is granted to temporarily download one copy of the materials (information or software) on Moodiary\'s mobile application for personal, non-commercial transitory viewing only.',
          ),
          _buildSection(
            'User Responsibilities',
            'You are responsible for:\n'
                '• Maintaining the confidentiality of your account information\n'
                '• All activities that occur under your account\n'
                '• Compliance with all laws and regulations\n'
                '• Not posting harmful, abusive, or illegal content\n'
                '• Respecting other users\' privacy and rights',
          ),
          _buildSection(
            'Content Guidelines',
            'You may not post content that:\n'
                '• Is hateful, harassing, or discriminatory\n'
                '• Violates intellectual property rights\n'
                '• Is explicit or inappropriate\n'
                '• Promotes illegal activities\n'
                '• Contains malware or harmful code',
          ),
          _buildSection(
            'Disclaimers',
            'The materials on Moodiary\'s application are provided on an\'as is\' basis. Moodiary makes no warranties, expressed or implied, and hereby disclaims and negates all other warranties including, without limitation, implied warranties or conditions of merchantability, fitness for a particular purpose, or non-infringement of intellectual property or other violation of rights.',
          ),
          _buildSection(
            'Limitations',
            'In no event shall Moodiary or its suppliers be liable for any damages (including, without limitation, damages for loss of data or profit, or due to business interruption) arising out of the use or inability to use the materials on Moodiary\'s application.',
          ),
          _buildSection(
            'Modifications',
            'Moodiary may revise these Terms of Service at any time without notice. By using this application, you are agreeing to be bound by the then current version of these Terms of Service.',
          ),
          _buildSection(
            'Contact Us',
            'If you have any questions about these Terms of Service, please contact us at: support@moodiary.app',
          ),
        ],
      ),
    );
  }

  static Widget _buildSection(String title, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            _context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(content, style: Theme.of(_context).textTheme.bodyMedium),
        const SizedBox(height: 16),
      ],
    );
  }

  static late BuildContext _context;
}

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    LegalScreens._context = context;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy Policy'),
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
      body: LegalScreens.privacyPolicy(),
    );
  }
}

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    LegalScreens._context = context;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Terms of Service'),
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
      body: LegalScreens.termsOfService(),
    );
  }
}
