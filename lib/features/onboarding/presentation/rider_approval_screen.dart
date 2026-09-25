import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/status_chip.dart';
import '../../auth/application/session_controller.dart';
import '../application/documents_controller.dart';
import '../domain/rider_document.dart';
import 'document_upload_screen.dart';

/// Verification-pending screen shown when the rider profile is not
/// `is_approved`.
///
/// Displays:
/// - An approval status chip (pending / approved).
/// - A checklist of all 6 required document types with their status.
/// - Each document row is tappable to open [DocumentUploadScreen].
/// - A "Check approval status" button that re-fetches the profile.
/// - A logout button.
class RiderApprovalScreen extends ConsumerStatefulWidget {
  /// Const constructor so the route can use `const RiderApprovalScreen()`.
  const RiderApprovalScreen({super.key});

  @override
  ConsumerState<RiderApprovalScreen> createState() =>
      _RiderApprovalScreenState();
}

class _RiderApprovalScreenState extends ConsumerState<RiderApprovalScreen> {
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    // Kick off the initial documents fetch the first time the screen
    // mounts; subsequent rebuilds reuse the controller's cached state.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read<DocumentsController>(documentsControllerProvider).refresh();
    });
  }

  Future<void> _onRefresh() async {
    setState(() => _refreshing = true);
    // Re-fetch profile (may redirect to home if now approved).
    await ref.read<SessionController>(sessionControllerProvider).restore();
    // Also refresh documents.
    if (mounted) {
      await ref
          .read<DocumentsController>(documentsControllerProvider)
          .refresh();
    }
    if (!mounted) return;
    setState(() => _refreshing = false);
  }

  Future<void> _onLogout() async {
    await ref.read<SessionController>(sessionControllerProvider).logout();
    if (!mounted) return;
    context.go(AppRoutes.login);
  }

  Future<void> _onDocumentRowTap(RiderDocumentType type) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => DocumentUploadScreen(type: type)),
    );
    // The controller refreshes on its own after a successful upload;
    // back-button cancellation requires no extra handling here.
  }

  /// Builds a stable list of all six document rows by overlaying the
  /// backend-reported documents on top of the canonical
  /// [RiderDocumentType] enum. Anything the backend hasn't returned is
  /// shown as `missing`.
  List<RiderDocument> _allRows(List<RiderDocument> backendDocs) {
    final Map<RiderDocumentType, RiderDocument> byType =
        <RiderDocumentType, RiderDocument>{
          for (final RiderDocument doc in backendDocs) doc.type: doc,
        };
    return <RiderDocument>[
      for (final RiderDocumentType t in RiderDocumentType.values)
        byType[t] ??
            RiderDocument(type: t, status: RiderDocumentStatus.missing),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final SessionController session = ref.watch<SessionController>(
      sessionControllerProvider,
    );
    final DocumentsController docsCtrl = ref.watch<DocumentsController>(
      documentsControllerProvider,
    );

    final user = session.state.user;
    final bool isApproved = session.state.isApproved;
    final List<RiderDocument> documents = _allRows(docsCtrl.documents);
    final bool docsLoading = docsCtrl.isLoading;

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        title: Text(
          'Verification',
          style: AppTypography.heading.copyWith(color: AppColors.charcoal),
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.logout, color: AppColors.charcoal),
            onPressed: _onLogout,
            tooltip: 'Log out',
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Status chip
              Row(
                children: <Widget>[
                  StatusChip(
                    label: isApproved ? 'Approved' : 'Pending approval',
                    tone: isApproved ? StatusTone.success : StatusTone.pending,
                  ),
                ],
              ),
              const SizedBox(height: AppDimensions.xl),

              // Greeting
              Text(
                'Hi ${user?.name ?? 'there'},',
                style: AppTypography.title.copyWith(color: AppColors.charcoal),
              ),
              const SizedBox(height: AppDimensions.xs),
              Text(
                isApproved
                    ? 'Your profile has been approved. You can now go online.'
                    : 'Upload the required documents below. Once verified, '
                          'you will be able to go online and receive orders.',
                style: AppTypography.body.copyWith(color: AppColors.muted),
              ),
              const SizedBox(height: 24),

              // Document checklist heading
              Text(
                'REQUIRED DOCUMENTS',
                style: AppTypography.micro.copyWith(color: AppColors.muted),
              ),
              const SizedBox(height: 8),

              // Document checklist — one bordered card, each row a single
              // design-§8 state (design: "vertical progress pattern").
              Expanded(
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(
                      AppDimensions.cardRadius,
                    ),
                    border: Border.all(color: AppColors.border),
                  ),
                  child:
                      docsLoading &&
                          documents.every(
                            (RiderDocument d) =>
                                d.status == RiderDocumentStatus.missing,
                          )
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.brand,
                            strokeWidth: 2,
                          ),
                        )
                      : ListView.separated(
                          itemCount: documents.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1, color: AppColors.border),
                          itemBuilder: (BuildContext context, int index) {
                            return _DocumentRow(
                              document: documents[index],
                              onTap: () =>
                                  _onDocumentRowTap(documents[index].type),
                            );
                          },
                        ),
                ),
              ),
              const SizedBox(height: 16),

              // Check approval status button
              AppButton(
                label: _refreshing ? 'Refreshing…' : 'Check approval status',
                isLoading: _refreshing,
                onPressed: _refreshing ? null : _onRefresh,
              ),
              const SizedBox(height: 12),

              // Logout button
              AppButton(
                label: 'Log out',
                variant: AppButtonVariant.secondary,
                onPressed: _onLogout,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A single row in the document checklist.
class _DocumentRow extends StatelessWidget {
  const _DocumentRow({required this.document, required this.onTap});

  final RiderDocument document;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String label = document.type.displayName;
    final _DocStyle style = _styleFor(document.status);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: <Widget>[
            // Status indicator dot
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: style.dotColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 14),

            // Document name + reviewer reason (matrix: "rejected document
            // shows reason and supports resubmit" — the reason renders
            // right on the row, and the row opens the upload screen where
            // the rider resubmits).
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    label,
                    style: AppTypography.body.copyWith(
                      color: AppColors.charcoal,
                    ),
                  ),
                  if (document.status == RiderDocumentStatus.rejected &&
                      (document.rejectionReason ?? '').isNotEmpty) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      document.rejectionReason!,
                      style: AppTypography.micro.copyWith(
                        color: AppColors.danger,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Status chip
            StatusChip(
              label: style.chipLabel,
              tone: style.tone,
              showDot: false,
            ),
            const SizedBox(width: 8),

            // Chevron
            const Icon(Icons.chevron_right, color: AppColors.muted, size: 20),
          ],
        ),
      ),
    );
  }

  static _DocStyle _styleFor(RiderDocumentStatus status) {
    // Design §8 state language mapped onto the backend's four signals:
    // missing → "Not started", pending → "Submitted", approved →
    // "Approved", rejected → "Needs correction". (The design's fifth
    // state, "Incomplete", has no backend signal and is not modelled.)
    switch (status) {
      case RiderDocumentStatus.approved:
        return const _DocStyle(
          dotColor: AppColors.success,
          chipLabel: 'Approved',
          tone: StatusTone.success,
        );
      case RiderDocumentStatus.pending:
        return const _DocStyle(
          dotColor: AppColors.warning,
          chipLabel: 'Submitted',
          tone: StatusTone.pending,
        );
      case RiderDocumentStatus.rejected:
        return const _DocStyle(
          dotColor: AppColors.danger,
          chipLabel: 'Needs correction',
          tone: StatusTone.danger,
        );
      case RiderDocumentStatus.missing:
        return const _DocStyle(
          dotColor: AppColors.muted,
          chipLabel: 'Not started',
          tone: StatusTone.neutral,
        );
    }
  }
}

class _DocStyle {
  const _DocStyle({
    required this.dotColor,
    required this.chipLabel,
    required this.tone,
  });

  final Color dotColor;
  final String chipLabel;
  final StatusTone tone;
}
