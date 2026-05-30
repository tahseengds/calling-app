import 'package:flutter/material.dart';

import 'legal_document_screen.dart';

/// In-app Terms of Service. Rendered directly in the app — no external
/// browser redirect.
class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  static const String _supportEmail = 'support@lumio.app';

  @override
  Widget build(BuildContext context) {
    return LegalDocumentScreen(
      title: 'Terms of Service',
      effectiveDate: 'May 30, 2026',
      intro:
          'These Terms of Service ("Terms") govern your use of Lumio, a private '
          'messaging and calling app. By creating an account or using Lumio, '
          'you agree to these Terms. Please read them carefully.',
      blocks: const [
        LegalBlock.heading('Eligibility'),
        LegalBlock.paragraph(
          'You must be at least 13 years old, or the minimum age required in '
          'your country to use a service like Lumio, to create an account. By '
          'using Lumio you confirm that you meet this requirement and that the '
          'information you provide is accurate.',
        ),
        LegalBlock.heading('Your Account'),
        LegalBlock.paragraph(
          'You are responsible for the activity on your account and for keeping '
          'your sign-in credentials secure. Notify us promptly if you believe '
          'your account has been compromised. You may not impersonate others or '
          'use the account of another person without permission.',
        ),
        LegalBlock.heading('Acceptable Use'),
        LegalBlock.paragraph(
          'Lumio is for personal, lawful communication. You agree not to use '
          'the service to:',
        ),
        LegalBlock.bullets([
          'Send spam, or harass, threaten, or abuse other people.',
          'Share content that is illegal, infringing, or that you do not have '
              'the right to share.',
          'Distribute malware, attempt to gain unauthorized access, or '
              'interfere with the operation of the service.',
          'Collect or harvest information about other users without their '
              'consent.',
          'Use the service to violate any applicable law or regulation.',
        ]),
        LegalBlock.paragraph(
          'We may suspend or terminate accounts that violate these rules.',
        ),
        LegalBlock.heading('Your Content'),
        LegalBlock.paragraph(
          'You retain ownership of the messages, photos, videos, and other '
          'content you send through Lumio. You grant us the limited permission '
          'needed to transmit, store, and deliver that content to your intended '
          'recipients and to sync it across your devices. You are responsible '
          'for the content you share and for ensuring you have the right to '
          'share it.',
        ),
        LegalBlock.heading('Calls and Messaging'),
        LegalBlock.paragraph(
          'Lumio provides voice and video calling and real-time messaging. The '
          'quality and availability of these features depend on your network '
          'connection and device, and may vary. We do not guarantee that every '
          'message or call will be delivered without delay or interruption.',
        ),
        LegalBlock.heading('Privacy'),
        LegalBlock.paragraph(
          'Your use of Lumio is also governed by our Privacy Policy, which '
          'explains how we collect and use your information. By using Lumio you '
          'acknowledge that you have read the Privacy Policy.',
        ),
        LegalBlock.heading('Service Changes and Availability'),
        LegalBlock.paragraph(
          'We are continually improving Lumio and may add, change, or remove '
          'features over time. We may also need to perform maintenance or '
          'suspend the service temporarily. We are not liable for any '
          'unavailability of the service or loss of data resulting from such '
          'changes, to the extent permitted by law.',
        ),
        LegalBlock.heading('Termination'),
        LegalBlock.paragraph(
          'You may stop using Lumio and delete your account at any time. We may '
          'suspend or terminate your access if you violate these Terms or if '
          'required to protect the service or other users. Provisions that by '
          'their nature should survive termination will continue to apply.',
        ),
        LegalBlock.heading('Disclaimers'),
        LegalBlock.paragraph(
          'Lumio is provided "as is" and "as available" without warranties of '
          'any kind, whether express or implied, to the fullest extent '
          'permitted by law. We do not warrant that the service will be '
          'uninterrupted, error-free, or secure.',
        ),
        LegalBlock.heading('Limitation of Liability'),
        LegalBlock.paragraph(
          'To the maximum extent permitted by law, Lumio and its providers will '
          'not be liable for any indirect, incidental, special, consequential, '
          'or punitive damages, or any loss of data, arising out of or related '
          'to your use of the service.',
        ),
        LegalBlock.heading('Changes to These Terms'),
        LegalBlock.paragraph(
          'We may update these Terms from time to time. When we make material '
          'changes, we will update the effective date above and, where '
          'appropriate, notify you in the app. Your continued use of Lumio '
          'after changes take effect means you accept the updated Terms.',
        ),
        LegalBlock.heading('Contact Us'),
        LegalBlock.paragraph(
          'If you have questions about these Terms, contact us at $_supportEmail.',
        ),
      ],
    );
  }
}
