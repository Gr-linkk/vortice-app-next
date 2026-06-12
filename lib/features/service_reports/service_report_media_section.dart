import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/service_reports/service_report_form_sections.dart';
import 'package:vortice_app/l10n/app_localizations.dart';

Future<Uint8List?> pickServiceReportGalleryPhoto(ImagePicker picker) async {
  final pickedFile = await picker.pickImage(
    source: ImageSource.gallery,
    maxWidth: 1920,
    maxHeight: 1080,
    imageQuality: 85,
  );
  if (pickedFile == null) return null;
  return pickedFile.readAsBytes();
}

Future<Uint8List?> takeServiceReportCameraPhoto(ImagePicker picker) async {
  final pickedFile = await picker.pickImage(
    source: ImageSource.camera,
    maxWidth: 1920,
    maxHeight: 1080,
    imageQuality: 85,
  );
  if (pickedFile == null) return null;
  return pickedFile.readAsBytes();
}

class ServiceReportMediaSection extends StatelessWidget {
  final List<Uint8List> photos;
  final VoidCallback onPickGallery;
  final VoidCallback onTakeCamera;
  final ValueChanged<int> onRemovePhoto;

  const ServiceReportMediaSection({
    super.key,
    required this.photos,
    required this.onPickGallery,
    required this.onTakeCamera,
    required this.onRemovePhoto,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ServiceReportSectionHeader(
          title: l10n.serviceReportPhotos,
          subtitle: l10n.serviceReportPhotosHint,
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: onPickGallery,
              icon: const Icon(Icons.photo_library, size: 18),
              label: const Text('Gallery'),
            ),
            OutlinedButton.icon(
              onPressed: onTakeCamera,
              icon: const Icon(Icons.camera_alt, size: 18),
              label: const Text('Camera'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (photos.isNotEmpty) ...[
          SizedBox(
            height: 100,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: photos.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        photos[i],
                        width: 100,
                        height: 100,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: () => onRemovePhoto(i),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: AppColors.error,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}
