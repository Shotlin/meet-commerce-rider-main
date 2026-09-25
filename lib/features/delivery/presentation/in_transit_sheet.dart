import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart' as ul;

import '../../../core/config/env.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/external_nav_launcher.dart';
import '../../../shared/widgets/app_button.dart';
import '../application/active_delivery_controller.dart';
import '../data/delivery_api.dart' show CancelDeliveryReason;
import '../domain/collected_payment.dart';
import '../domain/delivery_address.dart';
import '../domain/delivery_order.dart';
import '../domain/delivery_outcome.dart';
import 'cancel_delivery_sheet.dart';
import 'collect_payment_sheet.dart';
import 'delivery_details_sheet.dart';
import 'demo_complete_sheet.dart';

/// The in-transit delivery card (design §13 bottom delivery card):
/// customer name, address/landmark, payment badge, **COD amount due**
/// when applicable and uncollected, rider-visible **delivery notes**,
/// call/navigate actions, and the primary `Deliver` workflow button.
/// A `Delivery details` entry opens the expanded sheet with the item
/// list, notes, and both addresses (design §13 swipe-up surface).
class InTransitSheet extends ConsumerWidget {
  /// Constructs the in-transit delivery card.
  const InTransitSheet({required this.order, super.key});

  final DeliveryOrder order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DeliveryAddress addr = order.customerAddress;
    final bool showDemo = ref.watch<Env>(envProvider).enableDevAffordances;
    final ActiveDeliveryController deliveryController = ref
        .watch<ActiveDeliveryController>(activeDeliveryControllerProvider);
    final bool isCod = order.paymentMethod.toUpperCase() == 'COD';
    final CollectedPayment? collected = deliveryController.collectedPaymentFor(
      order.orderId,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AddressCard(
            tag: 'Drop',
            title: addr.name.isEmpty ? addr.address : addr.name,
            subtitle: addr.landmark != null && addr.landmark!.isNotEmpty
                ? '${addr.address} • ${addr.landmark}'
                : addr.address,
            paymentMethod: order.paymentMethod,
          ),
          // Design §13: "COD amount due if applicable" — the exact
          // customer amount the rider must collect, carried by the same
          // card (colour alone never carries it: icon + label too).
          if (isCod && collected == null) ...<Widget>[
            const SizedBox(height: 8),
            _CodDueChip(amount: order.totalAmount),
          ],
          if (_hasNotes) ...<Widget>[
            const SizedBox(height: 8),
            _NotesStrip(
              notes: <String>[
                ?order.deliveryNotes,
                ?order.deliveryInstructions,
              ],
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              if (addr.phone != null && addr.phone!.isNotEmpty) ...<Widget>[
                Expanded(
                  child: AppButton(
                    label: 'Call customer',
                    variant: AppButtonVariant.secondary,
                    leadingIcon: Icons.call_outlined,
                    onPressed: () => _onCall(ref, addr.phone!),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: AppButton(
                  label: 'Navigate',
                  variant: AppButtonVariant.secondary,
                  leadingIcon: Icons.navigation_outlined,
                  onPressed: addr.lat != null && addr.lng != null
                      ? () => _onNavigate(ref, addr.lat!, addr.lng!)
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AppButton(
            label: 'Delivery details',
            variant: AppButtonVariant.secondary,
            leadingIcon: Icons.receipt_long_outlined,
            onPressed: () => unawaited(_onShowDetails(context)),
          ),
          if (isCod) ...<Widget>[
            const SizedBox(height: 8),
            AppButton(
              label: collected == null
                  ? 'Collect payment'
                  : 'Payment collected · Edit',
              variant: collected == null
                  ? AppButtonVariant.primary
                  : AppButtonVariant.secondary,
              leadingIcon: collected == null
                  ? Icons.qr_code_outlined
                  : Icons.check_circle_outline,
              onPressed: () => _onCollectPayment(context, ref),
            ),
          ],
          const SizedBox(height: 8),
          AppButton(
            label: 'Deliver',
            onPressed: (!isCod || collected != null)
                ? () => _onDeliver(context, collected, ref)
                : null,
          ),
          if (showDemo) ...<Widget>[
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => _onDemoComplete(context, ref),
              child: Text(
                'Demo complete',
                style: AppTypography.label.copyWith(color: AppColors.muted),
              ),
            ),
          ],
          const SizedBox(height: 4),
          TextButton(
            onPressed: () => _onCancelDelivery(context, ref),
            child: Text(
              'Cancel delivery',
              style: AppTypography.label.copyWith(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
  }

  bool get _hasNotes =>
      (order.deliveryNotes != null && order.deliveryNotes!.isNotEmpty) ||
      (order.deliveryInstructions != null &&
          order.deliveryInstructions!.isNotEmpty);

  Future<void> _onShowDetails(BuildContext context) async {
    await showDeliveryDetailsSheet(context, order);
  }

  Future<void> _onNavigate(WidgetRef ref, double lat, double lng) async {
    final ExternalNavigationLauncher launcher = ref
        .read<ExternalNavigationLauncher>(externalNavLauncherProvider);
    await launcher.openDrivingDirections(destLat: lat, destLng: lng);
  }

  Future<void> _onCall(WidgetRef ref, String phone) async {
    final UrlLauncherDelegate launcher = ref.read<UrlLauncherDelegate>(
      urlLauncherDelegateProvider,
    );
    final Uri uri = Uri(scheme: 'tel', path: phone);
    if (await launcher.canLaunch(uri)) {
      await launcher.launch(uri, mode: ul.LaunchMode.externalApplication);
    }
  }

  Future<void> _onCollectPayment(BuildContext context, WidgetRef ref) async {
    final CollectedPayment? payment = await showCollectPaymentSheet(
      context,
      order,
    );
    if (payment == null) return;
    ref
        .read<ActiveDeliveryController>(activeDeliveryControllerProvider)
        .recordCollectedPayment(order.orderId, payment);
  }

  Future<void> _onDeliver(
    BuildContext context,
    CollectedPayment? collected,
    WidgetRef ref,
  ) async {
    final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(
      context,
    );

    final DeliveryResult result = await ref
        .read<ActiveDeliveryController>(activeDeliveryControllerProvider)
        .deliverDirect(
          order.orderId,
          cashCollected: collected?.cashCollected,
          upiCollected: collected?.upiCollected,
        );
    switch (result) {
      case DeliveryResultSuccess():
        return;
      case DeliveryResultStale(message: final String message):
      case DeliveryResultFailure(message: final String message):
      case DeliveryResultInvalidOtp(message: final String message):
      case DeliveryResultOtpExpired(message: final String message):
      case DeliveryResultProofFailed(message: final String message):
        messenger?.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _onDemoComplete(BuildContext context, WidgetRef ref) async {
    final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(
      context,
    );
    final Env env = ref.read<Env>(envProvider);
    final DeliveryOutcome outcome = await showDemoCompleteSheet(
      context,
      order,
      env: env,
    );
    switch (outcome) {
      case DeliveryOutcomeDelivered():
      case DeliveryOutcomeCancelled():
        return;
      case DeliveryOutcomeFailed(message: final String message):
        messenger?.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _onCancelDelivery(BuildContext context, WidgetRef ref) async {
    final CancelDeliveryReason? reason = await showCancelDeliverySheet(context);
    if (reason == null) return;
    if (!context.mounted) return;

    final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(
      context,
    );
    final ActiveDeliveryController controller = ref
        .read<ActiveDeliveryController>(activeDeliveryControllerProvider);
    final bool cancelled = await controller.cancelDelivery(
      order.orderId,
      reason.wire,
    );
    if (!cancelled) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('Could not cancel delivery. Try again')),
      );
    }
  }
}

/// Amber "collect ₹X on delivery" chip — the §13 COD amount due. Amber
/// (warning) per design §23 "COD Due", with icon + label so colour is
/// never the only signal.
class _CodDueChip extends StatelessWidget {
  const _CodDueChip({required this.amount});

  final double amount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.warningSoft,
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.currency_rupee_outlined,
            size: 18,
            color: AppColors.warning,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Collect ₹${amount.toStringAsFixed(0)} on delivery',
              style: AppTypography.label.copyWith(color: AppColors.charcoal),
            ),
          ),
        ],
      ),
    );
  }
}

/// Calm amber strip carrying the customer's delivery notes /
/// instructions (design §13 bottom card: address/notes).
class _NotesStrip extends StatelessWidget {
  const _NotesStrip({required this.notes});

  final List<String> notes;

  @override
  Widget build(BuildContext context) {
    final String text = notes.join(' · ');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.offWhite,
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.sticky_note_2_outlined,
            size: 16,
            color: AppColors.muted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: AppTypography.micro.copyWith(color: AppColors.charcoal),
            ),
          ),
        ],
      ),
    );
  }
}

/// Address card shared by the pickup (accepted) and drop (in-transit)
/// delivery cards.
class AddressCard extends StatelessWidget {
  /// Constructs the address card.
  const AddressCard({
    required this.tag,
    required this.title,
    required this.subtitle,
    this.paymentMethod,
    super.key,
  });

  final String tag;
  final String title;
  final String subtitle;
  final String? paymentMethod;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  tag,
                  style: AppTypography.micro.copyWith(color: AppColors.muted),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: AppTypography.label.copyWith(color: AppColors.charcoal),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTypography.micro.copyWith(color: AppColors.muted),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (paymentMethod != null) ...<Widget>[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.offWhite,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                paymentMethod!,
                style: AppTypography.micro.copyWith(color: AppColors.charcoal),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
