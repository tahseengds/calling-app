import type { Metadata } from 'next';
import { LegalLayout, LegalSection } from '@/components/LegalLayout';
import { site } from '@/lib/site';

export const metadata: Metadata = {
  title: 'Terms',
  description: `The terms for using ${site.name}.`,
};

export default function TermsPage() {
  return (
    <LegalLayout
      title="Terms of Service"
      updated="May 2026"
      intro={`These terms cover your use of ${site.name}. By creating an account you agree to them.`}
    >
      <LegalSection heading="Using the service">
        <p>
          You must be old enough to form a binding contract in your country to use {site.name}.
          You are responsible for the activity on your account and for keeping your device secure.
        </p>
      </LegalSection>

      <LegalSection heading="Acceptable use">
        <p>
          Do not use {site.name} to harass others, distribute malware, infringe intellectual
          property, or break the law. We may suspend accounts that put other people or the service
          at risk.
        </p>
      </LegalSection>

      <LegalSection heading="Your content">
        <p>
          You keep ownership of everything you send. Because messages and calls are end-to-end
          encrypted, you alone control who can read them. You are responsible for the content you
          share.
        </p>
      </LegalSection>

      <LegalSection heading="Service changes and availability">
        <p>
          We work to keep the service running, but we provide it as is and cannot promise it will
          be uninterrupted. We may add, change, or remove features over time.
        </p>
      </LegalSection>

      <LegalSection heading="Contact">
        <p>
          Questions about these terms can go to legal@lumio.app. Replace this address with your
          own before launch.
        </p>
      </LegalSection>
    </LegalLayout>
  );
}
