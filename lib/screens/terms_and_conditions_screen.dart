import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class TermsAndConditionsScreen extends StatelessWidget {
  const TermsAndConditionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Terms and Conditions',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black87),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('1. Introduction'),
            _buildParagraph(
                'Welcome to MyGoBuddy. These terms and conditions outline the rules and regulations for the use of MyGoBuddy\'s mobile application. By accessing this app, we assume you accept these terms and conditions. Do not continue to use MyGoBuddy if you do not agree to all of the terms and conditions stated on this page.'),
            const SizedBox(height: 20),
            _buildSectionTitle('2. Intellectual Property Rights'),
            _buildParagraph(
                'Other than the content you own, under these Terms, MyGoBuddy and/or its licensors own all the intellectual property rights and materials contained in this app. You are granted a limited license only for purposes of viewing the material contained on this app.'),
            const SizedBox(height: 20),
            _buildSectionTitle('3. Restrictions'),
            _buildParagraph(
                'You are specifically restricted from all of the following:\n'
                    '• Publishing any app material in any other media;\n'
                    '• Selling, sublicensing and/or otherwise commercializing any app material;\n'
                    '• Publicly performing and/or showing any app material;\n'
                    '• Using this app in any way that is or may be damaging to this app;\n'
                    '• Using this app in any way that impacts user access to this app;\n'
                    '• Using this app contrary to applicable laws and regulations, or in any way may cause harm to the app, or to any person or business entity;\n'
                    '• Engaging in any data mining, data harvesting, data extracting or any other similar activity in relation to this app.'),
            const SizedBox(height: 20),
            _buildSectionTitle('4. Your Content'),
            _buildParagraph(
                'In these app Standard Terms and Conditions, "Your Content" shall mean any audio, video text, images or other material you choose to display on this app. By displaying Your Content, you grant MyGoBuddy a non-exclusive, worldwide irrevocable, sub-licensable license to use, reproduce, adapt, publish, translate and distribute it in any and all media.'),
            const SizedBox(height: 20),
            _buildSectionTitle('5. No warranties'),
            _buildParagraph(
                'This app is provided "as is," with all faults, and MyGoBuddy expresses no representations or warranties, of any kind related to this app or the materials contained on this app. Also, nothing contained on this app shall be interpreted as advising you.'),
            const SizedBox(height: 20),
            _buildSectionTitle('6. Limitation of liability'),
            _buildParagraph(
                'In no event shall MyGoBuddy, nor any of its officers, directors and employees, be held liable for anything arising out of or in any way connected with your use of this app whether such liability is under contract. MyGoBuddy, including its officers, directors and employees shall not be held liable for any indirect, consequential or special liability arising out of or in any way related to your use of this app.'),
            const SizedBox(height: 20),
            _buildSectionTitle('7. Governing Law & Jurisdiction'),
            _buildParagraph(
                'These Terms will be governed by and interpreted in accordance with the laws of the State/Country, and you submit to the non-exclusive jurisdiction of the state and federal courts located in State/Country for the resolution of any disputes.'),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.poppins(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: const Color(0xFF19638D),
      ),
    );
  }

  Widget _buildParagraph(String text) {
    return Text(
      text,
      style: GoogleFonts.poppins(
        fontSize: 14,
        color: Colors.black.withOpacity(0.75),
        height: 1.6,
      ),
    );
  }
}
