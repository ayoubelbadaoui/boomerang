import 'package:boomerang/features/legal/domain/legal_documents.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class LegalPage extends StatelessWidget {
  const LegalPage({super.key, required this.document});

  final LegalDocument document;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
        title: Text(
          document.title,
          style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 40.h),
        children: [
          Text(
            'Last updated: ${document.lastUpdated}',
            style: TextStyle(
              fontSize: 13.sp,
              color: Colors.black45,
              fontStyle: FontStyle.italic,
            ),
          ),
          Text(
            'Version ${document.version}',
            style: TextStyle(fontSize: 12.sp, color: Colors.black38),
          ),
          SizedBox(height: 20.h),
          for (final section in document.sections) ...[
            Text(
              section.heading,
              style: TextStyle(
                fontSize: 17.sp,
                fontWeight: FontWeight.w700,
                color: Colors.black,
                height: 1.4,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              section.body,
              style: TextStyle(
                fontSize: 14.sp,
                color: Colors.black87,
                height: 1.6,
              ),
            ),
            SizedBox(height: 20.h),
          ],
        ],
      ),
    );
  }
}

void showPrivacyPolicy(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => LegalPage(document: privacyPolicy)),
  );
}

void showTermsOfService(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => LegalPage(document: termsOfService)),
  );
}

void showCommunityGuidelines(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => LegalPage(document: communityGuidelines)),
  );
}
