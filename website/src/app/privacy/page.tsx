import type { Metadata } from 'next';
import { LegalLayout, LegalSection } from '@/components/LegalLayout';
import { site } from '@/lib/site';

export const metadata: Metadata = {
  title: 'Privacy',
  description: `How ${site.name} handles your data.`,
};

export default function PrivacyPage() {
  return (
    <LegalLayout
      title="Privacy Policy"
      updated="May 2026"
      intro={`${site.name} is built so the people in your conversations are the only ones who can read them. This policy explains what we collect, why, and the choices you have.`}
    >
      <LegalSection heading="What we collect">
        <p>
          To run the service we process account basics (a phone number or email and a display
          name), device and connection metadata needed to route calls, and diagnostic logs that
          help us keep the service reliable.
        </p>
        <p>
          The content of your messages and calls is end-to-end encrypted. We cannot read it, and
          we do not store it in a form we could read.
        </p>
      </LegalSection>

      <LegalSection heading="What we never do">
        <p>
          We do not sell your data, and we do not run ad tracking. We do not build advertising
          profiles, and we do not share your contacts with third parties for marketing.
        </p>
      </LegalSection>

      <LegalSection heading="How we use what we collect">
        <p>
          Operational data is used to set up calls, deliver messages, prevent abuse, and improve
          reliability. Where the law requires a legal basis, ours is performing the contract you
          accept when you use the app.
        </p>
      </LegalSection>

      <LegalSection heading="Your choices">
        <p>
          You can review and delete your account at any time from the app. Deleting your account
          removes your profile and associated metadata from active systems, subject to limited
          retention required by law.
        </p>
      </LegalSection>

      <LegalSection heading="Contact">
        <p>
          Questions about privacy can go to privacy@lumio.app. Replace this address with your own
          before launch.
        </p>
      </LegalSection>
    </LegalLayout>
  );
}
