import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/session_model.dart';
import '../core/aspiration_outcome.dart';
import 'image_zoom_dialog.dart';

// Brand colors matching BRANDING.md
const Color _navy        = Color(0xFF003366);
const Color _cardBg      = Color(0xFFFFFFFF);
const Color _cardBorder  = Color(0xFFE2EAF4);
const Color _textDark    = Color(0xFF1A2B3C);
const Color _textMid     = Color(0xFF4A5568);
const Color _textLight   = Color(0xFF8A9BB0);
const Color _green       = Color(0xFF1A7A4A);
const Color _placeholderBg = Color(0xFFF1F5F9);

class SnapshotEvidencePanel extends StatelessWidget {
  final SessionModel session;

  const SnapshotEvidencePanel({
    super.key,
    required this.session,
  });

  @override
  Widget build(BuildContext context) {
    final galleryItems = <SnapshotImageItem>[
      if (session.insertionImageBase64 != null && session.insertionImageBase64!.isNotEmpty)
        SnapshotImageItem(title: 'Insertion', base64Image: session.insertionImageBase64!),
      if (session.aspirationImageBase64 != null && session.aspirationImageBase64!.isNotEmpty)
        SnapshotImageItem(title: 'Aspiration', base64Image: session.aspirationImageBase64!),
      if (session.withdrawalImageBase64 != null && session.withdrawalImageBase64!.isNotEmpty)
        SnapshotImageItem(title: 'Withdrawal', base64Image: session.withdrawalImageBase64!),
    ];

    final outcome = AspirationOutcome.parse(session.aspirationResult);
    final stabilityText = session.aspirationAngleDrift != null
        ? '±${session.aspirationAngleDrift!.toStringAsFixed(1)}°'
        : 'Not measured';
    final target = 90.0;
    final deviation = (session.insertionAngle - target).abs();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 1. Insertion Card ──
          SnapshotCard(
            key: const Key('snapshot_card_insertion'),
            title: 'Insertion',
            base64Image: session.insertionImageBase64,
            onTap: () {
              final idx = galleryItems.indexWhere((i) => i.title == 'Insertion');
              if (idx != -1) {
                showImageGalleryDialog(context, items: galleryItems, initialIndex: idx);
              }
            },
            metrics: [
              _buildMetricRow('Measured Angle', '${session.insertionAngle.toStringAsFixed(1)}°'),
              _buildMetricRow('Target Angle', '${target.toStringAsFixed(0)}°'),
              _buildMetricRow('Deviation', '${deviation.toStringAsFixed(1)}°'),
            ],
            score: session.insertionScore,
          ),

          // ── 2. Aspiration Card ──
          SnapshotCard(
            key: const Key('snapshot_card_aspiration'),
            title: 'Aspiration',
            base64Image: session.aspirationImageBase64,
            onTap: () {
              final idx = galleryItems.indexWhere((i) => i.title == 'Aspiration');
              if (idx != -1) {
                showImageGalleryDialog(context, items: galleryItems, initialIndex: idx);
              }
            },
            metrics: [
              _buildMetricRow(
                'Instructor blood check',
                outcome.label,
                valueColor: outcome == AspirationOutcome.noBleeding ? _green : null,
              ),
              _buildMetricRow('Aspiration time', '${session.aspirationDuration.toStringAsFixed(1)}s'),
              _buildMetricRow('Needle stability', stabilityText),
            ],
            score: session.aspirationScore,
          ),

          // ── 3. Withdrawal Card ──
          SnapshotCard(
            key: const Key('snapshot_card_withdrawal'),
            title: 'Withdrawal',
            base64Image: session.withdrawalImageBase64,
            onTap: () {
              final idx = galleryItems.indexWhere((i) => i.title == 'Withdrawal');
              if (idx != -1) {
                showImageGalleryDialog(context, items: galleryItems, initialIndex: idx);
              }
            },
            metrics: [
              _buildMetricRow('Withdrawal Angle', '${session.withdrawalAngle.toStringAsFixed(1)}°'),
              _buildMetricRow('Angular Delta', '${session.angularDelta.toStringAsFixed(1)}°'),
              _buildMetricRow(
                'Correspondence',
                session.correspondenceResult,
                valueColor: session.correspondenceResult == 'Matches' ? _green : null,
              ),
            ],
            score: session.withdrawalScore,
          ),
        ],
      ),
    );
  }

  static Widget _buildMetricRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              style: const TextStyle(color: _textMid, fontSize: 11, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? _textDark,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class SnapshotCard extends StatelessWidget {
  final String title;
  final String? base64Image;
  final VoidCallback? onTap;
  final List<Widget> metrics;
  final int score;

  const SnapshotCard({
    super.key,
    required this.title,
    this.base64Image,
    this.onTap,
    this.metrics = const [],
    this.score = 5,
  });

  @override
  Widget build(BuildContext context) {
    final bool hasImage = base64Image != null && base64Image!.isNotEmpty;

    return Container(
      width: 220,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(14),
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
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasImage)
            GestureDetector(
              onTap: onTap,
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                    child: AspectRatio(
                      aspectRatio: 4 / 3,
                      child: Image.memory(
                        base64Decode(base64Image!),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            _buildPlaceholder(),
                      ),
                    ),
                  ),
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
            )
          else
            _buildPlaceholder(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _textDark,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (metrics.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ...metrics,
                ],
                const SizedBox(height: 8),
                Container(height: 1, color: _cardBorder),
                const SizedBox(height: 8),
                _buildScoreRow(score),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildPlaceholder() {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: Container(
          color: _placeholderBg,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(
                Icons.no_photography_outlined,
                color: _textLight,
                size: 32,
              ),
              SizedBox(height: 6),
              Text(
                'Snapshot not captured',
                style: TextStyle(
                  color: _textMid,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildScoreRow(int score) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'Score',
          style: TextStyle(color: _textDark, fontSize: 12, fontWeight: FontWeight.w700),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(5, (i) => Container(
                width: 7, height: 7,
                margin: const EdgeInsets.only(right: 2),
                decoration: BoxDecoration(
                  color: i < score ? _navy : _cardBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              )),
            ),
            const SizedBox(width: 4),
            Text(
              '$score / 5',
              style: const TextStyle(color: _navy, fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ],
    );
  }
}
