import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../services/api_service.dart';
import '../widgets/resource_form_dialog.dart';
import '../widgets/status_badge.dart';

const List<String> _jobCardTypes = <String>[
  'Safari',
  'Long Term Lease',
  'Test Drive',
  'Service',
  'Client Viewing',
  'Others',
];

class JobCardsScreen extends StatefulWidget {
  const JobCardsScreen({super.key});

  @override
  State<JobCardsScreen> createState() => _JobCardsScreenState();
}

class _JobCardsScreenState extends State<JobCardsScreen> {
  final TextEditingController _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _items = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _leads = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _vehicles = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _users = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _allocations = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _leaseAllocations = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _quotations = <Map<String, dynamic>>[];

  bool _loading = true;
  bool _saving = false;
  int? _downloadingId;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait<dynamic>([
        ApiService.fetchList('/job-cards').catchError((_) => <dynamic>[]),
        ApiService.fetchList('/leads').catchError((_) => <dynamic>[]),
        ApiService.fetchList('/vehicles').catchError((_) => <dynamic>[]),
        ApiService.fetchList('/users').catchError((_) => <dynamic>[]),
        ApiService.fetchList(
          '/safari-allocations',
        ).catchError((_) => <dynamic>[]),
        ApiService.fetchList(
          '/lease-allocations',
        ).catchError((_) => <dynamic>[]),
        ApiService.fetchList('/quotations').catchError((_) => <dynamic>[]),
      ]);

      if (!mounted) return;

      setState(() {
        _items = _toMapList(results[0]).map(_normalizeJobCard).toList();
        _leads = _toMapList(results[1]);
        _vehicles = _toMapList(results[2]);
        _users = _toMapList(results[3]);
        _allocations = _toMapList(results[4]);
        _leaseAllocations = _toMapList(results[5]);
        _quotations = _toMapList(results[6]);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load job cards: $e')));
    }
  }

  List<Map<String, dynamic>> _toMapList(dynamic raw) {
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Map<String, dynamic> _normalizeJobCard(Map<String, dynamic> jobCard) {
    final odometerOutRaw =
        jobCard['odometer_out'] ??
        jobCard['odometerOut'] ??
        jobCard['vehicle']?['odometerOut'];
    final odometerInRaw =
        jobCard['odometer_in'] ??
        jobCard['odometerIn'] ??
        jobCard['vehicle']?['odometerIn'];
    final fuelGaugeOutRaw =
        jobCard['fuel_gauge_out'] ??
        jobCard['fuelGaugeOut'] ??
        jobCard['fuel_out'];
    final fuelGaugeInRaw =
        jobCard['fuel_gauge_in'] ??
        jobCard['fuelGaugeIn'] ??
        jobCard['fuel_in'];
    final routeItineraryRaw =
        jobCard['route_itinerary'] ?? jobCard['routeItinerary'];
    final itineraryLineItems = _itineraryRowsFromRaw(routeItineraryRaw);

    final fallbackStatus =
        _hasReturnDetails(<String, dynamic>{
          'safariEndDate':
              jobCard['safari_end_date'] ?? jobCard['safariEndDate'],
          'timeIn': jobCard['time_in'] ?? jobCard['timeIn'],
          'odometerIn': odometerInRaw,
          'fuelGaugeIn': fuelGaugeInRaw,
        })
        ? 'Closed'
        : 'Open';

    return <String, dynamic>{
      'id': jobCard['id'],
      'leadId': _toInt(jobCard['lead_id'] ?? jobCard['leadId']),
      'vehicleId': _toInt(jobCard['vehicle_id'] ?? jobCard['vehicleId']),
      'leaseAllocationId': _toInt(
        jobCard['lease_allocation_id'] ?? jobCard['leaseAllocationId'],
      ),
      'leaseContractId': _toInt(
        jobCard['lease_contract_id'] ?? jobCard['leaseContractId'],
      ),
      'type':
          (jobCard['type'] ??
                  jobCard['job_type'] ??
                  jobCard['jobType'] ??
                  'Safari')
              .toString(),
      'status': _normalizeStatusValue(
        (jobCard['status'] ??
                jobCard['job_status'] ??
                jobCard['jobStatus'] ??
                fallbackStatus)
            .toString(),
      ),
      'jobCardNo': (jobCard['job_card_no'] ?? jobCard['jobCardNo'] ?? '-')
          .toString(),
      'bookingReferenceNo':
          (jobCard['booking_reference_no'] ??
                  jobCard['bookingReferenceNo'] ??
                  '')
              .toString(),
      'tourOperatorClientName':
          (jobCard['tour_operator_client_name'] ??
                  jobCard['tourOperatorClientName'] ??
                  '')
              .toString(),
      'contactPerson':
          (jobCard['contact_person'] ?? jobCard['contactPerson'] ?? '')
              .toString(),
      'contactNumber':
          (jobCard['contact_number'] ?? jobCard['contactNumber'] ?? '')
              .toString(),
      'contactEmail':
          (jobCard['contact_email'] ?? jobCard['contactEmail'] ?? '')
              .toString(),
      'nationality': (jobCard['nationality'] ?? '').toString(),
      'safariStartDate':
          (jobCard['safari_start_date'] ?? jobCard['safariStartDate'] ?? '')
              .toString(),
      'safariEndDate':
          (jobCard['safari_end_date'] ?? jobCard['safariEndDate'] ?? '')
              .toString(),
      'timeOut': (jobCard['time_out'] ?? jobCard['timeOut'] ?? '').toString(),
      'timeIn': (jobCard['time_in'] ?? jobCard['timeIn'] ?? '').toString(),
      'numberOfDays':
          (jobCard['number_of_days'] ?? jobCard['numberOfDays'] ?? 1)
              .toString(),
      'pickupLocation':
          (jobCard['pickup_location'] ?? jobCard['pickupLocation'] ?? '')
              .toString(),
      'dropoffLocation':
          (jobCard['dropoff_location'] ?? jobCard['dropoffLocation'] ?? '')
              .toString(),
      'routeSummary':
          (jobCard['route_summary'] ?? jobCard['routeSummary'] ?? '')
              .toString(),
      'itineraryLineItems': itineraryLineItems,
      'reason': (jobCard['reason'] ?? '').toString(),
      'clientDetails':
          (jobCard['client_details'] ?? jobCard['clientDetails'] ?? '')
              .toString(),
      'additionalDetails':
          (jobCard['additional_details'] ?? jobCard['additionalDetails'] ?? '')
              .toString(),
      'location': (jobCard['location'] ?? '').toString(),
      'kms': (jobCard['kms'] ?? '').toString(),
      'odometerOut': (odometerOutRaw ?? '').toString(),
      'odometerIn': (odometerInRaw ?? '').toString(),
      'fuelGaugeOut': (fuelGaugeOutRaw ?? '').toString(),
      'fuelGaugeIn': (fuelGaugeInRaw ?? '').toString(),
      'approximateFuelUsed':
          (jobCard['approximate_fuel_used'] ??
                  jobCard['approximateFuelUsed'] ??
                  jobCard['fuel_used'] ??
                  '')
              .toString(),
      'driverDetails':
          (jobCard['driver_details'] ?? jobCard['driverDetails'] ?? '')
              .toString(),
      'guideLanguage':
          (jobCard['guide_language'] ?? jobCard['guideLanguage'] ?? '')
              .toString(),
      'vehicleNo':
          (jobCard['vehicle_no'] ??
                  jobCard['vehicleNo'] ??
                  jobCard['vehicle']?['vehicle_no'] ??
                  jobCard['vehicle']?['vehicleNo'] ??
                  '')
              .toString(),
      'vehiclePlateNo':
          (jobCard['plate_no'] ??
                  jobCard['plateNo'] ??
                  jobCard['vehicle']?['plate_no'] ??
                  jobCard['vehicle']?['plateNo'] ??
                  '')
              .toString(),
      'adults': (jobCard['adults'] ?? 0).toString(),
      'children': (jobCard['children'] ?? 0).toString(),
    };
  }

  String _normalizeStatusValue(String status) {
    if (status == 'Close') return 'Closed';
    if (status == 'Open' || status == 'Closed') return status;
    return 'Open';
  }

  bool _hasReturnDetails(Map<String, dynamic> values) {
    final hasDateRange =
        (values['safariStartDate']?.toString().trim().isNotEmpty ?? false) &&
        (values['safariEndDate']?.toString().trim().isNotEmpty ?? false);
    if (hasDateRange) return true;

    final hasTimeIn = values['timeIn']?.toString().trim().isNotEmpty ?? false;
    final hasOdometerIn =
        values['odometerIn']?.toString().trim().isNotEmpty ?? false;
    final hasFuelGaugeIn =
        values['fuelGaugeIn']?.toString().trim().isNotEmpty ?? false;
    return hasTimeIn || hasOdometerIn || hasFuelGaugeIn;
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse((value ?? '').toString()) ?? 0;
  }

  List<Map<String, dynamic>> _itineraryRowsFromRaw(dynamic raw) {
    if (raw is! List) return <Map<String, dynamic>>[];

    final rows = <Map<String, dynamic>>[];
    for (final item in raw) {
      if (item is Map) {
        final map = Map<String, dynamic>.from(item);
        rows.add(<String, dynamic>{
          'date': (map['date'] ?? map['dayDate'] ?? '').toString().trim(),
          'dayDescription':
              (map['dayDescription'] ??
                      map['dateDescription'] ??
                      map['description'] ??
                      map['lineItem'] ??
                      map['line_item'] ??
                      map['title'] ??
                      map['name'] ??
                      '')
                  .toString()
                  .trim(),
          'allowancePerDay':
              (map['allowancePerDay'] ?? map['allowance_per_day']),
        });
      } else if (item is String && item.trim().isNotEmpty) {
        rows.add(<String, dynamic>{
          'date': '',
          'dayDescription': item.trim(),
          'allowancePerDay': null,
        });
      }
    }
    return rows;
  }

  List<Map<String, dynamic>> _parseItineraryLines(dynamic rawText) {
    if (rawText is! List) return <Map<String, dynamic>>[];

    return rawText
        .whereType<Map>()
        .map((item) {
          final map = Map<String, dynamic>.from(item);
          final date = (map['date'] ?? '').toString().trim();
          final description = (map['dayDescription'] ?? '').toString().trim();
          final allowanceRaw = map['allowancePerDay'];
          final allowance = allowanceRaw is num
              ? allowanceRaw
              : num.tryParse((allowanceRaw ?? '').toString());
          return <String, dynamic>{
            'date': date,
            'dayDescription': description,
            'allowancePerDay': allowance,
          };
        })
        .where((row) {
          final date = (row['date'] ?? '').toString().trim();
          final description = (row['dayDescription'] ?? '').toString().trim();
          final allowance = row['allowancePerDay'];
          return date.isNotEmpty || description.isNotEmpty || allowance != null;
        })
        .toList();
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _items;

    return _items.where((it) {
      final values = [
        (it['jobCardNo'] ?? '').toString(),
        (it['bookingReferenceNo'] ?? '').toString(),
        (it['tourOperatorClientName'] ?? '').toString(),
        (it['type'] ?? '').toString(),
        _leadName(it['leadId']),
        _vehicleLabel(it['vehicleId']),
      ];
      return values.any((v) => v.toLowerCase().contains(q));
    }).toList();
  }

  String _leadName(dynamic leadId) {
    final id = _toInt(leadId);
    final lead = _leads.firstWhere(
      (l) => _toInt(l['id'] ?? l['lead_id']) == id,
      orElse: () => <String, dynamic>{},
    );
    return (lead['group_name'] ??
            lead['groupName'] ??
            lead['client_name'] ??
            lead['clientName'] ??
            '-')
        .toString();
  }

  String _vehicleLabel(dynamic vehicleId) {
    final id = _toInt(vehicleId);
    final vehicle = _vehicles.firstWhere(
      (v) => _toInt(v['id']) == id,
      orElse: () => <String, dynamic>{},
    );
    final no = (vehicle['vehicle_no'] ?? vehicle['vehicleNo'] ?? '').toString();
    final plate = (vehicle['plate_no'] ?? vehicle['plateNo'] ?? '').toString();
    if (no.isEmpty && plate.isEmpty) return '-';
    if (no.isNotEmpty && plate.isNotEmpty) return '$no ($plate)';
    return no.isNotEmpty ? no : plate;
  }

  String _driverNameFromAllocation(dynamic leadId, dynamic vehicleId) {
    final lid = _toInt(leadId);
    final vid = _toInt(vehicleId);
    final alloc = _allocations.firstWhere(
      (a) =>
          _toInt(a['lead_id'] ?? a['leadId']) == lid &&
          _toInt(a['vehicle_id'] ?? a['vehicleId']) == vid,
      orElse: () => <String, dynamic>{},
    );
    final dName = (alloc['driver']?['name'] ?? alloc['driverName'] ?? '')
        .toString();
    if (dName.isNotEmpty) return dName;
    final did = _toInt(alloc['driver_id'] ?? alloc['driverId']);
    if (did <= 0) return '';
    final u = _users.firstWhere(
      (e) => _toInt(e['id']) == did,
      orElse: () => <String, dynamic>{},
    );
    return (u['name'] ?? '').toString();
  }

  String _firstNonEmpty(List<dynamic> values, {String fallback = ''}) {
    for (final value in values) {
      final text = (value ?? '').toString().trim();
      if (text.isNotEmpty) return text;
    }
    return fallback;
  }

  Map<String, dynamic> _leaseAllocationById(int id) {
    if (id <= 0) return <String, dynamic>{};
    return _leaseAllocations.firstWhere(
      (a) => _toInt(a['id']) == id,
      orElse: () => <String, dynamic>{},
    );
  }

  String _leaseAllocationLabel(Map<String, dynamic> allocation) {
    final id = _toInt(allocation['id']);
    if (id <= 0) return '';

    final leadMap = allocation['lead'] is Map
        ? Map<String, dynamic>.from(allocation['lead'] as Map)
        : <String, dynamic>{};
    final contractMap = allocation['contract'] is Map
        ? Map<String, dynamic>.from(allocation['contract'] as Map)
        : <String, dynamic>{};
    final vehicleMap = allocation['vehicle'] is Map
        ? Map<String, dynamic>.from(allocation['vehicle'] as Map)
        : <String, dynamic>{};

    final bookingRef = _firstNonEmpty([
      allocation['booking_reference_no'],
      allocation['bookingReferenceNo'],
      allocation['booking_ref'],
      leadMap['booking_ref'],
      leadMap['bookingReferenceNo'],
    ], fallback: '-');

    final client = _firstNonEmpty([
      allocation['client_name'],
      allocation['clientName'],
      allocation['tour_operator_client_name'],
      allocation['tourOperatorClientName'],
      contractMap['client_name'],
      contractMap['clientName'],
      leadMap['client_name'],
      leadMap['clientName'],
      leadMap['client_company'],
      leadMap['clientCompany'],
    ], fallback: '-');

    final group = _firstNonEmpty([
      allocation['group_name'],
      allocation['groupName'],
      leadMap['group_name'],
      leadMap['groupName'],
      allocation['lead_group_name'],
      allocation['leadGroupName'],
    ], fallback: '-');

    final vehicleNo = _firstNonEmpty([
      allocation['vehicle_no'],
      allocation['vehicleNo'],
      vehicleMap['vehicle_no'],
      vehicleMap['vehicleNo'],
    ]);
    final plate = _firstNonEmpty([
      allocation['plate_no'],
      allocation['plateNo'],
      vehicleMap['plate_no'],
      vehicleMap['plateNo'],
    ]);

    final vehiclePart = vehicleNo.isNotEmpty || plate.isNotEmpty
        ? ' | ${vehicleNo.isNotEmpty ? vehicleNo : '-'} ${plate.isNotEmpty ? '($plate)' : ''}'
              .trim()
        : '';

    return '$id|$bookingRef | $client | $group$vehiclePart';
  }

  Map<String, dynamic> _latestQuotationForLead(int leadId) {
    if (leadId <= 0) return <String, dynamic>{};

    DateTime _stamp(Map<String, dynamic> quote) {
      final raw =
          quote['quoteDate'] ??
          quote['quote_date'] ??
          quote['created_at'] ??
          quote['createdAt'];
      return DateTime.tryParse((raw ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0);
    }

    final matches = _quotations.where((q) {
      final qLeadId = _toInt(q['lead_id'] ?? q['leadId']);
      return qLeadId == leadId;
    }).toList();

    if (matches.isEmpty) return <String, dynamic>{};
    matches.sort((a, b) => _stamp(b).compareTo(_stamp(a)));
    return matches.first;
  }

  List<Map<String, dynamic>> _itineraryRowsFromQuotation(
    Map<String, dynamic> quote,
  ) {
    final rawSections = quote['day_sections'] ?? quote['daySections'];
    if (rawSections is! List) return <Map<String, dynamic>>[];

    final rows = <Map<String, dynamic>>[];
    for (final item in rawSections) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      rows.add(<String, dynamic>{
        'date': (map['date'] ?? map['dayDate'] ?? map['dayTitle'] ?? '')
            .toString()
            .trim(),
        'dayDescription':
            (map['dayDescription'] ??
                    map['dateDescription'] ??
                    map['description'] ??
                    map['details'] ??
                    '')
                .toString()
                .trim(),
        'allowancePerDay': num.tryParse(
          (map['allowancePerDay'] ?? map['allowance_per_day'] ?? '').toString(),
        ),
      });
    }

    return rows.where((row) {
      final d = (row['date'] ?? '').toString().trim();
      final desc = (row['dayDescription'] ?? '').toString().trim();
      final allw = row['allowancePerDay'];
      return d.isNotEmpty || desc.isNotEmpty || allw != null;
    }).toList();
  }

  Future<void> _openForm({Map<String, dynamic>? initial}) async {
    final leadOptions =
        _leads
            .map((l) {
              final id = _toInt(l['id'] ?? l['lead_id']);
              if (id <= 0) return '';
              final name =
                  (l['group_name'] ??
                          l['groupName'] ??
                          l['client_name'] ??
                          l['clientName'] ??
                          'Lead $id')
                      .toString();
              return '$id|$name';
            })
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList()
          ..sort();

    final vehicleOptions =
        _vehicles
            .map((v) {
              final id = _toInt(v['id']);
              if (id <= 0) return '';
              final label = _vehicleLabel(id);
              if (label == '-') return '';
              return '$id|$label';
            })
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList()
          ..sort();

    final leaseAllocationOptions =
        _leaseAllocations
            .map(_leaseAllocationLabel)
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList()
          ..sort();

    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => ResourceFormDialog(
        title: initial == null ? 'Add Job Card' : 'Edit Job Card',
        onFieldChanged: (fieldKey, value, setValue) {
          if (fieldKey == 'type') {
            if (value == 'Safari') {
              setValue('leaseAllocationId', '');
            } else if (value == 'Long Term Lease') {
              setValue('leadId', '');
            }
            return;
          }

          if (fieldKey == 'leadId') {
            final selectedLeadId = _idFromOption(value);
            if (selectedLeadId <= 0) return;

            final lead = _leads.firstWhere(
              (l) => _toInt(l['id'] ?? l['lead_id']) == selectedLeadId,
              orElse: () => <String, dynamic>{},
            );
            final bookingRef = _firstNonEmpty([
              lead['booking_ref'],
              lead['bookingReferenceNo'],
            ]);
            final client = _firstNonEmpty([
              lead['client_company'],
              lead['clientCompany'],
              lead['client_name'],
              lead['clientName'],
            ]);

            if (bookingRef.isNotEmpty)
              setValue('bookingReferenceNo', bookingRef);
            if (client.isNotEmpty) setValue('tourOperatorClientName', client);

            final quote = _latestQuotationForLead(selectedLeadId);
            if (quote.isNotEmpty) {
              final itineraryRows = _itineraryRowsFromQuotation(quote);
              if (itineraryRows.isNotEmpty) {
                setValue('itineraryLineItems', itineraryRows);
              }
            }

            final alloc = _allocations.firstWhere(
              (a) => _toInt(a['lead_id'] ?? a['leadId']) == selectedLeadId,
              orElse: () => <String, dynamic>{},
            );
            final vid = _toInt(alloc['vehicle_id'] ?? alloc['vehicleId']);
            if (vid > 0) {
              setValue('vehicleId', _optionFromIdLabel(vid, vehicleOptions));
            }
            return;
          }

          if (fieldKey == 'leaseAllocationId') {
            final selectedAllocationId = _idFromOption(value);
            final allocation = _leaseAllocationById(selectedAllocationId);
            if (allocation.isEmpty) return;

            final leadMap = allocation['lead'] is Map
                ? Map<String, dynamic>.from(allocation['lead'] as Map)
                : <String, dynamic>{};
            final contractMap = allocation['contract'] is Map
                ? Map<String, dynamic>.from(allocation['contract'] as Map)
                : <String, dynamic>{};
            final vehicleMap = allocation['vehicle'] is Map
                ? Map<String, dynamic>.from(allocation['vehicle'] as Map)
                : <String, dynamic>{};

            final bookingRef = _firstNonEmpty([
              allocation['booking_reference_no'],
              allocation['bookingReferenceNo'],
              allocation['booking_ref'],
              leadMap['booking_ref'],
            ]);
            final client = _firstNonEmpty([
              allocation['client_name'],
              allocation['clientName'],
              contractMap['client_name'],
              contractMap['clientName'],
              leadMap['client_company'],
              leadMap['clientCompany'],
              leadMap['client_name'],
              leadMap['clientName'],
            ]);
            final vehicleNo = _firstNonEmpty([
              allocation['vehicle_no'],
              allocation['vehicleNo'],
              vehicleMap['vehicle_no'],
              vehicleMap['vehicleNo'],
            ]);
            final plate = _firstNonEmpty([
              allocation['plate_no'],
              allocation['plateNo'],
              vehicleMap['plate_no'],
              vehicleMap['plateNo'],
            ]);

            if (bookingRef.isNotEmpty)
              setValue('bookingReferenceNo', bookingRef);
            if (client.isNotEmpty) setValue('tourOperatorClientName', client);
            if (vehicleNo.isNotEmpty) setValue('vehicleNo', vehicleNo);
            if (plate.isNotEmpty) setValue('vehiclePlateNo', plate);

            final vehicleId = _toInt(
              allocation['vehicle_id'] ??
                  allocation['vehicleId'] ??
                  vehicleMap['id'],
            );
            if (vehicleId > 0) {
              setValue(
                'vehicleId',
                _optionFromIdLabel(vehicleId, vehicleOptions),
              );
            }

            final leadId = _toInt(
              allocation['lead_id'] ?? allocation['leadId'],
            );
            if (leadId > 0) {
              setValue('leadId', _optionFromIdLabel(leadId, leadOptions));
            }

            final allocationItinerary =
                allocation['itineraryItems'] ??
                allocation['itinerary_items'] ??
                allocation['route_itinerary'] ??
                allocation['routeItinerary'];
            final itineraryRows = _itineraryRowsFromRaw(allocationItinerary);
            if (itineraryRows.isNotEmpty) {
              setValue('itineraryLineItems', itineraryRows);
            }
          }
        },
        initialValues: {
          'leadId': _optionFromIdLabel(_toInt(initial?['leadId']), leadOptions),
          'leaseAllocationId': _optionFromIdLabel(
            _toInt(initial?['leaseAllocationId']),
            leaseAllocationOptions,
          ),
          'vehicleId': _optionFromIdLabel(
            _toInt(initial?['vehicleId']),
            vehicleOptions,
          ),
          'type': (initial?['type'] ?? 'Safari').toString(),
          'status': (initial?['status'] ?? 'Open').toString(),
          'safariStartDate': (initial?['safariStartDate'] ?? '').toString(),
          'safariEndDate': (initial?['safariEndDate'] ?? '').toString(),
          'pickupLocation': (initial?['pickupLocation'] ?? '').toString(),
          'dropoffLocation': (initial?['dropoffLocation'] ?? '').toString(),
          'routeSummary': (initial?['routeSummary'] ?? '').toString(),
          'itineraryLineItems':
              initial?['itineraryLineItems'] ?? <Map<String, dynamic>>[],
          'bookingReferenceNo': (initial?['bookingReferenceNo'] ?? '')
              .toString(),
          'tourOperatorClientName': (initial?['tourOperatorClientName'] ?? '')
              .toString(),
          'contactPerson': (initial?['contactPerson'] ?? '').toString(),
          'contactNumber': (initial?['contactNumber'] ?? '').toString(),
          'contactEmail': (initial?['contactEmail'] ?? '').toString(),
          'nationality': (initial?['nationality'] ?? '').toString(),
          'timeOut': (initial?['timeOut'] ?? '').toString(),
          'timeIn': (initial?['timeIn'] ?? '').toString(),
          'numberOfDays': (initial?['numberOfDays'] ?? '').toString(),
          'adults': (initial?['adults'] ?? '0').toString(),
          'children': (initial?['children'] ?? '0').toString(),
          'reason': (initial?['reason'] ?? '').toString(),
          'clientDetails': (initial?['clientDetails'] ?? '').toString(),
          'additionalDetails': (initial?['additionalDetails'] ?? '').toString(),
          'location': (initial?['location'] ?? '').toString(),
          'kms': (initial?['kms'] ?? '').toString(),
          'odometerOut': (initial?['odometerOut'] ?? '').toString(),
          'odometerIn': (initial?['odometerIn'] ?? '').toString(),
          'fuelGaugeOut': (initial?['fuelGaugeOut'] ?? '').toString(),
          'fuelGaugeIn': (initial?['fuelGaugeIn'] ?? '').toString(),
          'approximateFuelUsed': (initial?['approximateFuelUsed'] ?? '')
              .toString(),
          'driverDetails': (initial?['driverDetails'] ?? '').toString(),
          'guideLanguage': (initial?['guideLanguage'] ?? '').toString(),
          'vehicleNo': (initial?['vehicleNo'] ?? '').toString(),
          'vehiclePlateNo': (initial?['vehiclePlateNo'] ?? '').toString(),
        },
        fields: [
          const ResourceFormField(
            keyName: 'type',
            label: 'Type',
            type: ResourceFieldType.select,
            options: _jobCardTypes,
            requiredField: true,
          ),
          ResourceFormField(
            keyName: 'leadId',
            label: 'Lead',
            type: ResourceFieldType.select,
            options: leadOptions,
            requiredField: true,
            visibleWhenKey: 'type',
            visibleWhenValues: ['Safari'],
          ),
          ResourceFormField(
            keyName: 'leaseAllocationId',
            label: 'Lease Allocation *',
            type: ResourceFieldType.select,
            options: leaseAllocationOptions,
            requiredField: true,
            visibleWhenKey: 'type',
            visibleWhenValues: ['Long Term Lease'],
          ),
          ResourceFormField(
            keyName: 'vehicleId',
            label: 'Vehicle',
            type: ResourceFieldType.select,
            options: vehicleOptions,
            requiredField: true,
          ),
          const ResourceFormField(
            keyName: 'status',
            label: 'Status',
            type: ResourceFieldType.select,
            options: ['Open', 'Closed'],
            requiredField: true,
          ),
          const ResourceFormField(
            keyName: 'safariStartDate',
            label: 'Start Date',
            type: ResourceFieldType.date,
          ),
          const ResourceFormField(
            keyName: 'safariEndDate',
            label: 'End Date',
            type: ResourceFieldType.date,
          ),
          const ResourceFormField(
            keyName: 'pickupLocation',
            label: 'Pickup Location',
          ),
          const ResourceFormField(
            keyName: 'dropoffLocation',
            label: 'Dropoff Location',
          ),
          const ResourceFormField(
            keyName: 'routeSummary',
            label: 'Route Summary',
            type: ResourceFieldType.textarea,
            maxLines: 3,
          ),
          const ResourceFormField(
            keyName: 'itineraryLineItems',
            label: 'Itinerary (Line Items)',
            type: ResourceFieldType.itinerary,
          ),
          const ResourceFormField(
            keyName: 'bookingReferenceNo',
            label: 'Booking Ref No',
          ),
          const ResourceFormField(
            keyName: 'tourOperatorClientName',
            label: 'Tour Operator/Client',
          ),
          const ResourceFormField(
            keyName: 'contactPerson',
            label: 'Contact Person',
          ),
          const ResourceFormField(
            keyName: 'contactNumber',
            label: 'Contact Number',
          ),
          const ResourceFormField(
            keyName: 'contactEmail',
            label: 'Contact Email',
          ),
          const ResourceFormField(keyName: 'nationality', label: 'Nationality'),
          const ResourceFormField(keyName: 'timeOut', label: 'Time Out'),
          const ResourceFormField(keyName: 'timeIn', label: 'Time In'),
          const ResourceFormField(
            keyName: 'numberOfDays',
            label: 'Number Of Days',
            type: ResourceFieldType.number,
          ),
          const ResourceFormField(
            keyName: 'adults',
            label: 'Adults',
            type: ResourceFieldType.number,
          ),
          const ResourceFormField(
            keyName: 'children',
            label: 'Children',
            type: ResourceFieldType.number,
          ),
          const ResourceFormField(
            keyName: 'reason',
            label: 'Reason',
            type: ResourceFieldType.textarea,
            maxLines: 2,
          ),
          const ResourceFormField(
            keyName: 'clientDetails',
            label: 'Client Details',
            type: ResourceFieldType.textarea,
            maxLines: 2,
          ),
          const ResourceFormField(
            keyName: 'additionalDetails',
            label: 'Additional Details',
            type: ResourceFieldType.textarea,
            maxLines: 2,
          ),
          const ResourceFormField(keyName: 'location', label: 'Location'),
          const ResourceFormField(
            keyName: 'kms',
            label: 'KMs',
            type: ResourceFieldType.number,
          ),
          const ResourceFormField(
            keyName: 'odometerOut',
            label: 'Odometer Out',
            type: ResourceFieldType.number,
          ),
          const ResourceFormField(
            keyName: 'odometerIn',
            label: 'Odometer In',
            type: ResourceFieldType.number,
          ),
          const ResourceFormField(
            keyName: 'fuelGaugeOut',
            label: 'Fuel Gauge Out',
            type: ResourceFieldType.number,
          ),
          const ResourceFormField(
            keyName: 'fuelGaugeIn',
            label: 'Fuel Gauge In',
            type: ResourceFieldType.number,
          ),
          const ResourceFormField(
            keyName: 'approximateFuelUsed',
            label: 'Approx Fuel Used',
            type: ResourceFieldType.number,
          ),
          const ResourceFormField(
            keyName: 'driverDetails',
            label: 'Driver Details',
          ),
          const ResourceFormField(
            keyName: 'guideLanguage',
            label: 'Guide Language',
          ),
          const ResourceFormField(keyName: 'vehicleNo', label: 'Vehicle No'),
          const ResourceFormField(
            keyName: 'vehiclePlateNo',
            label: 'Vehicle Plate No',
          ),
        ],
      ),
    );

    if (payload == null) return;

    final type = (payload['type'] ?? 'Safari').toString();
    final leaseAllocationId = _idFromOption(payload['leaseAllocationId']);
    final selectedAllocation = _leaseAllocationById(leaseAllocationId);
    final leadId = type == 'Long Term Lease'
        ? _toInt(
            selectedAllocation['lead_id'] ??
                selectedAllocation['leadId'] ??
                payload['leadId'],
          )
        : _idFromOption(payload['leadId']);
    final vehicleIdFromForm = _idFromOption(payload['vehicleId']);
    final vehicleIdFromLease = _toInt(
      selectedAllocation['vehicle_id'] ?? selectedAllocation['vehicleId'],
    );
    final vehicleId = type == 'Long Term Lease'
        ? (vehicleIdFromLease > 0 ? vehicleIdFromLease : vehicleIdFromForm)
        : vehicleIdFromForm;
    final startDate = _nullIfEmpty(payload['safariStartDate']);
    final endDate = _nullIfEmpty(payload['safariEndDate']);

    if (type == 'Safari' && leadId <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a valid lead.')),
      );
      return;
    }

    if (type == 'Long Term Lease' && leaseAllocationId <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a valid lease allocation.'),
        ),
      );
      return;
    }

    if (vehicleId <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a valid vehicle.')),
      );
      return;
    }

    int resolvedDays = (_numberOrNull(payload['numberOfDays']) ?? 0).toInt();
    if (resolvedDays <= 0 && startDate != null && endDate != null) {
      final start = DateTime.tryParse(startDate);
      final end = DateTime.tryParse(endDate);
      if (start != null && end != null) {
        resolvedDays = end.difference(start).inDays + 1;
      }
    }
    if (resolvedDays <= 0) {
      resolvedDays = 1;
    }

    final derivedStatus =
        _hasReturnDetails(<String, dynamic>{
          'safariStartDate': startDate,
          'safariEndDate': endDate,
          'timeIn': payload['timeIn'],
          'odometerIn': payload['odometerIn'],
          'fuelGaugeIn': payload['fuelGaugeIn'],
        })
        ? 'Closed'
        : 'Open';
    final itineraryRows = _parseItineraryLines(payload['itineraryLineItems']);

    final requestBody = <String, dynamic>{
      'leadId': leadId,
      'vehicleId': vehicleId,
      'leaseAllocationId': leaseAllocationId > 0 ? leaseAllocationId : null,
      'lease_allocation_id': leaseAllocationId > 0 ? leaseAllocationId : null,
      'status': _normalizeStatusValue(
        (payload['status'] ?? derivedStatus).toString(),
      ),
      'type': type,
      'safariStartDate': startDate,
      'safari_start_date': startDate,
      'safariEndDate': endDate,
      'safari_end_date': endDate,
      'numberOfDays': resolvedDays,
      'number_of_days': resolvedDays,
      'timeOut': _nullIfEmpty(payload['timeOut']),
      'time_out': _nullIfEmpty(payload['timeOut']),
      'timeIn': _nullIfEmpty(payload['timeIn']),
      'time_in': _nullIfEmpty(payload['timeIn']),
      'pickupLocation': _nullIfEmpty(payload['pickupLocation']),
      'dropoffLocation': _nullIfEmpty(payload['dropoffLocation']),
      'routeSummary': _nullIfEmpty(payload['routeSummary']),
      'routeItinerary': itineraryRows,
      'route_itinerary': itineraryRows,
      'additionalDetails': _nullIfEmpty(payload['additionalDetails']),
      'additional_details': _nullIfEmpty(payload['additionalDetails']),
      'bookingReferenceNo': _nullIfEmpty(payload['bookingReferenceNo']),
      'tourOperatorClientName': _nullIfEmpty(payload['tourOperatorClientName']),
      'contactPerson': _nullIfEmpty(payload['contactPerson']),
      'contactNumber': _nullIfEmpty(payload['contactNumber']),
      'contactEmail': _nullIfEmpty(payload['contactEmail']),
      'nationality': _nullIfEmpty(payload['nationality']),
      'adults': _numberOrNull(payload['adults']) ?? 0,
      'children': _numberOrNull(payload['children']) ?? 0,
      'reason': _nullIfEmpty(payload['reason']),
      'clientDetails': _nullIfEmpty(payload['clientDetails']),
      'location': _nullIfEmpty(payload['location']),
      'kms': _numberOrNull(payload['kms']),
      'odometerOut': _numberOrNull(payload['odometerOut']),
      'odometerIn': _numberOrNull(payload['odometerIn']),
      'fuelGaugeOut': _numberOrNull(payload['fuelGaugeOut']),
      'fuelGaugeIn': _numberOrNull(payload['fuelGaugeIn']),
      'approximateFuelUsed': _numberOrNull(payload['approximateFuelUsed']),
      'driverDetails': _nullIfEmpty(payload['driverDetails']),
      'guideLanguage': _nullIfEmpty(payload['guideLanguage']),
      'vehicleNo': _nullIfEmpty(payload['vehicleNo']),
      'vehiclePlateNo': _nullIfEmpty(payload['vehiclePlateNo']),
    };

    setState(() => _saving = true);
    try {
      if (initial == null) {
        await ApiService.post('/job-cards', requestBody);
      } else {
        await ApiService.put('/job-cards/${initial['id']}', requestBody);
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  String _optionFromIdLabel(int id, List<String> options) {
    if (id <= 0) return options.isNotEmpty ? options.first : '';
    return options.firstWhere(
      (opt) => _idFromOption(opt) == id,
      orElse: () => options.isNotEmpty ? options.first : '',
    );
  }

  int _idFromOption(dynamic value) {
    final text = (value ?? '').toString();
    final idPart = text.split('|').first;
    return int.tryParse(idPart) ?? 0;
  }

  String? _nullIfEmpty(dynamic value) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty ? null : text;
  }

  num? _numberOrNull(dynamic value) {
    final text = (value ?? '').toString().trim();
    if (text.isEmpty) return null;
    return num.tryParse(text);
  }

  Future<void> _viewCard(Map<String, dynamic> card) async {
    final fresh = await ApiService.get(
      '/job-cards/${card['id']}',
    ).catchError((_) => card);
    if (!mounted) return;
    final map = fresh is Map<String, dynamic>
        ? fresh
        : (fresh is Map ? Map<String, dynamic>.from(fresh) : card);
    final data = map['data'] is Map
        ? Map<String, dynamic>.from(map['data'])
        : (map['jobCard'] is Map
              ? Map<String, dynamic>.from(map['jobCard'])
              : map);
    final normalized = _normalizeJobCard(data);

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Job Card ${normalized['jobCardNo']}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _kv('Type', (normalized['type'] ?? '-').toString()),
              _kv('Status', (normalized['status'] ?? '-').toString()),
              _kv('Lead', _leadName(normalized['leadId'])),
              _kv('Vehicle', _vehicleLabel(normalized['vehicleId'])),
              _kv(
                'Driver',
                _driverNameFromAllocation(
                      normalized['leadId'],
                      normalized['vehicleId'],
                    ).isEmpty
                    ? '-'
                    : _driverNameFromAllocation(
                        normalized['leadId'],
                        normalized['vehicleId'],
                      ),
              ),
              _kv(
                'Start Date',
                (normalized['safariStartDate'] ?? '-').toString(),
              ),
              _kv('End Date', (normalized['safariEndDate'] ?? '-').toString()),
              _kv('Route', (normalized['routeSummary'] ?? '-').toString()),
              _kv(
                'Booking Ref',
                (normalized['bookingReferenceNo'] ?? '-').toString(),
              ),
              _kv(
                'Client',
                (normalized['tourOperatorClientName'] ?? '-').toString(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _kv(String key, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RichText(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style,
          children: [
            TextSpan(
              text: '$key: ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: value.isEmpty ? '-' : value),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(Map<String, dynamic> card) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Job Card'),
        content: const Text('Are you sure you want to delete this job card?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await ApiService.delete('/job-cards/${card['id']}');
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  Future<void> _downloadPdf(Map<String, dynamic> card) async {
    final id = _toInt(card['id']);
    if (id <= 0) return;

    setState(() => _downloadingId = id);
    try {
      final bytes = await ApiService.downloadBytes('/job-cards/$id/pdf');
      final dir = await getTemporaryDirectory();
      final no = (card['jobCardNo'] ?? 'job-card-$id').toString();
      final safe = no.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final file = File('${dir.path}${Platform.pathSeparator}$safe.pdf');
      await file.writeAsBytes(bytes, flush: true);

      final result = await OpenFilex.open(file.path, type: 'application/pdf');
      if (!mounted) return;
      if (result.type != ResultType.done) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('PDF saved to ${file.path}')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('PDF download failed: $e')));
    } finally {
      if (mounted) {
        setState(() => _downloadingId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : () => _openForm(),
        icon: const Icon(Icons.add),
        label: Text(_saving ? 'Saving...' : 'Add Job Card'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                hintText: 'Search job cards...',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: _filtered.isEmpty
                        ? ListView(
                            children: const [
                              SizedBox(height: 100),
                              Center(child: Text('No job cards found')),
                            ],
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _filtered.length,
                            itemBuilder: (_, i) {
                              final card = _filtered[i];
                              final id = _toInt(card['id']);
                              final driver = _driverNameFromAllocation(
                                card['leadId'],
                                card['vehicleId'],
                              );
                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surface,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.outline,
                                    width: 0.8,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            (card['jobCardNo'] ?? '-')
                                                .toString(),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 15,
                                            ),
                                          ),
                                        ),
                                        StatusBadge(
                                          status: (card['status'] ?? 'Open')
                                              .toString(),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      'Type: ${(card['type'] ?? '-').toString()}',
                                    ),
                                    const SizedBox(height: 4),
                                    Text('Lead: ${_leadName(card['leadId'])}'),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Vehicle: ${_vehicleLabel(card['vehicleId'])}',
                                    ),
                                    if (driver.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text('Driver: $driver'),
                                    ],
                                    const SizedBox(height: 10),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        OutlinedButton.icon(
                                          onPressed: () => _viewCard(card),
                                          icon: const Icon(
                                            Icons.visibility_outlined,
                                            size: 16,
                                          ),
                                          label: const Text('View'),
                                        ),
                                        OutlinedButton.icon(
                                          onPressed: () =>
                                              _openForm(initial: card),
                                          icon: const Icon(
                                            Icons.edit_outlined,
                                            size: 16,
                                          ),
                                          label: const Text('Edit'),
                                        ),
                                        OutlinedButton.icon(
                                          onPressed: _downloadingId == id
                                              ? null
                                              : () => _downloadPdf(card),
                                          icon: _downloadingId == id
                                              ? const SizedBox(
                                                  width: 14,
                                                  height: 14,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                )
                                              : const Icon(
                                                  Icons.picture_as_pdf_outlined,
                                                  size: 16,
                                                ),
                                          label: Text(
                                            _downloadingId == id
                                                ? 'Downloading'
                                                : 'PDF',
                                          ),
                                        ),
                                        OutlinedButton.icon(
                                          onPressed: () => _delete(card),
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            size: 16,
                                          ),
                                          label: const Text('Delete'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}
