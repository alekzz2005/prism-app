import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/session_model.dart';
import 'image_zoom_dialog.dart';

// Brand colors matching BRANDING.md
const Color _navy = Color(0xFF003366);
const Color _cardBg = Color(0xFFFFFFFF);
const Color _cardBorder = Color(0xFFE2EAF4);
const Color _textDark = Color(0xFF1A2B3C);
const Color _textLight = Color(0xFF8A9BB0);

class SnapshotEvidencePanel extends StatelessWidget {
  final SessionModel session;

  const SnapshotEvidencePanel({
    super.key,
    required this.session,
  });

  @override
  Widget build(BuildContext context) {
    final items = <SnapshotImageItem>[
      if (session.insertionImageBase64 != null)
        SnapshotImageItem(title: 'Insertion', base64Image: session.insertionImageBase64!),
      if (session.aspirationImageBase64 != null)
        SnapshotImageItem(title: 'Aspiration', base64Image: session.aspirationImageBase64!),
      if (session.withdrawalImageBase64 != null)
        SnapshotImageItem(title: 'Withdrawal', base64Image: session.withdrawalImageBase64!),
    ];

    if (items.isEmpty) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: items.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          return SnapshotCard(
            title: item.title,
            base64Image: item.base64Image,
            onTap: () => showImageGalleryDialog(
              context,
              items: items,
              initialIndex: index,
            ),
          );
        }).toList(),
      ),
    );
  }
}

class SnapshotCard extends StatelessWidget {
  final String title;
  final String base64Image;
  final VoidCallback onTap;

  const SnapshotCard({
    super.key,
    required this.title,
    required this.base64Image,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        width: 140,
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _cardBorder),
          boxShadow: [
            BoxShadow(
              color: _navy.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                  child: AspectRatio(
                    aspectRatio: 3 / 4,
                    child: Image.memory(
                      base64Decode(base64Image),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const Center(child: Icon(Icons.broken_image, color: _textLight)),
                    ),
                  ),
                ),
                // Zoom icon badge overlay on preview image
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.zoom_in_rounded, color: Colors.white, size: 14),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _textDark, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
