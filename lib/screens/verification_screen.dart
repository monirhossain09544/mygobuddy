import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mygobuddy/main.dart';
import 'package:mygobuddy/screens/pending_verification_screen.dart';
import 'package:mygobuddy/utils/constants.dart';
import 'package:mygobuddy/utils/localizations.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum VerificationMethod { passport, idCard, license }

class VerificationScreen extends StatefulWidget {
  const VerificationScreen({super.key});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  VerificationMethod? _selectedMethod;
  XFile? _frontImageFile;
  XFile? _backImageFile;
  XFile? _selfieImageFile;

  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _isCameraInitialized = false;
  bool _cameraPermissionDenied = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    final status = await Permission.camera.request();
    if (status.isGranted) {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (mounted) setState(() => _cameraPermissionDenied = true);
        return;
      }
      final frontCamera = _cameras.firstWhere(
              (camera) => camera.lensDirection == CameraLensDirection.front,
          orElse: () => _cameras.first);

      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      try {
        await _cameraController!.initialize();
        if (mounted) {
          setState(() {
            _isCameraInitialized = true;
            _cameraPermissionDenied = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isCameraInitialized = false;
            _cameraPermissionDenied = true;
          });
        }
      }
    } else {
      if (mounted) {
        setState(() {
          _cameraPermissionDenied = true;
        });
      }
    }
  }

  void _onPageChanged(int page) {
    setState(() {
      _currentPage = page;
    });
  }

  void _nextPage() {
    _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _previousPage() {
    _pageController.previousPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _pickImage(ImageSource source,
      {required bool isFront}) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: source, imageQuality: 80);
    if (pickedFile != null) {
      setState(() {
        if (isFront) {
          _frontImageFile = pickedFile;
        } else {
          _backImageFile = pickedFile;
        }
      });
    }
  }

  Future<void> _takePicture() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    if (_cameraController!.value.isTakingPicture) {
      return;
    }
    try {
      final XFile file = await _cameraController!.takePicture();
      setState(() {
        _selfieImageFile = file;
      });
    } catch (e) {
      // Handle error
    }
  }

  Future<void> _submitVerification() async {
    setState(() {
      _isSubmitting = true;
    });

    final localizations = AppLocalizations.of(context);

    try {
      final userId = supabase.auth.currentUser!.id;
      String? frontUrl, backUrl, selfieUrl;

      // Upload front image
      if (_frontImageFile != null) {
        frontUrl = await _uploadFile(userId, _frontImageFile!, 'front');
      }
      // Upload back image
      if (_backImageFile != null) {
        backUrl = await _uploadFile(userId, _backImageFile!, 'back');
      }
      // Upload selfie image
      if (_selfieImageFile != null) {
        selfieUrl = await _uploadFile(userId, _selfieImageFile!, 'selfie');
      }

      final verificationData = {
        'type': _selectedMethod!.name,
        'front_url': frontUrl,
        'back_url': backUrl,
        'selfie_url': selfieUrl,
        'submitted_at': DateTime.now().toIso8601String(),
      };

      await supabase.from('buddies').update({
        'verification_documents': verificationData,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', userId);

      if (mounted) {
        context.showSnackBar(
            localizations.translate('verification_submit_success'));
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
              builder: (context) => const PendingVerificationScreen()),
              (Route<dynamic> route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        context.showSnackBar(
            localizations.translate('verification_submit_error'),
            isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<String> _uploadFile(
      String userId, XFile file, String docType) async {
    final bytes = await file.readAsBytes();
    final fileExt = path.extension(file.path);
    final fileName =
        '${docType}_${DateTime.now().millisecondsSinceEpoch}$fileExt';
    final filePath = '$userId/$fileName';

    await supabase.storage.from('verification-docs').uploadBinary(
      filePath,
      bytes,
      fileOptions: FileOptions(contentType: file.mimeType),
    );

    return supabase.storage.from('verification-docs').getPublicUrl(filePath);
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    const Color primaryColor = Color(0xFF19638D);
    const Color backgroundColor = Color(0xFFF8F8F8);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: backgroundColor,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          backgroundColor: backgroundColor,
          elevation: 0,
          leading: _currentPage > 0
              ? IconButton(
            icon: const Icon(Icons.arrow_back_ios_new,
                color: Colors.black, size: 20),
            onPressed: _previousPage,
          )
              : null,
          title: Text(
            _getStepTitle(localizations),
            style: GoogleFonts.poppins(
              color: primaryColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: true,
        ),
        body: PageView(
          controller: _pageController,
          onPageChanged: _onPageChanged,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _buildDocumentSelectionPage(localizations),
            _buildDocumentUploadPage(localizations),
            _buildSelfiePage(localizations),
          ],
        ),
      ),
    );
  }

  String _getStepTitle(AppLocalizations localizations) {
    switch (_currentPage) {
      case 0:
        return localizations.translate('verification_step_1');
      case 1:
        return localizations.translate('verification_step_2');
      case 2:
        return localizations.translate('verification_step_3');
      default:
        return '';
    }
  }

  Widget _buildDocumentSelectionPage(AppLocalizations localizations) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Text(
            localizations.translate('verification_doc_type_title'),
            style: GoogleFonts.poppins(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF111827)),
          ),
          const SizedBox(height: 8),
          Text(
            localizations.translate('verification_doc_type_subtitle'),
            style: GoogleFonts.poppins(
                fontSize: 14, color: Colors.grey.shade700, height: 1.5),
          ),
          const SizedBox(height: 32),
          _buildOptionCard(
            icon: Icons.book_outlined,
            title: localizations.translate('verification_passport'),
            method: VerificationMethod.passport,
          ),
          const SizedBox(height: 16),
          _buildOptionCard(
            icon: Icons.badge_outlined,
            title: localizations.translate('verification_id_card'),
            method: VerificationMethod.idCard,
          ),
          const SizedBox(height: 16),
          _buildOptionCard(
            icon: Icons.directions_car_outlined,
            title: localizations.translate('verification_license'),
            method: VerificationMethod.license,
          ),
        ],
      ),
    );
  }

  Widget _buildOptionCard(
      {required IconData icon,
        required String title,
        required VerificationMethod method}) {
    const Color accentColor = Color(0xFFF15808);
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedMethod = method;
        });
        _nextPage();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade300, width: 1),
        ),
        child: Row(
          children: [
            Icon(icon, color: accentColor, size: 28),
            const SizedBox(width: 20),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87),
              ),
            ),
            Icon(Icons.arrow_forward_ios,
                color: Colors.grey.shade400, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentUploadPage(AppLocalizations localizations) {
    final bool needsTwoImages = _selectedMethod == VerificationMethod.idCard ||
        _selectedMethod == VerificationMethod.license;
    final bool canProceed = _frontImageFile != null &&
        (!needsTwoImages || _backImageFile != null);
    final docType = _selectedMethod?.name ?? '';
    final docTypeName =
    localizations.translate('verification_${docType.toLowerCase()}');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  Text(
                    localizations.translate('verification_upload_title',
                        args: {'documentType': docTypeName}),
                    style: GoogleFonts.poppins(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF111827)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    localizations.translate('verification_upload_subtitle'),
                    style: GoogleFonts.poppins(
                        fontSize: 14, color: Colors.grey.shade700, height: 1.5),
                  ),
                  const SizedBox(height: 32),
                  _ImagePickerBox(
                    label: localizations.translate('verification_upload_front'),
                    imageFile: _frontImageFile,
                    onTap: () => _pickImage(ImageSource.gallery, isFront: true),
                  ),
                  if (needsTwoImages) ...[
                    const SizedBox(height: 24),
                    _ImagePickerBox(
                      label:
                      localizations.translate('verification_upload_back'),
                      imageFile: _backImageFile,
                      onTap: () =>
                          _pickImage(ImageSource.gallery, isFront: false),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20.0),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: canProceed ? _nextPage : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF15808),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                  const Color(0xFFF15808).withOpacity(0.5),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  localizations.translate('verification_button_next'),
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelfiePage(AppLocalizations localizations) {
    if (_selfieImageFile != null) {
      return _buildSelfieConfirmationPage(localizations);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 20),
          Text(
            localizations.translate('verification_selfie_title'),
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF111827)),
          ),
          const SizedBox(height: 8),
          Text(
            localizations.translate('verification_selfie_subtitle'),
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
                fontSize: 14, color: Colors.grey.shade700, height: 1.5),
          ),
          const SizedBox(height: 32),
          Expanded(
            child: Center(
              child: _buildCameraPreview(localizations),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20.0),
            child: FloatingActionButton(
              onPressed: _isCameraInitialized ? _takePicture : null,
              backgroundColor: _isCameraInitialized
                  ? const Color(0xFFF15808)
                  : Colors.grey,
              child: const Icon(Icons.camera_alt, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraPreview(AppLocalizations localizations) {
    if (_cameraPermissionDenied) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 60),
            const SizedBox(height: 16),
            Text(
              localizations
                  .translate('verification_camera_permission_denied_title'),
              textAlign: TextAlign.center,
              style:
              GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              localizations
                  .translate('verification_camera_permission_denied_message'),
              textAlign: TextAlign.center,
              style:
              GoogleFonts.poppins(fontSize: 14, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: openAppSettings,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF15808),
                foregroundColor: Colors.white,
              ),
              child: Text(
                  localizations.translate('verification_button_open_settings')),
            )
          ],
        ),
      );
    }

    if (_isCameraInitialized && _cameraController != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(150),
        child: SizedBox(
          width: 300,
          height: 300,
          child: CameraPreview(_cameraController!),
        ),
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text(localizations.translate('verification_camera_loading')),
      ],
    );
  }

  Widget _buildSelfieConfirmationPage(AppLocalizations localizations) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  localizations.translate('verification_selfie_confirm_title'),
                  style: GoogleFonts.poppins(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF111827)),
                ),
                const SizedBox(height: 8),
                Text(
                  localizations
                      .translate('verification_selfie_confirm_subtitle'),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      fontSize: 14, color: Colors.grey.shade700, height: 1.5),
                ),
                const SizedBox(height: 32),
                ClipRRect(
                  borderRadius: BorderRadius.circular(150),
                  child: Image.file(
                    File(_selfieImageFile!.path),
                    width: 300,
                    height: 300,
                    fit: BoxFit.cover,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20.0),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _selfieImageFile = null),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: const BorderSide(color: Color(0xFFF15808)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      localizations.translate('verification_button_retake'),
                      style: GoogleFonts.poppins(
                          color: const Color(0xFFF15808),
                          fontWeight: FontWeight.bold,
                          fontSize: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _submitVerification,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF15808),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5))
                        : Text(
                      localizations.translate(
                          'verification_button_confirm_submit'),
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ImagePickerBox extends StatelessWidget {
  final String label;
  final XFile? imageFile;
  final VoidCallback onTap;

  const _ImagePickerBox({
    required this.label,
    required this.imageFile,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black87),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: onTap,
          child: Container(
            height: 180,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300, width: 1.5),
            ),
            child: imageFile != null
                ? ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Image.file(
                File(imageFile!.path),
                fit: BoxFit.cover,
              ),
            )
                : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_a_photo_outlined,
                    color: Colors.grey.shade500, size: 40),
                const SizedBox(height: 8),
                Text(
                  localizations
                      .translate('verification_upload_tap_to_upload'),
                  style: GoogleFonts.poppins(
                      color: Colors.grey.shade600, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
