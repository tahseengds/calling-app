import 'package:flutter/material.dart';

import 'legal_document_screen.dart';

/// In-app Privacy Policy. Content is rendered directly in the app — no
/// external browser redirect. Keep the support address generic
/// (support@lumio.app) so no personal email is baked into the binary.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const String _supportEmail = 'support@lumio.app';

  @override
  Widget build(BuildContext context) {
    return LegalDocumentScreen(
      title: 'Privacy Policy',
      effectiveDate: 'May 30, 2026',
      intro:
          'Lumio ("we", "us", or "our") builds a private messaging and calling '
          'app. This Privacy Policy explains what information we collect, how we '
          'use it, and the choices you have. We designed Lumio to collect as '
          'little as possible and to keep your conversations yours.',
      blocks: const [
        LegalBlock.heading('Information You Provide'),
        LegalBlock.paragraph(
          'When you create an account we collect the information needed to set '
          'it up and let other people reach you:',
        ),
        LegalBlock.bullets([
          'Account details: your name, email address, and (if you sign in with '
              'Google) your Google account identifier.',
          'Profile information: an optional profile photo and any display name '
              'you choose.',
          'Content you send: messages, photos, videos, voice notes, documents, '
              'and reactions you share in a conversation, delivered to the '
              'people you send them to.',
          'Support requests: when you contact us through the in-app Help & '
              'Support form, we receive your message, the category you select, '
              'and any device details you choose to include.',
        ]),
        LegalBlock.heading('Information Collected Automatically'),
        LegalBlock.paragraph(
          'To deliver messages and calls reliably and to keep the service '
          'secure, we automatically process a limited set of technical data:',
        ),
        LegalBlock.bullets([
          'Connection and delivery data: timestamps, delivery and read '
              'receipts, and online/last-seen status, subject to your privacy '
              'settings.',
          'Device and app information: app version, operating system, device '
              'type, and language — used for diagnostics and compatibility.',
          'Push notification token: a token from Firebase Cloud Messaging so we '
              'can notify you of new messages and calls.',
        ]),
        LegalBlock.heading('How We Use Your Information'),
        LegalBlock.paragraph('We use the information above to:'),
        LegalBlock.bullets([
          'Provide core features — sending messages, placing calls, and syncing '
              'your conversations across sessions.',
          'Deliver notifications for new messages and incoming calls.',
          'Maintain security, prevent abuse, and enforce our Terms of Service.',
          'Diagnose problems and improve reliability and performance.',
          'Respond to your support requests.',
        ]),
        LegalBlock.paragraph(
          'We do not sell your personal information, and we do not use the '
          'content of your messages to serve advertising.',
        ),
        LegalBlock.heading('Your Privacy Controls'),
        LegalBlock.paragraph(
          'Lumio gives you direct control over how you appear to others. From '
          'Settings › Privacy you can manage:',
        ),
        LegalBlock.bullets([
          'Who can see your last seen, online status, profile photo, and about '
              'information.',
          'Whether read receipts are shared.',
          'Whether calls from people outside your contacts are silenced.',
          'Your list of blocked contacts, who can no longer message or call '
              'you.',
        ]),
        LegalBlock.paragraph(
          'These settings are stored with your account and applied across your '
          'devices.',
        ),
        LegalBlock.heading('How Your Information Is Shared'),
        LegalBlock.paragraph(
          'The content you send is shared with the recipients you choose. '
          'Beyond that, we share information only in limited circumstances:',
        ),
        LegalBlock.bullets([
          'Service providers: infrastructure partners (such as our hosting and '
              'push-notification providers) that process data on our behalf '
              'under appropriate safeguards.',
          'Legal reasons: when required by law, or to protect the rights, '
              'safety, and security of our users and the service.',
        ]),
        LegalBlock.heading('Data Retention'),
        LegalBlock.paragraph(
          'We keep your account information for as long as your account is '
          'active. Messages are stored to deliver and sync them to your '
          'devices, and disappearing messages are removed automatically once '
          'their timer expires. When you delete your account, we delete or '
          'anonymize associated personal data, except where we are required to '
          'retain it for legal or security reasons.',
        ),
        LegalBlock.heading('Security'),
        LegalBlock.paragraph(
          'We use encryption in transit, access controls, and other technical '
          'and organizational measures to protect your information. No system '
          'is perfectly secure, but we work continuously to safeguard your '
          'data and to limit who can access it.',
        ),
        LegalBlock.heading("Children's Privacy"),
        LegalBlock.paragraph(
          'Lumio is not directed to children under 13 (or the minimum age '
          'required in your country). We do not knowingly collect personal '
          'information from children. If you believe a child has provided us '
          'information, contact us and we will remove it.',
        ),
        LegalBlock.heading('Your Rights'),
        LegalBlock.paragraph(
          'Depending on where you live, you may have the right to access, '
          'correct, export, or delete your personal information, and to object '
          'to or restrict certain processing. You can update your profile and '
          'privacy settings in the app at any time, or contact us to exercise '
          'these rights.',
        ),
        LegalBlock.heading('Changes to This Policy'),
        LegalBlock.paragraph(
          'We may update this Privacy Policy from time to time. When we make '
          'material changes, we will update the effective date above and, where '
          'appropriate, notify you in the app.',
        ),
        LegalBlock.heading('Contact Us'),
        LegalBlock.paragraph(
          'If you have questions about this Privacy Policy or how we handle '
          'your information, contact us at $_supportEmail.',
        ),
      ],
    );
  }
}
