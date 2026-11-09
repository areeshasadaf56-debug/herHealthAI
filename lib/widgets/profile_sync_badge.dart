import 'package:flutter/material.dart' hide Text;
import '../services/health_profile_service.dart';
import '../theme/app_theme.dart';
import '../l10n/app_text.dart';

/// A tiny, honest sync indicator for the Health Diary (SRS FR-79):
/// invisible when everything is synced, a soft "Saving…" row while a
/// change is queued, and a persistent retry row when the upload failed.
/// The actual data is always on this device first, so "failed" never
/// means lost.
class ProfileSyncBadge extends StatelessWidget {
  const ProfileSyncBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ProfileSyncState>(
      valueListenable: HealthProfileService().syncState,
      builder: (context, state, _) {
        if (state == ProfileSyncState.synced) return const SizedBox.shrink();

        final failed = state == ProfileSyncState.failed;
        final service = HealthProfileService();
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(
            children: [
              Icon(
                failed ? Icons.cloud_off_rounded : Icons.cloud_upload_rounded,
                size: 15,
                color: failed ? AppColors.periodRed : AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  failed
                      ? (service.lastSyncError ??
                            'Saved on this device — will sync when online.')
                      : 'Saving…',
                  style: AppTextStyles.sans(
                    size: 11.5,
                    color: failed
                        ? AppColors.periodRed
                        : AppColors.textSecondary,
                  ),
                ),
              ),
              if (failed)
                GestureDetector(
                  onTap: () => service.retryPendingSync(),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      'Retry',
                      style: AppTextStyles.sans(
                        size: 11.5,
                        weight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
