import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mygobuddy/screens/selection_screen.dart';
import 'package:mygobuddy/utils/localizations.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _currentPage = 0;

  void _changePage(int newPage, int totalPages) {
    if (newPage >= 0 && newPage < totalPages) {
      setState(() {
        _currentPage = newPage;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;

    final List<Map<String, dynamic>> pageData = [
      {
        "image": "assets/images/onboarding_background.png",
        "titleKey": "onboarding_title_1",
        "alignment": -0.2,
        "buttonColor": const Color(0xFF19638D),
      },
      {
        "image": "assets/images/onboarding_background_2.png",
        "titleKey": "onboarding_title_2",
        "alignment": 0.0,
        "buttonColor": const Color(0xFFF15808),
      },
      {
        "image": "assets/images/onboarding_background_3.png",
        "titleKey": "onboarding_title_3",
        "alignment": 0.0,
        "buttonColor": const Color(0xFF19638D),
      },
    ];

    final currentPageData = pageData[_currentPage];
    bool isLastPage = _currentPage == pageData.length - 1;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        body: GestureDetector(
          onHorizontalDragEnd: (details) {
            if (details.primaryVelocity! < 0) {
              if (!isLastPage) _changePage(_currentPage + 1, pageData.length);
            } else if (details.primaryVelocity! > 0) {
              _changePage(_currentPage - 1, pageData.length);
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 500),
                child: Container(
                  key: ValueKey<int>(_currentPage),
                  decoration: BoxDecoration(
                    image: DecorationImage(
                      image: AssetImage(currentPageData["image"]),
                      fit: BoxFit.cover,
                      alignment: Alignment(currentPageData["alignment"], 0),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withOpacity(0.0),
                        Colors.white.withOpacity(0.5),
                        Colors.white.withOpacity(0.9),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.0, 0.2, 1.0],
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 80, 20, 40),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 500),
                          transitionBuilder: (child, animation) {
                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0, 0.2),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              ),
                            );
                          },
                          child: SizedBox(
                            key: ValueKey<int>(_currentPage),
                            width: 284,
                            child: Text(
                              localizations.translate(currentPageData["titleKey"]),
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(
                                color: Colors.black,
                                fontSize: 24,
                                fontWeight: FontWeight.w500,
                                height: 1.2,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(pageData.length, (index) => _buildPageIndicator(index == _currentPage)),
                        ),
                        const SizedBox(height: 32),
                        GestureDetector(
                          onTap: () {
                            if (isLastPage) {
                              Navigator.of(context).pushReplacement(
                                MaterialPageRoute(builder: (context) => const SelectionScreen()),
                              );
                            } else {
                              _changePage(_currentPage + 1, pageData.length);
                            }
                          },
                          child: Container(
                            width: 219,
                            padding: const EdgeInsets.all(12),
                            decoration: ShapeDecoration(
                              color: currentPageData["buttonColor"],
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              isLastPage
                                  ? localizations.translate('button_get_started')
                                  : localizations.translate('button_continue'),
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                height: 1.20,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPageIndicator(bool isActive) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(horizontal: 4.0),
      height: 8.0,
      width: isActive ? 24.0 : 8.0,
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFFF15808) : Colors.grey.shade400,
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }
}
