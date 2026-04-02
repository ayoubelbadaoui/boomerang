enum LegalDocumentType { privacyPolicy, termsOfService, communityGuidelines }

class LegalDocument {
  const LegalDocument({
    required this.type,
    required this.title,
    required this.lastUpdated,
    required this.version,
    required this.sections,
  });

  final LegalDocumentType type;
  final String title;
  final String lastUpdated;
  final String version;
  final List<LegalSection> sections;
}

class LegalSection {
  const LegalSection({required this.heading, required this.body});
  final String heading;
  final String body;
}

const kPrivacyPolicyVersion = '1.0';
const kTermsVersion = '1.0';

final privacyPolicy = LegalDocument(
  type: LegalDocumentType.privacyPolicy,
  title: 'Privacy Policy',
  lastUpdated: 'March 30, 2026',
  version: kPrivacyPolicyVersion,
  sections: const [
    LegalSection(
      heading: 'Introduction',
      body:
          'Welcome to Boomerang ("we," "our," or "us"). We are committed to '
          'protecting your privacy and ensuring the safety of your personal '
          'information. This Privacy Policy explains how we collect, use, '
          'disclose, and safeguard your data when you use the Boomerang mobile '
          'application (the "App").\n\n'
          'By using the App, you agree to the collection and use of information '
          'in accordance with this policy. If you do not agree, please do not '
          'use the App.',
    ),
    LegalSection(
      heading: '1. Information We Collect',
      body:
          'Account Information: When you create an account, we collect your '
          'name, email address, phone number, date of birth, gender, and '
          'optional profile photo.\n\n'
          'Content You Create: Photos, videos (boomerangs), captions, comments, '
          'and messages you share through the App.\n\n'
          'Usage Data: We automatically collect information about how you '
          'interact with the App, including pages viewed, features used, and '
          'the time and duration of your activities.\n\n'
          'Device Information: Device type, operating system, unique device '
          'identifiers, and mobile network information.\n\n'
          'Location Data: We may collect approximate location information based '
          'on your device settings.',
    ),
    LegalSection(
      heading: '2. How We Use Your Information',
      body:
          'We use the information we collect to:\n\n'
          '• Provide, maintain, and improve the App\n'
          '• Create and manage your account\n'
          '• Enable social features (following, messaging, sharing)\n'
          '• Send push notifications (with your consent)\n'
          '• Enforce our Terms of Service and Community Guidelines\n'
          '• Detect and prevent fraud, abuse, and security incidents\n'
          '• Comply with legal obligations\n'
          '• Respond to your support requests',
    ),
    LegalSection(
      heading: '3. How We Share Your Information',
      body:
          'We do not sell your personal information. We may share your data '
          'with:\n\n'
          '• Service Providers: Third-party services that help us operate the '
          'App (e.g., Firebase for authentication and storage, cloud hosting).\n'
          '• Legal Requirements: When required by law, legal process, or '
          'government request.\n'
          '• Safety: To protect the rights, property, or safety of our users '
          'or the public.\n'
          '• With Your Consent: When you explicitly agree to sharing.',
    ),
    LegalSection(
      heading: '4. Data Retention',
      body:
          'We retain your personal data for as long as your account is active '
          'or as needed to provide you services. If you delete your account, we '
          'will delete or anonymize your personal data within 30 days, except '
          'where we are required to retain it for legal, regulatory, or '
          'legitimate business purposes.',
    ),
    LegalSection(
      heading: '5. Your Rights (GDPR)',
      body:
          'If you are located in the European Economic Area (EEA), you have '
          'the following rights under the General Data Protection Regulation:\n\n'
          '• Right of Access: Request a copy of your personal data.\n'
          '• Right to Rectification: Request correction of inaccurate data.\n'
          '• Right to Erasure: Request deletion of your personal data.\n'
          '• Right to Restrict Processing: Request that we limit how we use '
          'your data.\n'
          '• Right to Data Portability: Request your data in a portable format.\n'
          '• Right to Object: Object to our processing of your data.\n'
          '• Right to Withdraw Consent: Withdraw consent at any time.\n\n'
          'To exercise these rights, go to Settings > Manage Account > '
          'Privacy & Data, or contact us at privacy@boomerangapp.com.',
    ),
    LegalSection(
      heading: '6. Children\'s Privacy (COPPA)',
      body:
          'The App is not intended for children under the age of 13. We do '
          'not knowingly collect personal information from children under 13. '
          'If you are a parent or guardian and believe your child has provided '
          'us with personal information, please contact us immediately at '
          'privacy@boomerangapp.com, and we will take steps to delete such '
          'information.\n\n'
          'Users between 13 and 17 must have parental or guardian consent '
          'to use the App. We encourage parents to monitor their children\'s '
          'online activity.',
    ),
    LegalSection(
      heading: '7. Data Security',
      body:
          'We implement industry-standard security measures to protect your '
          'data, including encryption in transit (TLS/SSL), secure cloud '
          'infrastructure, and access controls. However, no method of '
          'transmission over the Internet is 100% secure.',
    ),
    LegalSection(
      heading: '8. International Data Transfers',
      body:
          'Your data may be transferred to and processed in countries other '
          'than your own. We ensure appropriate safeguards are in place for '
          'international transfers, including Standard Contractual Clauses '
          'approved by the European Commission where applicable.',
    ),
    LegalSection(
      heading: '9. Changes to This Policy',
      body:
          'We may update this Privacy Policy from time to time. We will '
          'notify you of any material changes by posting the new policy in '
          'the App and updating the "Last Updated" date. Your continued use '
          'of the App after changes constitutes acceptance of the updated '
          'policy.',
    ),
    LegalSection(
      heading: '10. Contact Us',
      body:
          'If you have questions about this Privacy Policy or wish to exercise '
          'your data rights, contact us at:\n\n'
          'Email: privacy@boomerangapp.com\n'
          'Subject: Privacy Inquiry',
    ),
  ],
);

final termsOfService = LegalDocument(
  type: LegalDocumentType.termsOfService,
  title: 'Terms of Service',
  lastUpdated: 'March 30, 2026',
  version: kTermsVersion,
  sections: const [
    LegalSection(
      heading: 'Introduction',
      body:
          'These Terms of Service ("Terms") govern your access to and use of '
          'the Boomerang mobile application ("App"). By creating an account or '
          'using the App, you agree to be bound by these Terms.\n\n'
          'If you do not agree to these Terms, do not use the App.',
    ),
    LegalSection(
      heading: '1. Eligibility',
      body:
          'You must be at least 13 years of age to use the App. If you are '
          'between 13 and 17, you must have the consent of a parent or legal '
          'guardian. By using the App, you represent that you meet these '
          'requirements.\n\n'
          'We reserve the right to terminate accounts of users who '
          'misrepresent their age.',
    ),
    LegalSection(
      heading: '2. Your Account',
      body:
          'You are responsible for maintaining the confidentiality of your '
          'account credentials and for all activities that occur under your '
          'account. You agree to:\n\n'
          '• Provide accurate and truthful registration information\n'
          '• Not share your account credentials with others\n'
          '• Notify us immediately of any unauthorized use\n'
          '• Not create more than one personal account',
    ),
    LegalSection(
      heading: '3. User Content',
      body:
          'You retain ownership of the content you create and share through '
          'the App ("User Content"). By posting User Content, you grant '
          'Boomerang a non-exclusive, worldwide, royalty-free license to use, '
          'display, reproduce, and distribute your content within the App.\n\n'
          'You are solely responsible for your User Content and represent that '
          'you have all necessary rights to share it.',
    ),
    LegalSection(
      heading: '4. Prohibited Conduct',
      body:
          'You agree not to:\n\n'
          '• Post content that is illegal, harmful, threatening, abusive, '
          'harassing, defamatory, vulgar, obscene, or otherwise objectionable\n'
          '• Share sexually explicit content involving minors\n'
          '• Impersonate any person or entity\n'
          '• Bully, harass, or intimidate other users\n'
          '• Engage in spam or unsolicited advertising\n'
          '• Attempt to hack, disrupt, or interfere with the App\n'
          '• Collect personal information of other users without consent\n'
          '• Violate any applicable law or regulation\n'
          '• Circumvent any content moderation or safety measures',
    ),
    LegalSection(
      heading: '5. Content Moderation',
      body:
          'We reserve the right to review, remove, or restrict any User '
          'Content that violates these Terms or our Community Guidelines, '
          'at our sole discretion and without prior notice.\n\n'
          'Users can report content or other users that violate our policies. '
          'We will review all reports and take appropriate action.',
    ),
    LegalSection(
      heading: '6. Account Termination',
      body:
          'We may suspend or terminate your account at any time if you violate '
          'these Terms, our Community Guidelines, or applicable law. You may '
          'delete your account at any time through Settings > Manage Account > '
          'Delete Account.\n\n'
          'Upon termination, your right to use the App ceases immediately. '
          'We may retain certain data as required by law.',
    ),
    LegalSection(
      heading: '7. Intellectual Property',
      body:
          'The App and its original content (excluding User Content), features, '
          'and functionality are owned by Boomerang and are protected by '
          'international copyright, trademark, and other intellectual property '
          'laws.',
    ),
    LegalSection(
      heading: '8. Disclaimer of Warranties',
      body:
          'The App is provided "as is" and "as available" without any '
          'warranties of any kind, whether express or implied. We do not '
          'warrant that the App will be uninterrupted, error-free, or secure.',
    ),
    LegalSection(
      heading: '9. Limitation of Liability',
      body:
          'To the fullest extent permitted by law, Boomerang shall not be '
          'liable for any indirect, incidental, special, consequential, or '
          'punitive damages arising from your use of the App.',
    ),
    LegalSection(
      heading: '10. Changes to Terms',
      body:
          'We reserve the right to modify these Terms at any time. We will '
          'notify you of material changes through the App. Your continued use '
          'of the App after changes take effect constitutes acceptance of the '
          'revised Terms.',
    ),
    LegalSection(
      heading: '11. Contact Us',
      body:
          'If you have questions about these Terms, contact us at:\n\n'
          'Email: legal@boomerangapp.com\n'
          'Subject: Terms of Service Inquiry',
    ),
  ],
);

final communityGuidelines = LegalDocument(
  type: LegalDocumentType.communityGuidelines,
  title: 'Community Guidelines',
  lastUpdated: 'March 30, 2026',
  version: '1.0',
  sections: const [
    LegalSection(
      heading: 'Our Mission',
      body:
          'Boomerang is built to be a safe, creative, and inclusive community. '
          'These guidelines help ensure everyone has a positive experience. '
          'Violations may result in content removal, account suspension, or '
          'permanent ban.',
    ),
    LegalSection(
      heading: '1. Be Respectful',
      body:
          '• Treat all users with dignity and respect\n'
          '• No bullying, harassment, or intimidation\n'
          '• No hate speech based on race, ethnicity, religion, gender, '
          'sexual orientation, disability, or any other protected characteristic\n'
          '• No threats of violence or encouragement of self-harm',
    ),
    LegalSection(
      heading: '2. Keep It Safe',
      body:
          '• No sexually explicit or pornographic content\n'
          '• No content depicting or promoting violence or dangerous activities\n'
          '• No content exploiting or endangering minors\n'
          '• No sharing of personal information of others without consent\n'
          '• No promotion of illegal activities, drugs, or weapons',
    ),
    LegalSection(
      heading: '3. Be Authentic',
      body:
          '• Do not impersonate others or create fake accounts\n'
          '• Do not spread misinformation or misleading content\n'
          '• Do not engage in spam, scams, or deceptive practices\n'
          '• Respect intellectual property and give credit where due',
    ),
    LegalSection(
      heading: '4. Report Violations',
      body:
          'If you see content or behavior that violates these guidelines, '
          'please report it using the in-app report feature. We review all '
          'reports and take action within 24 hours.\n\n'
          'You can also block users whose content you do not wish to see.',
    ),
    LegalSection(
      heading: '5. Enforcement',
      body:
          'We enforce these guidelines through a combination of automated '
          'systems and human review. Consequences for violations include:\n\n'
          '• Content removal\n'
          '• Warning notification\n'
          '• Temporary account suspension\n'
          '• Permanent account ban\n\n'
          'Severe violations (child safety, terrorism, imminent threats) '
          'may also be reported to law enforcement.',
    ),
  ],
);
