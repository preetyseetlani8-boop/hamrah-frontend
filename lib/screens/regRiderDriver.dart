import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../widgets/top_right_alert.dart';
import '../services/registration_service.dart';
import '../services/UserSession.dart';
import 'carDetails.dart';
import 'login_screen.dart';

class DriverRiderRegisterPage extends StatefulWidget {
  final bool isUpgrade;

  const DriverRiderRegisterPage({super.key, this.isUpgrade = false});

  @override
  State<DriverRiderRegisterPage> createState() =>
      _DriverRiderRegisterPageState();
}

class _DriverRiderRegisterPageState extends State<DriverRiderRegisterPage> {
  bool _obscurePassword = true;

  // CNIC image state
  File? _cnicImage;
  bool _cnicUploaded = false;
  bool _isCnicUploading = false;

  // Selfie state
  File? _selfieImage;
  bool _selfieUploaded = false;
  bool _isSelfieUploading = false;

  // Face verify state
  bool _faceVerified = false;
  bool _isFaceVerifying = false;

  String _selectedGender = 'Male';

  final ImagePicker _picker = ImagePicker();

  final TextEditingController firstNameController  = TextEditingController();
  final TextEditingController lastNameController   = TextEditingController();
  final TextEditingController studentIdController  = TextEditingController();
  final TextEditingController phoneController      = TextEditingController();
  final TextEditingController cnicController       = TextEditingController();
  final TextEditingController emailController      = TextEditingController();
  final TextEditingController passwordController   = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.isUpgrade) {
      final parts = UserSession.name.split(' ');
      firstNameController.text = parts.isNotEmpty ? parts[0] : '';
      lastNameController.text = parts.length > 1 ? parts.sublist(1).join(' ') : '';
      studentIdController.text = UserSession.studentId;
      phoneController.text = UserSession.phone;
      emailController.text = UserSession.email;
    }
  }

  @override
  void dispose() {
    firstNameController.dispose();
    lastNameController.dispose();
    studentIdController.dispose();
    phoneController.dispose();
    cnicController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────
  // CNIC image pick + upload
  // ─────────────────────────────────────────────
  Future<void> _pickCnic(ImageSource source) async {
    final XFile? picked = await _picker.pickImage(source: source);
    if (picked == null) return;

    final file = File(picked.path);
    setState(() {
      _cnicImage      = file;
      _cnicUploaded   = false;
      _selfieImage    = null;
      _selfieUploaded = false;
      _faceVerified   = false;
    });

    await _uploadCnic(file);
  }

  Future<void> _uploadCnic(File file) async {
    setState(() => _isCnicUploading = true);
    try {
      final url = await RegistrationService.uploadImage(file);
      RegistrationService.cnicImageUrl = url;
      setState(() => _cnicUploaded = true);
      if (!mounted) return;
      TopRightAlert.show(context,
          title: 'CNIC Uploaded', message: 'Now take a selfie.', isError: false);
    } catch (e) {
      // If /upload not ready yet, store locally and still allow selfie step
      RegistrationService.cnicImageUrl = '';
      setState(() => _cnicUploaded = true);
      if (!mounted) return;
      TopRightAlert.show(context,
          title: 'Image Saved', message: 'Now take a selfie.', isError: false);
    } finally {
      if (mounted) setState(() => _isCnicUploading = false);
    }
  }

  // ─────────────────────────────────────────────
  // Selfie pick + upload + face verify
  // ─────────────────────────────────────────────
  Future<void> _takeSelfie() async {
    final XFile? picked = await _picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
    );
    if (picked == null) return;

    final file = File(picked.path);
    setState(() {
      _selfieImage    = file;
      _selfieUploaded = false;
      _faceVerified   = false;
    });

    await _uploadSelfieAndVerify(file);
  }

  Future<void> _uploadSelfieAndVerify(File file) async {
    // Step 1 — upload selfie
    setState(() => _isSelfieUploading = true);
    try {
      final url = await RegistrationService.uploadImage(file);
      RegistrationService.liveImageUrl = url;
      setState(() => _selfieUploaded = true);
    } catch (e) {
      RegistrationService.liveImageUrl = '';
      setState(() => _selfieUploaded = true);
    } finally {
      if (mounted) setState(() => _isSelfieUploading = false);
    }

    // Step 2 — compare faces
    setState(() => _isFaceVerifying = true);
    try {
      final result = await RegistrationService.verifyFaceWithUrls(
        cnicUrl: RegistrationService.cnicImageUrl,
        liveUrl: RegistrationService.liveImageUrl,
      );

      if (!mounted) return;
      final verified = result['verified'] == true;
      setState(() => _faceVerified = verified);

      TopRightAlert.show(context,
          title: verified ? 'Face Matched ✅' : 'Face Not Matched ❌',
          message: result['message']?.toString() ??
              (verified ? 'Identity verified.' : 'Selfie does not match CNIC. Retake.'),
          isError: !verified);
    } catch (e) {
      if (!mounted) return;
      TopRightAlert.show(context,
          title: 'Verification Error',
          message: e.toString().replaceFirst('Exception: ', ''),
          isError: true);
      setState(() => _faceVerified = false);
    } finally {
      if (mounted) setState(() => _isFaceVerifying = false);
    }
  }

  // ─────────────────────────────────────────────
  // Continue button
  // ─────────────────────────────────────────────
  void _handleNext() {
    if (firstNameController.text.isEmpty || lastNameController.text.isEmpty) {
      TopRightAlert.show(context, title: 'Name Required',
          message: 'Enter first and last name.', isError: true); return;
    }
    if (studentIdController.text.isEmpty) {
      TopRightAlert.show(context, title: 'Student ID Required',
          message: 'Enter student ID.', isError: true); return;
    }
    if (phoneController.text.isEmpty) {
      TopRightAlert.show(context, title: 'Phone Required',
          message: 'Enter phone number.', isError: true); return;
    }
    if (cnicController.text.isEmpty) {
      TopRightAlert.show(context, title: 'CNIC Required',
          message: 'Enter CNIC number.', isError: true); return;
    }
    if (_cnicImage == null) {
      TopRightAlert.show(context, title: 'CNIC Image Required',
          message: 'Upload a photo of your CNIC.', isError: true); return;
    }
    if (_selfieImage == null) {
      TopRightAlert.show(context, title: 'Selfie Required',
          message: 'Take a live selfie for verification.', isError: true); return;
    }
    if (!_faceVerified) {
      TopRightAlert.show(context, title: 'Face Not Verified',
          message: 'Selfie does not match CNIC. Retake selfie.', isError: true); return;
    }
    if (emailController.text.isEmpty) {
      TopRightAlert.show(context, title: 'Email Required',
          message: 'Enter email address.', isError: true); return;
    }
    if (!widget.isUpgrade && passwordController.text.isEmpty) {
      TopRightAlert.show(context, title: 'Password Required',
          message: 'Enter password.', isError: true); return;
    }

    // Save draft
    RegistrationService.password    = widget.isUpgrade
        ? RegistrationService.password
        : passwordController.text.trim();
    RegistrationService.firstName   = firstNameController.text.trim();
    RegistrationService.lastName    = lastNameController.text.trim();
    RegistrationService.cnicNumber  = cnicController.text.trim();
    RegistrationService.studentId   = studentIdController.text.trim();
    RegistrationService.phone       = phoneController.text.trim();
    RegistrationService.email       = emailController.text.trim();
    RegistrationService.gender      = _selectedGender;

    UserSession.name      = '${firstNameController.text.trim()} ${lastNameController.text.trim()}';
    UserSession.studentId = studentIdController.text.trim();
    UserSession.phone     = phoneController.text.trim();
    UserSession.email     = emailController.text.trim();

    Navigator.push(context,
        MaterialPageRoute(
            builder: (_) => CarDetailsPage(isUpgrade: widget.isUpgrade)));
  }

  @override
  Widget build(BuildContext context) {
    final bool anyBusy = _isCnicUploading || _isSelfieUploading || _isFaceVerifying;

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
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new,
                          color: Color(0xFF00897B)),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Text(widget.isUpgrade ? 'Become a Driver' : 'Driver Registration',
                        style: TextStyle(
                            color: Color(0xFF00897B),
                            fontSize: 20,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Center(
                        child: Text('Personal information',
                            style: TextStyle(color: Colors.grey)),
                      ),
                      const SizedBox(height: 20),

                      // Name row
                      Row(children: [
                        Expanded(child: _buildTextField(
                            controller: firstNameController,
                            icon: Icons.person_outline, hintText: 'First Name')),
                        const SizedBox(width: 15),
                        Expanded(child: _buildTextField(
                            controller: lastNameController,
                            icon: Icons.person_outline, hintText: 'Last Name')),
                      ]),
                      const SizedBox(height: 15),

                      _buildTextField(controller: studentIdController,
                          icon: Icons.badge_outlined, hintText: 'DSU Reg ID'),
                      const SizedBox(height: 15),

                      _buildTextField(
                        controller: phoneController,
                        icon: Icons.phone_android_outlined,
                        hintText: 'Phone No (03XXXXXXXXX)',
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(11),
                        ],
                      ),
                      const SizedBox(height: 15),

                      _buildTextField(
                        controller: cnicController,
                        icon: Icons.credit_card_outlined,
                        hintText: 'CNIC (XXXXX-XXXXXXX-X)',
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(13),
                          _CNICFormatter(),
                        ],
                      ),
                      const SizedBox(height: 15),

                      // Gender dropdown
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: DropdownButtonFormField<String>(
                          value: _selectedGender,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.person_pin_outlined,
                                color: Color(0xFF00897B)),
                            border: InputBorder.none,
                            labelText: 'Gender',
                            labelStyle: TextStyle(color: Color(0xFF00897B)),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'Male', child: Text('Male')),
                            DropdownMenuItem(value: 'Female', child: Text('Female')),
                          ],
                          onChanged: (v) => setState(() => _selectedGender = v!),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── STEP 1: CNIC Image ──
                      _sectionHeader('Step 1: Upload CNIC Photo',
                          Icons.credit_card, _cnicUploaded),
                      const SizedBox(height: 10),
                      _buildImageBox(
                        image: _cnicImage,
                        isUploading: _isCnicUploading,
                        isUploaded: _cnicUploaded,
                        uploadedLabel: 'CNIC uploaded ✅',
                        onCamera: () => _pickCnic(ImageSource.camera),
                        onGallery: () => _pickCnic(ImageSource.gallery),
                      ),
                      const SizedBox(height: 20),

                      // ── STEP 2: Live Selfie (only shown after CNIC uploaded) ──
                      if (_cnicUploaded) ...[
                        _sectionHeader('Step 2: Take Live Selfie',
                            Icons.face_retouching_natural, _faceVerified),
                        const SizedBox(height: 10),
                        _buildSelfieBox(),
                        const SizedBox(height: 20),
                      ],

                      // ── Rest of form (only shown after face verified) ──
                      if (_faceVerified) ...[
                        _buildTextField(
                            controller: emailController,
                            icon: Icons.email_outlined,
                            hintText: 'Email',
                            keyboardType: TextInputType.emailAddress),
                        const SizedBox(height: 15),
                        _buildTextField(
                            controller: passwordController,
                            icon: Icons.lock_outline,
                            hintText: 'Password',
                            isPassword: true),
                        const SizedBox(height: 30),

                        SizedBox(
                          width: double.infinity,
                          height: 55,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00897B),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15)),
                            ),
                            onPressed: anyBusy ? null : _handleNext,
                            child: const Text('Continue',
                                style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],

                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('Already have an account? ',
                              style: TextStyle(color: Colors.black54)),
                          GestureDetector(
                            onTap: () => Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const HamrahLoginPage()),
                              (route) => false,
                            ),
                            child: const Text('Login',
                                style: TextStyle(
                                    color: Color(0xFF00897B),
                                    fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Section header with step indicator ──
  Widget _sectionHeader(String title, IconData icon, bool done) {
    return Row(
      children: [
        Icon(done ? Icons.check_circle : icon,
            color: done ? Colors.green : const Color(0xFF00897B), size: 20),
        const SizedBox(width: 8),
        Text(title,
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: done ? Colors.green : const Color(0xFF00897B),
                fontSize: 14)),
      ],
    );
  }

  // ── CNIC image upload box ──
  Widget _buildImageBox({
    required File? image,
    required bool isUploading,
    required bool isUploaded,
    required String uploadedLabel,
    required VoidCallback onCamera,
    required VoidCallback onGallery,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: isUploaded
              ? Colors.green.withOpacity(0.5)
              : Colors.teal.withOpacity(0.3),
        ),
      ),
      child: Column(
        children: [
          if (isUploading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Column(children: [
                CircularProgressIndicator(color: Color(0xFF00897B)),
                SizedBox(height: 8),
                Text('Uploading...', style: TextStyle(color: Colors.grey)),
              ]),
            )
          else if (image != null)
            Stack(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.file(image,
                    height: 140, width: double.infinity, fit: BoxFit.cover),
              ),
              Positioned(
                bottom: 6, right: 6,
                child: GestureDetector(
                  onTap: onCamera,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                        color: const Color(0xFF00897B),
                        borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.edit, color: Colors.white, size: 16),
                  ),
                ),
              ),
            ])
          else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Icon(Icons.image_search, size: 50, color: Colors.grey),
            ),
          const SizedBox(height: 8),
          if (!isUploading)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton.icon(
                  onPressed: onCamera,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Camera'),
                ),
                TextButton.icon(
                  onPressed: onGallery,
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Gallery'),
                ),
              ],
            ),
          if (isUploaded && !isUploading)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 16),
                  const SizedBox(width: 4),
                  Text(uploadedLabel,
                      style: const TextStyle(
                          color: Colors.green,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Selfie box ──
  Widget _buildSelfieBox() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: _faceVerified
              ? Colors.green.withOpacity(0.5)
              : Colors.teal.withOpacity(0.3),
        ),
      ),
      child: Column(
        children: [
          // Selfie preview
          CircleAvatar(
            radius: 60,
            backgroundColor: Colors.grey.shade100,
            backgroundImage:
                _selfieImage != null ? FileImage(_selfieImage!) : null,
            child: _selfieImage == null
                ? const Icon(Icons.face, size: 60, color: Colors.grey)
                : null,
          ),
          const SizedBox(height: 12),

          // Status
          if (_isSelfieUploading)
            const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2,
                      color: Color(0xFF00897B))),
              SizedBox(width: 8),
              Text('Uploading selfie...',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
            ])
          else if (_isFaceVerifying)
            const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2,
                      color: Color(0xFF00897B))),
              SizedBox(width: 8),
              Text('Comparing faces...',
                  style: TextStyle(color: Color(0xFF00897B),
                      fontWeight: FontWeight.w600, fontSize: 12)),
            ])
          else if (_faceVerified)
            const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.verified, color: Colors.green, size: 18),
              SizedBox(width: 6),
              Text('Face matched — identity verified',
                  style: TextStyle(color: Colors.green,
                      fontWeight: FontWeight.w600, fontSize: 12)),
            ])
          else if (_selfieImage != null)
            const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red, size: 18),
              SizedBox(width: 6),
              Text('Not matched — retake selfie',
                  style: TextStyle(color: Colors.red,
                      fontWeight: FontWeight.w600, fontSize: 12)),
            ]),

          const SizedBox(height: 12),

          // Take selfie button
          if (!_isSelfieUploading && !_isFaceVerifying)
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                onPressed: _takeSelfie,
                icon: const Icon(Icons.camera_front, color: Colors.white),
                label: Text(
                  _selfieImage == null ? 'Take Selfie' : 'Retake Selfie',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00897B),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    TextEditingController? controller,
    required IconData icon,
    required String hintText,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    bool isPassword = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      obscureText: isPassword ? _obscurePassword : false,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: const Color(0xFF00897B)),
        hintText: hintText,
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(_obscurePassword
                    ? Icons.visibility_off
                    : Icons.visibility),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              )
            : null,
        filled: true,
        fillColor: Colors.white.withOpacity(0.9),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Color(0xFF00897B), width: 1.5),
        ),
      ),
    );
  }
}

class _CNICFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    var text = newValue.text;
    if (text.length > 5 && text[5] != '-')
      text = '${text.substring(0, 5)}-${text.substring(5)}';
    if (text.length > 13 && text[13] != '-')
      text = '${text.substring(0, 13)}-${text.substring(13)}';
    return newValue.copyWith(
        text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}
