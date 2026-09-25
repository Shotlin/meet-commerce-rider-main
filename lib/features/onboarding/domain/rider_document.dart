/// The six rider verification document types required by the live
/// backend (R4.2).
///
/// `wire` is the path segment for `POST /delivery/documents/:type` and
/// is exactly the casing the backend's
/// [`DocumentType` schema](backend-contract.md) expects:
/// snake_case, lowercase. `displayName` is the user-facing label used
/// by the rider approval and upload screens.
///
/// Adding a new document type requires:
/// 1. A new enum value here.
/// 2. A `wire` mapping that matches the backend's accepted segment.
/// 3. A `displayName` for the UI.
enum RiderDocumentType {
  /// Profile photo of the rider.
  photo,

  /// Driving licence.
  drivingLicense,

  /// Aadhaar (front side).
  aadharFront,

  /// Aadhaar (back side).
  aadharBack,

  /// Vehicle registration certificate.
  vehicleRc,

  /// Permanent account number card.
  panCard;

  /// Backend wire string for the `:type` segment of the document
  /// upload endpoint. Must match the `rider_documents.doc_type` CHECK
  /// constraint: 'aadhaar', 'license', 'vehicle_rc', 'pan', 'photo', 'bank_proof'.
  String get wire {
    switch (this) {
      case RiderDocumentType.photo:
        return 'photo';
      case RiderDocumentType.drivingLicense:
        return 'license'; // backend: 'license' (not 'driving_license')
      case RiderDocumentType.aadharFront:
        return 'aadhaar'; // backend combines front+back as 'aadhaar'
      case RiderDocumentType.aadharBack:
        return 'aadhaar_back'; // stored separately for UI but same backend type
      case RiderDocumentType.vehicleRc:
        return 'vehicle_rc';
      case RiderDocumentType.panCard:
        return 'pan'; // backend: 'pan' (not 'pan_card')
    }
  }

  /// Display label rendered on the approval checklist and the upload
  /// screen header.
  String get displayName {
    switch (this) {
      case RiderDocumentType.photo:
        return 'Profile photo';
      case RiderDocumentType.drivingLicense:
        return 'Driving license';
      case RiderDocumentType.aadharFront:
        return 'Aadhaar front';
      case RiderDocumentType.aadharBack:
        return 'Aadhaar back';
      case RiderDocumentType.vehicleRc:
        return 'Vehicle RC';
      case RiderDocumentType.panCard:
        return 'PAN card';
    }
  }

  /// Parses a backend [wire] string into a [RiderDocumentType].
  /// Handles both the backend's stored values and legacy aliases.
  static RiderDocumentType? fromWire(String? wire) {
    if (wire == null) return null;
    switch (wire.toLowerCase().trim()) {
      case 'photo':
        return RiderDocumentType.photo;
      case 'license':
      case 'driving_license': // legacy alias
        return RiderDocumentType.drivingLicense;
      case 'aadhaar':
      case 'aadhar_front': // legacy alias
        return RiderDocumentType.aadharFront;
      case 'aadhaar_back':
      case 'aadhar_back': // legacy alias
        return RiderDocumentType.aadharBack;
      case 'vehicle_rc':
        return RiderDocumentType.vehicleRc;
      case 'pan':
      case 'pan_card': // legacy alias
        return RiderDocumentType.panCard;
    }
    return null;
  }
}

/// Approval status of a single rider document (R4.2).
///
/// `missing` is the state reported by the rider approval screen for
/// documents that have not been uploaded yet (the backend simply
/// omits them from `data.documents`). The other three values mirror
/// the live backend's `PENDING` / `APPROVED` / `REJECTED` strings.
enum RiderDocumentStatus {
  /// Not yet uploaded.
  missing,

  /// Uploaded; awaiting review.
  pending,

  /// Reviewed and approved.
  approved,

  /// Reviewed and rejected; the rider must re-upload.
  rejected;

  /// Maps a raw backend status string to a [RiderDocumentStatus].
  ///
  /// Tolerates any casing the backend might emit (the live backend
  /// uses upper-case `PENDING` / `APPROVED` / `REJECTED`, but mixed
  /// casings have been observed during deploys, so we normalise via
  /// [String.toUpperCase]).
  ///
  /// Unknown values, an empty string, and `null` all map to
  /// [missing] — that is the safe default for the approval checklist
  /// because it presents the document as "not yet uploaded" rather
  /// than misrepresenting an unknown status as approved or pending.
  static RiderDocumentStatus parse(String? raw) {
    final String? normalised = raw?.toUpperCase().trim();
    if (normalised == null || normalised.isEmpty) {
      return RiderDocumentStatus.missing;
    }
    switch (normalised) {
      case 'PENDING':
        return RiderDocumentStatus.pending;
      case 'APPROVED':
        return RiderDocumentStatus.approved;
      case 'REJECTED':
        return RiderDocumentStatus.rejected;
      case 'MISSING':
        return RiderDocumentStatus.missing;
      default:
        return RiderDocumentStatus.missing;
    }
  }
}

/// Immutable representation of a single rider verification document.
///
/// The model is the boundary between the network layer (raw JSON
/// maps) and the application/UI layer (typed [RiderDocumentType] /
/// [RiderDocumentStatus] values). [fromJson] is deliberately lenient:
/// it accepts both `type`/`document_type`, both `url`/`document_url`,
/// and both camelCase and snake_case timestamp keys so minor backend
/// shape variations don't break the rider approval screen.
class RiderDocument {
  /// Constructs a [RiderDocument] explicitly.
  const RiderDocument({
    required this.type,
    required this.status,
    this.url,
    this.uploadedAt,
    this.rejectionReason,
  });

  /// Builds a [RiderDocument] from a backend JSON map.
  ///
  /// Tolerates:
  /// - `type` or `document_type` for the type wire string.
  /// - `status` or `document_status` for the approval state.
  /// - `url` or `document_url` for the CDN URL.
  /// - `uploaded_at` or `uploadedAt` for the upload timestamp; parsed
  ///   into a [DateTime] when the value is a valid ISO-8601 string.
  /// - `rejection_reason` or `rejectionReason` for the rejection note.
  ///
  /// Throws a [FormatException] when the `type` field is missing or
  /// resolves to an unknown wire string. Status defaults to
  /// [RiderDocumentStatus.missing] when absent.
  factory RiderDocument.fromJson(Map<String, dynamic> json) {
    final String? typeWire =
        (json['type'] as String?) ?? (json['document_type'] as String?);
    final RiderDocumentType? type = RiderDocumentType.fromWire(typeWire);
    if (type == null) {
      throw FormatException(
        'RiderDocument.fromJson: unknown document type "$typeWire"',
      );
    }

    final String? statusRaw =
        (json['status'] as String?) ?? (json['document_status'] as String?);
    final RiderDocumentStatus status = RiderDocumentStatus.parse(statusRaw);

    final String? url =
        (json['url'] as String?) ?? (json['document_url'] as String?);

    final String? uploadedAtRaw =
        (json['uploadedAt'] as String?) ?? (json['uploaded_at'] as String?);
    final DateTime? uploadedAt = uploadedAtRaw != null
        ? DateTime.tryParse(uploadedAtRaw)
        : null;

    final String? rejectionReason =
        (json['rejectionReason'] as String?) ??
        (json['rejection_reason'] as String?);

    return RiderDocument(
      type: type,
      status: status,
      url: url,
      uploadedAt: uploadedAt,
      rejectionReason: rejectionReason,
    );
  }

  /// Document type.
  final RiderDocumentType type;

  /// Current approval status.
  final RiderDocumentStatus status;

  /// CDN URL of the uploaded document, if any.
  final String? url;

  /// Upload timestamp, if any.
  final DateTime? uploadedAt;

  /// Reviewer note when the document is [RiderDocumentStatus.rejected].
  final String? rejectionReason;

  /// Returns a copy of this document with the given fields replaced.
  RiderDocument copyWith({
    RiderDocumentType? type,
    RiderDocumentStatus? status,
    String? url,
    DateTime? uploadedAt,
    String? rejectionReason,
  }) {
    return RiderDocument(
      type: type ?? this.type,
      status: status ?? this.status,
      url: url ?? this.url,
      uploadedAt: uploadedAt ?? this.uploadedAt,
      rejectionReason: rejectionReason ?? this.rejectionReason,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RiderDocument &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          status == other.status &&
          url == other.url &&
          uploadedAt == other.uploadedAt &&
          rejectionReason == other.rejectionReason;

  @override
  int get hashCode =>
      Object.hash(type, status, url, uploadedAt, rejectionReason);

  @override
  String toString() =>
      'RiderDocument(type: ${type.wire}, status: $status, url: $url)';
}
