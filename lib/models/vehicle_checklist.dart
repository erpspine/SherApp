const String kPreDepartureChecklistType = 'pre_departure';
const String kPostDepartureChecklistType = 'post_departure';

String checklistTypeLabel(String type) {
  switch (type) {
    case kPreDepartureChecklistType:
      return 'Pre-Departure';
    case kPostDepartureChecklistType:
      return 'Post-Return';
    default:
      return type
          .replaceAll('_', ' ')
          .split(' ')
          .where((part) => part.isNotEmpty)
          .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
          .join(' ');
  }
}

class ChecklistItem {
  final int id;
  final String name;
  final int checklistId;
  final String checklistTitle;
  String status; // '', 'OK' or 'NOK'
  String issue; // Issue description for NOK

  ChecklistItem({
    required this.id,
    required this.name,
    this.checklistId = 0,
    this.checklistTitle = '',
    this.status = '',
    this.issue = '',
  });

  factory ChecklistItem.fromChecklistDefinition(
    Map<String, dynamic> checklist,
    Map<String, dynamic>? item,
  ) {
    final checklistId = checklist['id'] is int
        ? checklist['id'] as int
        : int.tryParse('${checklist['id'] ?? 0}') ?? 0;
    final checklistTitle = (checklist['title'] ?? '').toString();
    final itemId = item?['id'] is int
        ? item!['id'] as int
        : int.tryParse('${item?['id'] ?? checklistId}') ?? checklistId;
    final itemText =
        (item?['text'] ?? item?['name'] ?? item?['title'] ?? checklistTitle)
            .toString();

    return ChecklistItem(
      id: itemId,
      name: itemText,
      checklistId: checklistId,
      checklistTitle: checklistTitle,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'checklist_id': checklistId,
    'checklist_title': checklistTitle,
    'name': name,
    'text': name,
    'status': status,
    'issue': issue,
  };
}

class VehicleChecklist {
  final String type; // 'pre_departure' or 'post_departure'
  final Map<String, dynamic> lead; // Selected lead details
  final Map<String, dynamic> vehicle; // Auto-populated vehicle details
  final String odometer;
  final String parkingLocation;
  List<ChecklistItem> items;
  String remarks;
  List<String> imagePaths; // Local file paths of images

  VehicleChecklist({
    required this.type,
    required this.lead,
    required this.vehicle,
    this.odometer = '',
    this.parkingLocation = '',
    this.items = const [],
    this.remarks = '',
    this.imagePaths = const [],
  });

  Map<String, dynamic> toJson() => {
    'type': type,
    'checklistType': type,
    'lead': lead,
    'vehicle': vehicle,
    'odometer': odometer,
    'odometer_reading': odometer,
    if (type == kPreDepartureChecklistType) 'odometer_out': odometer,
    if (type == kPostDepartureChecklistType) 'odometer_in': odometer,
    'parkingLocation': parkingLocation,
    'parking_location': parkingLocation,
    'items': items.map((item) => item.toJson()).toList(),
    'remarks': remarks,
    'images': [],
  };
}
