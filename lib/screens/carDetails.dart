// lib/screens/carDetails.dart

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../widgets/top_right_alert.dart';
import '../services/registration_service.dart';
import 'otp_verification_screen.dart';

class CarDetailsPage extends StatefulWidget {
  final bool isUpgrade;

  const CarDetailsPage({super.key, this.isUpgrade = false});

  @override
  State<CarDetailsPage> createState() => _CarDetailsPageState();
}

class _CarDetailsPageState extends State<CarDetailsPage> {
  String? selectedTransport;
  File? _licenseImage;
  bool _isLicenseVerified = false;
  bool _isUploading = false;
  bool _isRegistering = false;
  Map<String, dynamic>? _extractedLicenseData;

  final ImagePicker _picker = ImagePicker();

  final TextEditingController _modelController = TextEditingController();
  final TextEditingController _colorController = TextEditingController();
  final TextEditingController _regController   = TextEditingController();
  final List<Map<String, String>> _vehicles = [];

  @override
  void dispose() {
    _modelController.dispose();
    _colorController.dispose();
    _regController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────
  // Step 1: Upload license image → get URL
  // Step 2: Send URL to /license/verify → OCR
  // ─────────────────────────────────────────────
  Future<void> _uploadLicenseToBackend(File imageFile) async {
    setState(() => _isUploading = true);

    try {
      // Step 1 — upload image, get URL
      final licenseUrl = await RegistrationService.uploadImage(imageFile);
      RegistrationService.licenseImageUrl = licenseUrl;

      // Step 2 — verify license via OCR
      final data = await RegistrationService.verifyLicense(
          licenseUrl: licenseUrl);

      setState(() {
        _extractedLicenseData = data['extracted'] as Map<String, dynamic>?;
        _isLicenseVerified = true;
        _isUploading = false;
      });

      if (!mounted) return;
      TopRightAlert.show(
        context,
        title: 'License verified',
        message: data['message']?.toString() ?? 'License recorded.',
        isError: false,
      );
    } catch (e) {
      setState(() => _isUploading = false);
      if (!mounted) return;
      TopRightAlert.show(
        context,
        title: 'Upload Error',
        message: e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    }
  }

  Future<void> _pickLicense(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(source: source);
      if (pickedFile == null) return;

      final File imageFile = File(pickedFile.path);

      setState(() {
        _licenseImage = imageFile;
        _isLicenseVerified = false;
        _extractedLicenseData = null;
      });

      await _uploadLicenseToBackend(imageFile);
    } catch (e) {
      TopRightAlert.show(
        context,
        title: 'Error',
        message: 'Something went wrong: $e',
        isError: true,
      );
    }
  }

  // ─────────────────────────────────────────────
  // Finish — register driver then go to OTP
  // ─────────────────────────────────────────────
  void _addVehicleToList() {
    if (selectedTransport == null ||
        _modelController.text.isEmpty ||
        _colorController.text.isEmpty ||
        _regController.text.isEmpty) {
      TopRightAlert.show(context,
          title: 'Fields Missing',
          message: 'Complete all vehicle fields before adding.',
          isError: true);
      return;
    }
    if (_vehicles.length >= 2) {
      TopRightAlert.show(context,
          title: 'Limit Reached',
          message: 'Maximum 2 vehicles allowed.',
          isError: true);
      return;
    }

    final number = _regController.text.trim();
    if (_vehicles.any((v) => v['vehicle_number'] == number)) {
      TopRightAlert.show(context,
          title: 'Duplicate',
          message: 'This vehicle is already in your list.',
          isError: true);
      return;
    }

    setState(() {
      _vehicles.add({
        'vehicle_number': number,
        'mode_of_transport': selectedTransport!.toLowerCase(),
        'vehicle_model': _modelController.text.trim(),
        'vehicle_colour': _colorController.text.trim(),
      });
      _modelController.clear();
      _colorController.clear();
      _regController.clear();
      selectedTransport = null;
    });
  }

  void _removeVehicle(int index) {
    setState(() => _vehicles.removeAt(index));
  }

  Future<void> _finishRegistration() async {
    if (_licenseImage == null) {
      TopRightAlert.show(context,
          title: 'License Missing',
          message: 'Upload your driving license.',
          isError: true);
      return;
    }

    if (!_isLicenseVerified) {
      TopRightAlert.show(context,
          title: 'Not Verified',
          message: 'Wait for license verification to finish.',
          isError: true);
      return;
    }

    if (_vehicles.isEmpty) {
      if (selectedTransport == null ||
          _modelController.text.isEmpty ||
          _colorController.text.isEmpty ||
          _regController.text.isEmpty) {
        TopRightAlert.show(context,
            title: 'Fields Missing',
            message: 'Add at least one vehicle.',
            isError: true);
        return;
      }
      _addVehicleToList();
      if (_vehicles.isEmpty) return;
    }

    setState(() => _isRegistering = true);

    try {
      RegistrationService.vehicleDrafts
        ..clear()
        ..addAll(_vehicles.map((v) => Map<String, dynamic>.from(v)));

      if (widget.isUpgrade) {
        await RegistrationService.registerDriverUpgrade();
      } else {
        await RegistrationService.registerDriver();
      }

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const OtpVerificationPage(
            registrationRole: 'driver',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      TopRightAlert.show(
        context,
        title: 'Registration Failed',
        message: e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isRegistering = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool busy = _isUploading || _isRegistering;

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
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new,
                          color: Color(0xFF00897B)),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Text(
                      'Vehicle & License',
                      style: TextStyle(
                          color: Color(0xFF00897B),
                          fontSize: 20,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Vehicle information',
                          style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 25),

                      const Text('Upload Driving License',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.black87)),
                      const SizedBox(height: 10),

                      _buildUploadBox(),
                      const SizedBox(height: 8),

                      if (_licenseImage != null) _buildVerificationBadge(),
                      if (_extractedLicenseData != null)
                        _buildExtractedDataCard(),

                      const SizedBox(height: 25),

                      _buildTransportDropdown(),
                      const SizedBox(height: 15),

                      if (selectedTransport == 'Car') ...[
                        _buildVehicleField(
                            Icons.directions_car_filled_outlined,
                            'Car Model (e.g. Corolla 2022)',
                            _modelController),
                        const SizedBox(height: 15),
                        _buildVehicleField(Icons.color_lens_outlined,
                            'Car Color', _colorController),
                        const SizedBox(height: 15),
                        _buildVehicleField(
                            Icons.confirmation_number_outlined,
                            'Car Registration No (e.g. ABC-123)',
                            _regController),
                      ] else if (selectedTransport == 'Bike') ...[
                        _buildVehicleField(
                            Icons.two_wheeler_outlined,
                            'Bike Model (e.g. Honda 125 2022)',
                            _modelController),
                        const SizedBox(height: 15),
                        _buildVehicleField(Icons.color_lens_outlined,
                            'Bike Color', _colorController),
                        const SizedBox(height: 15),
                        _buildVehicleField(
                            Icons.confirmation_number_outlined,
                            'Bike Registration No (e.g. KHI-1234)',
                            _regController),
                      ],

                      const SizedBox(height: 12),
                      if (_vehicles.length < 2)
                        OutlinedButton.icon(
                          onPressed: busy ? null : _addVehicleToList,
                          icon: const Icon(Icons.add, color: Color(0xFF00897B)),
                          label: const Text('Add Vehicle',
                              style: TextStyle(color: Color(0xFF00897B))),
                        ),
                      if (_vehicles.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        ...List.generate(_vehicles.length, (i) {
                          final v = _vehicles[i];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: const Icon(Icons.directions_car,
                                  color: Color(0xFF00897B)),
                              title: Text(v['vehicle_number'] ?? ''),
                              subtitle: Text(
                                  '${v['mode_of_transport']} • ${v['vehicle_model']} • ${v['vehicle_colour']}'),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red),
                                onPressed: busy ? null : () => _removeVehicle(i),
                              ),
                            ),
                          );
                        }),
                      ],

                      const SizedBox(height: 40),

                      SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00897B),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15)),
                            elevation: 5,
                          ),
                          onPressed: busy ? null : _finishRegistration,
                          child: busy
                              ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5),
                          )
                              : const Text(
                            'FINISH REGISTRATION',
                            style: TextStyle(
                                fontSize: 16,
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
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

  Widget _buildUploadBox() {
    return GestureDetector(
      onTap: _isUploading ? null : _showPickerOptions,
      child: Container(
        height: 160,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _isLicenseVerified
                ? Colors.green.withOpacity(0.6)
                : Colors.teal.withOpacity(0.3),
            width: 2,
          ),
        ),
        child: _isUploading
            ? const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Color(0xFF00897B)),
              SizedBox(height: 10),
              Text('Verifying with server...',
                  style: TextStyle(color: Colors.grey)),
            ],
          ),
        )
            : _licenseImage != null
            ? Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.file(_licenseImage!,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity),
            ),
            Positioned(
              bottom: 8,
              right: 8,
              child: GestureDetector(
                onTap: _showPickerOptions,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00897B),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.edit,
                      color: Colors.white, size: 16),
                ),
              ),
            ),
          ],
        )
            : Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_a_photo_outlined,
                color: Colors.teal.withOpacity(0.5), size: 40),
            const SizedBox(height: 10),
            const Text('Upload license image',
                style: TextStyle(
                    color: Colors.teal,
                    fontWeight: FontWeight.w500)),
            const Text('Camera or gallery',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildVerificationBadge() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(
            _isLicenseVerified
                ? Icons.verified
                : _isUploading
                ? Icons.hourglass_top
                : Icons.warning_amber_rounded,
            color: _isLicenseVerified
                ? Colors.green
                : _isUploading
                ? Colors.orange
                : Colors.red,
            size: 18,
          ),
          const SizedBox(width: 6),
          Text(
            _isLicenseVerified
                ? 'License verified'
                : _isUploading
                ? 'Verifying...'
                : 'Verification failed — retake photo',
            style: TextStyle(
              fontSize: 12,
              color: _isLicenseVerified ? Colors.green : Colors.orange,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExtractedDataCard() {
    final data = _extractedLicenseData ?? {};
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.green.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('License details',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF00897B),
                  fontSize: 13)),
          const SizedBox(height: 10),
          if (data['license_number'] != null)
            _dataRow(Icons.credit_card, 'License No', data['license_number'].toString()),
          if (data['name'] != null)
            _dataRow(Icons.person_outline, 'Name', data['name'].toString()),
          if (data['expiry_date'] != null)
            _dataRow(Icons.calendar_today, 'Expiry', data['expiry_date'].toString()),
          if (data['blood_group'] != null)
            _dataRow(Icons.bloodtype_outlined, 'Blood Group', data['blood_group'].toString()),
        ],
      ),
    );
  }

  Widget _dataRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: const Color(0xFF00897B)),
          const SizedBox(width: 8),
          Text('$label: ',
              style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontWeight: FontWeight.w600)),
          Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF212121),
                      fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }

  void _showPickerOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Color(0xFF00897B)),
              title: const Text('Take a Photo'),
              onTap: () {
                Navigator.pop(context);
                _pickLicense(ImageSource.camera);
              },
            ),
            ListTile(
              leading:
              const Icon(Icons.photo_library, color: Color(0xFF00897B)),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickLicense(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransportDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(15),
      ),
      child: DropdownButtonFormField<String>(
        decoration: const InputDecoration(
          border: InputBorder.none,
          prefixIcon: Icon(Icons.commute_outlined, color: Color(0xFF00897B)),
        ),
        value: selectedTransport,
        hint: const Text('Select Mode Of Transport'),
        items: const [
          DropdownMenuItem(value: 'Car', child: Text('Car')),
          DropdownMenuItem(value: 'Bike', child: Text('Bike')),
        ],
        onChanged: (v) => setState(() => selectedTransport = v),
      ),
    );
  }

  Widget _buildVehicleField(
      IconData icon, String hint, TextEditingController controller) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: const Color(0xFF00897B)),
        hintText: hint,
        filled: true,
        fillColor: Colors.white.withOpacity(0.9),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide:
          const BorderSide(color: Color(0xFF00897B), width: 1.5),
        ),
      ),
    );
  }
}
