class DeliveryDestination {
  final String deliveryId;
  final String deliveryName;
  final double latitude;
  final double longitude;
  final String? label;
  final String? assignedBy;
  final DateTime assignedAt;

  const DeliveryDestination({
    required this.deliveryId,
    required this.deliveryName,
    required this.latitude,
    required this.longitude,
    required this.assignedAt,
    this.label,
    this.assignedBy,
  });

  factory DeliveryDestination.fromJson(Map<String, dynamic> json) {
    return DeliveryDestination(
      deliveryId: json['deliveryId'] ?? '',
      deliveryName: json['deliveryName'] ?? '',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      label: json['label'],
      assignedBy: json['assignedBy'],
      assignedAt: json['assignedAt'] != null
          ? DateTime.parse(json['assignedAt'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'deliveryId': deliveryId,
      'deliveryName': deliveryName,
      'latitude': latitude,
      'longitude': longitude,
      'label': label,
      'assignedBy': assignedBy,
      'assignedAt': assignedAt.toIso8601String(),
    };
  }
}
