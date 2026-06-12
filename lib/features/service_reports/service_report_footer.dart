import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:vortice_app/features/service_reports/service_report_media_section.dart';

class ServiceReportFormFooter extends StatelessWidget {
  final List<Uint8List> photos;
  final VoidCallback onPickGallery;
  final VoidCallback onTakeCamera;
  final ValueChanged<int> onRemovePhoto;

  const ServiceReportFormFooter({
    super.key,
    required this.photos,
    required this.onPickGallery,
    required this.onTakeCamera,
    required this.onRemovePhoto,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ServiceReportMediaSection(
          photos: photos,
          onPickGallery: onPickGallery,
          onTakeCamera: onTakeCamera,
          onRemovePhoto: onRemovePhoto,
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
