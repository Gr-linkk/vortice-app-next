import 'dart:typed_data';

import 'package:flutter/material.dart';

class ServiceRequestFormPhotoField extends StatelessWidget {
  const ServiceRequestFormPhotoField({
    super.key,
    required this.photos,
    required this.onAddPhotos,
    required this.onTakePhoto,
    required this.onRemovePhoto,
  });

  final List<Uint8List> photos;
  final Future<void> Function() onAddPhotos;
  final Future<void> Function() onTakePhoto;
  final ValueChanged<int> onRemovePhoto;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onAddPhotos,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Gallery'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onTakePhoto,
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Camera'),
              ),
            ),
          ],
        ),
        if (photos.isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 88,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: photos.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) => Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(
                      photos[index],
                      width: 88,
                      height: 88,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: InkWell(
                      onTap: () => onRemovePhoto(index),
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(4),
                        child: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
