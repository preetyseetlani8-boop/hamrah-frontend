import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../widgets/top_right_alert.dart';
import '../services/registration_service.dart';
import 'carDetails.dart';

class FaceVerificationPage extends StatefulWidget {
  final String registrationRole;

  const FaceVerificationPage({
    super.key,
    this.registrationRole = 'driver',
  });

  @override
  State<FaceVerificationPage> createState() => _FaceVerificationPageState();
}

class _FaceVerificationPageState extends State<FaceVerificationPage> {
  File? _selfieImage;
  bool _isUploading = false;
  bool _isVerifying = false;
  final ImagePicker _picker = ImagePicker();

  Future<void> _captureFace() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
      );
      if (pickedFile != null) {
        setState(() => _selfieImage = File(pickedFile.path));
      }
    } catch (e) {
      if (!mounted) return;
      TopRightAlert.show(context,
          title: 'Camera error',
          message: 'Unable to open camera.',
          isError: true);
    }
  }

  Future<void> _submitFace() async {
    if (_selfieImage == null) return;

    // Step 1 — upload selfie → get live_image_url
    setState(() => _isUploading = true);
    String liveUrl;
    try {
      liveUrl = await RegistrationService.uploadImage(_selfieImage!);
      RegistrationService.liveImageUrl = liveUrl;
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploading = false);
      TopRightAlert.show(context,
          title: 'Upload Failed',
          message: e.toString().replaceFirst('Exception: ', ''),
          isError: true);
      return;
    }
    setState(() {_isUploading = false; _isVerifying = true;});

    // Step 2 — compare CNIC face vs live selfie
    try {
      final result = await RegistrationService.verifyFaceWithUrls(
        cnicUrl: RegistrationService.cnicImageUrl,
        liveUrl: liveUrl,
      );

      if (!mounted) return;

      final verified = result['verified'] == true;

      if (!verified) {
        TopRightAlert.show(context,
            title: 'Face Not Matched',
            message: result['message']?.toString() ??
                'Selfie does not match CNIC photo. Try again.',
            isError: true);
        setState(() => _isVerifying = false);
        return;
      }

      TopRightAlert.show(context,
          title: 'Identity Verified',
          message: result['message']?.toString() ?? 'Face matched successfully.',
          isError: false);

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const CarDetailsPage()),
      );
    } catch (e) {
      if (!mounted) return;
      TopRightAlert.show(context,
          title: 'Verification Failed',
          message: e.toString().replaceFirst('Exception: ', ''),
          isError: true);
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool busy = _isUploading || _isVerifying;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/doodles1.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.topLeft,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new,
                        color: Color(0xFF00897B)),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(height: 10),
                const Icon(Icons.face_retouching_natural,
                    size: 70, color: Color(0xFF00897B)),
                const SizedBox(height: 12),
                const Text(
                  'Identity Verification',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF00897B)),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Take a clear front-facing selfie.\nIt will be compared with your CNIC photo.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const Spacer(),

                // Selfie preview
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF00897B), width: 3),
                  ),
                  child: CircleAvatar(
                    radius: 90,
                    backgroundColor: Colors.white,
                    backgroundImage: _selfieImage != null
                        ? FileImage(_selfieImage!)
                        : null,
                    child: _selfieImage == null
                        ? const Icon(Icons.person, size: 90, color: Colors.grey)
                        : null,
                  ),
                ),

                const Spacer(),

                // Status label
                if (busy)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Color(0xFF00897B))),
                        const SizedBox(width: 10),
                        Text(
                          _isUploading ? 'Uploading selfie...' : 'Comparing faces...',
                          style: const TextStyle(
                              color: Color(0xFF00897B), fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),

                // Capture button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: busy ? null : _captureFace,
                    icon: const Icon(Icons.camera_alt, color: Colors.white),
                    label: Text(
                      _selfieImage == null ? 'Take Selfie' : 'Retake',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00897B),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15)),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Continue button — only shown after selfie taken
                if (_selfieImage != null)
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton(
                      onPressed: busy ? null : _submitFace,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF00897B)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15)),
                      ),
                      child: const Text('Verify & Continue',
                          style: TextStyle(
                              color: Color(0xFF00897B),
                              fontWeight: FontWeight.bold)),
                    ),
                  ),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
