import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../services/api_service.dart';

class QuotationCreateScreen extends StatefulWidget {
  const QuotationCreateScreen({super.key, this.editId});

  /// When non-null the screen loads the existing quotation and saves via PUT.
  final int? editId;

  @override
  State<QuotationCreateScreen> createState() => _QuotationCreateScreenState();
}

class _QuotationCreateScreenState extends State<QuotationCreateScreen> {
  static const List<String> _createStatusOptions = ['Pending', 'Draft'];
  static const List<String> _editStatusOptions = [
    'Pending',
    'Draft',
    'Sent',
    'Approved',
    'Rejected',
    'Converted',
  ];

  List<String> get _statusOptions =>
      widget.editId != null ? _editStatusOptions : _createStatusOptions;

  final TextEditingController _clientCtrl = TextEditingController();
  final TextEditingController _attentionCtrl = TextEditingController();
  final TextEditingController _notesCtrl = TextEditingController();

  DateTime _quoteDate = DateTime.now();
  bool _loadingLeads = false;
  bool _loadingRates = false;
  bool _saving = false;
  bool _loadingQuotation = false;
  String? _selectedLeadId;
  String _quoteStatus = 'Pending';

  List<Map<String, dynamic>> _leads = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _transportRates = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _parkRates = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _concessionRates = <Map<String, dynamic>>[];
  List<_DayDraft> _daySections = <_DayDraft>[_DayDraft(dayIndex: 1)];

  @override
  void initState() {
    super.initState();
    _loadLeads();
    if (widget.editId != null) {
      _loadQuotationForEdit(widget.editId!);
    }
  }

  @override
  void dispose() {
    _clientCtrl.dispose();
    _attentionCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLeads() async {
    setState(() => _loadingLeads = true);
    try {
      final raw = await ApiService.fetchList('/leads');
      if (!mounted) return;
      setState(() {
        _leads = raw.whereType<Map>().map((e) {
          return Map<String, dynamic>.from(e as Map);
        }).toList();
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not load leads.')));
    } finally {
      if (mounted) {
        setState(() => _loadingLeads = false);
      }
    }
  }

  double _parseItemNum(dynamic value) {
    if (value is num) return value.toDouble();
    final cleaned = value.toString().replaceAll(RegExp(r'[^0-9.]'), '');
    return double.tryParse(cleaned) ?? 0.0;
  }

  Future<void> _loadQuotationForEdit(int id) async {
    setState(() => _loadingQuotation = true);
    try {
      final raw = await ApiService.get('/quotations/$id');
      if (!mounted) return;

      // Unwrap nested response shapes (data / quotation / flat)
      final Map<String, dynamic> q = () {
        if (raw is Map<String, dynamic>) {
          final nested = raw['data'] ?? raw['quotation'];
          if (nested is Map<String, dynamic>) return nested;
          if (nested is Map) return Map<String, dynamic>.from(nested);
          return raw;
        }
        if (raw is Map) return Map<String, dynamic>.from(raw);
        return <String, dynamic>{};
      }();

      final clientVal = (q['client'] ?? '').toString();
      final attentionVal = (q['attention'] ?? '').toString();
      final notesVal = (q['notes'] ?? '').toString();
      final statusVal = (q['status'] ?? 'Pending').toString();
      final leadIdVal = (q['lead_id'] ?? q['leadId'] ?? '').toString();
      final quoteDateRaw = (q['quote_date'] ?? q['quoteDate'] ?? '').toString();
      final quoteDateParsed =
          DateTime.tryParse(_toIsoDate(quoteDateRaw)) ?? DateTime.now();

      // Parse day sections
      final rawDaySections = q['day_sections'] ?? q['daySections'];
      final rawLineItems = q['line_items'] ?? q['lineItems'];

      _ItemDraft _parseItem(Map<String, dynamic> im) {
        return _ItemDraft()
          ..item = (im['item'] ?? '').toString()
          ..customItem = (im['custom_item'] ?? im['customItem'] ?? '')
              .toString()
          ..description = (im['description'] ?? '').toString()
          ..unit = (im['unit'] ?? 'Per person').toString()
          ..qty = _parseItemNum(im['qty'])
          ..rate = _parseItemNum(im['rate']);
      }

      String _readDayDescription(
        Map<String, dynamic> section, {
        List? rawItems,
      }) {
        final direct =
            (section['day_description'] ??
                    section['dayDescription'] ??
                    section['description'] ??
                    '')
                .toString()
                .trim();
        if (direct.isNotEmpty) return direct;

        if (rawItems is List) {
          for (final item in rawItems) {
            if (item is! Map) continue;
            final map = Map<String, dynamic>.from(item);
            final fromItem =
                (map['day_description'] ?? map['dayDescription'] ?? '')
                    .toString()
                    .trim();
            if (fromItem.isNotEmpty) return fromItem;
          }
        }

        return '';
      }

      List<_DayDraft> sections;

      if (rawDaySections is List && rawDaySections.isNotEmpty) {
        sections = List<_DayDraft>.generate(rawDaySections.length, (i) {
          final s = rawDaySections[i] is Map
              ? Map<String, dynamic>.from(rawDaySections[i] as Map)
              : <String, dynamic>{};
          final draft = _DayDraft(dayIndex: i + 1);
          final dayDateRaw =
              (s['day_date'] ??
                      s['dayDate'] ??
                      s['date'] ??
                      s['day_title'] ??
                      s['dayTitle'] ??
                      '')
                  .toString();
          draft.dayDate = _toIsoDate(dayDateRaw);
          draft.dayTitle = (s['day_title'] ?? s['dayTitle'] ?? draft.dayDate)
              .toString();
          final rawItems = s['items'] ?? s['line_items'] ?? s['lineItems'];
          draft.dayDescription = _readDayDescription(s, rawItems: rawItems);
          if (rawItems is List && rawItems.isNotEmpty) {
            draft.items = rawItems
                .whereType<Map>()
                .map((e) => _parseItem(Map<String, dynamic>.from(e)))
                .toList();
          }
          return draft;
        });
      } else if (rawLineItems is List && rawLineItems.isNotEmpty) {
        final draft = _DayDraft(dayIndex: 1);
        final first = rawLineItems.first is Map
            ? Map<String, dynamic>.from(rawLineItems.first as Map)
            : <String, dynamic>{};
        final dayDateRaw =
            (first['day_date'] ??
                    first['dayDate'] ??
                    first['date'] ??
                    first['day_title'] ??
                    first['dayTitle'] ??
                    '')
                .toString();
        draft.dayDate = _toIsoDate(dayDateRaw);
        draft.dayTitle =
            (first['day_title'] ?? first['dayTitle'] ?? draft.dayDate)
                .toString();
        draft.dayDescription = _readDayDescription(
          first,
          rawItems: rawLineItems,
        );
        draft.items = rawLineItems
            .whereType<Map>()
            .map((e) => _parseItem(Map<String, dynamic>.from(e)))
            .toList();
        sections = [draft];
      } else {
        sections = [_DayDraft(dayIndex: 1)];
      }

      setState(() {
        _clientCtrl.text = clientVal;
        _attentionCtrl.text = attentionVal;
        _notesCtrl.text = notesVal;
        _quoteStatus = statusVal;
        _quoteDate = quoteDateParsed;
        if (leadIdVal.isNotEmpty) _selectedLeadId = leadIdVal;
        _daySections = sections;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not load quotation: $e')));
    } finally {
      if (mounted) setState(() => _loadingQuotation = false);
    }
  }

  String _fmtDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  double get _subtotal {
    var value = 0.0;
    for (final day in _daySections) {
      for (final item in day.items) {
        value += item.qty * item.rate;
      }
    }
    return value;
  }

  int get _lineItemCount {
    var count = 0;
    for (final day in _daySections) {
      count += day.items.length;
    }
    return count;
  }

  double get _tax => _subtotal * 0.18;

  double get _grandTotal => _subtotal + _tax;

  String _leadText(Map<String, dynamic> lead, String snake, String camel) {
    final value = lead[snake] ?? lead[camel] ?? '';
    return value?.toString() ?? '';
  }

  String _toIsoDate(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return '';

    final direct = RegExp(r'^(\d{4}-\d{2}-\d{2})').firstMatch(value);
    if (direct != null) {
      return direct.group(1) ?? '';
    }

    final parsed = DateTime.tryParse(value);
    if (parsed == null) return '';
    return _fmtDate(parsed);
  }

  List<String> _tripDates(String startDate, String endDate) {
    final startIso = _toIsoDate(startDate);
    final endIso = _toIsoDate(endDate);
    if (startIso.isEmpty || endIso.isEmpty) return <String>[];

    final start = DateTime.tryParse(startIso);
    final end = DateTime.tryParse(endIso);
    if (start == null || end == null) return <String>[];
    if (start.isAfter(end)) return <String>[startIso];

    final out = <String>[];
    var cursor = start;
    while (!cursor.isAfter(end)) {
      out.add(_fmtDate(cursor));
      cursor = cursor.add(const Duration(days: 1));
    }
    return out;
  }

  void _autofillFromLead(String leadId) {
    final match = _leads.where((lead) {
      final id = (lead['id'] ?? '').toString();
      return id == leadId;
    }).toList();

    if (match.isEmpty) return;
    final lead = match.first;

    final client = _leadText(lead, 'client_company', 'clientCompany');
    final attention = _leadText(lead, 'agent_contact', 'agentContact');
    final routeParks = _leadText(lead, 'route_parks', 'routeParks');
    final bookingRef = _leadText(lead, 'booking_ref', 'bookingRef');
    final startDate = _leadText(lead, 'start_date', 'startDate');
    final endDate = _leadText(lead, 'end_date', 'endDate');

    final tripDays = _tripDates(startDate, endDate);
    final sections = tripDays.isEmpty
        ? <_DayDraft>[_DayDraft(dayIndex: 1)]
        : List<_DayDraft>.generate(tripDays.length, (idx) {
            final day = _DayDraft(dayIndex: idx + 1);
            day.dayDate = tripDays[idx];
            day.dayTitle = tripDays[idx];
            if (idx == 0 && routeParks.isNotEmpty) {
              day.dayDescription = routeParks;
            }
            return day;
          });

    if (sections.isNotEmpty) {
      final first = sections.first;
      if (first.items.isNotEmpty) {
        first.items.first.item = 'Transport';
        if (routeParks.isNotEmpty) {
          first.items.first.description = routeParks;
        }
        first.items.first.unit = 'Vehicle';
      }
    }

    final noteParts = <String>[];
    if (bookingRef.isNotEmpty) noteParts.add('Lead $bookingRef');
    if (routeParks.isNotEmpty) noteParts.add(routeParks);
    if (startDate.isNotEmpty || endDate.isNotEmpty) {
      noteParts.add('${_toIsoDate(startDate)} to ${_toIsoDate(endDate)}');
    }

    setState(() {
      if (client.isNotEmpty) _clientCtrl.text = client;
      if (attention.isNotEmpty) _attentionCtrl.text = attention;
      if (noteParts.isNotEmpty) {
        _notesCtrl.text = noteParts.join(' | ');
      }
      _daySections = sections;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _quoteDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() => _quoteDate = picked);
  }

  Future<void> _pickDayDate(int dayIndex) async {
    DateTime initial = DateTime.now();
    final existing = _daySections[dayIndex].dayDate.trim();
    if (existing.isNotEmpty) {
      final parsed = DateTime.tryParse(existing);
      if (parsed != null) {
        initial = parsed;
      }
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      _daySections[dayIndex].dayDate = _fmtDate(picked);
      _daySections[dayIndex].dayTitle = _fmtDate(picked);
    });
  }

  void _addDay() {
    setState(
      () => _daySections.add(_DayDraft(dayIndex: _daySections.length + 1)),
    );
  }

  void _removeDay(int index) {
    if (_daySections.length == 1) return;
    setState(() => _daySections.removeAt(index));
  }

  void _addItem(int dayIndex) {
    setState(() => _daySections[dayIndex].items.add(_ItemDraft()));
  }

  void _removeItem(int dayIndex, int itemIndex) {
    if (_daySections[dayIndex].items.length == 1) return;
    setState(() => _daySections[dayIndex].items.removeAt(itemIndex));
  }

  Future<void> _ensureRatesLoaded() async {
    if (_transportRates.isNotEmpty ||
        _parkRates.isNotEmpty ||
        _concessionRates.isNotEmpty) {
      return;
    }

    setState(() => _loadingRates = true);
    try {
      final transportRaw = await ApiService.fetchList('/transport-rates');
      final parkRaw = await ApiService.fetchList('/park-rates');
      final concessionRaw = await ApiService.fetchList('/concession-rates');
      if (!mounted) return;

      setState(() {
        _transportRates = transportRaw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _parkRates = parkRaw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _concessionRates = concessionRaw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load item rates.')),
      );
    } finally {
      if (mounted) {
        setState(() => _loadingRates = false);
      }
    }
  }

  List<Map<String, dynamic>> _ratesForCategory(String category) {
    switch (category) {
      case 'Transport':
        return _transportRates;
      case 'Park Fees':
        return _parkRates;
      case 'Concession Fees':
        return _concessionRates;
      default:
        return const <Map<String, dynamic>>[];
    }
  }

  String _mapText(Map<String, dynamic> row, String snake, String camel) {
    final value = row[snake] ?? row[camel] ?? '';
    return value?.toString() ?? '';
  }

  String _rateDescription(String category, Map<String, dynamic> row) {
    if (category == 'Transport') {
      final particular = _mapText(row, 'particular', 'particular');
      final name = _mapText(row, 'name', 'name');
      return particular.isNotEmpty ? particular : name;
    }

    final park = _mapText(row, 'park_name', 'parkName');
    final type = _mapText(row, 'type', 'type').replaceAll('_', ' ');
    final rateCategory = _mapText(
      row,
      'category',
      'category',
    ).replaceAll('_', ' ');
    return [
      park,
      type,
      rateCategory,
    ].where((e) => e.trim().isNotEmpty).join(' - ');
  }

  String _rateLabel(String category, Map<String, dynamic> row) {
    final rate = _extractRate(row);
    final description = _rateDescription(category, row);
    return '${description.isEmpty ? category : description} - USD ${rate.toStringAsFixed(2)}';
  }

  double _extractRate(Map<String, dynamic> row) {
    final candidates = <dynamic>[
      row['rate'],
      row['amount'],
      row['cost'],
      row['cost_per_vehicle'],
      row['costPerVehicle'],
      row['cost_per_adult_concession'],
      row['costPerAdultConcession'],
      row['cost_per_child_concession'],
      row['costPerChildConcession'],
      row['cost_per_park_fee'],
      row['costPerParkFee'],
      row['cost_per_child_park_fee'],
      row['costPerChildParkFee'],
    ];

    for (final value in candidates) {
      final raw = (value ?? '').toString().trim();
      if (raw.isEmpty) continue;

      final direct = double.tryParse(raw);
      if (direct != null) return direct;

      final cleaned = raw
          .replaceAll(',', '')
          .replaceAll(RegExp(r'[^0-9.\-]'), '');
      final parsed = double.tryParse(cleaned);
      if (parsed != null) return parsed;
    }
    return 0;
  }

  double _autoQtyFromLead(String category, Map<String, dynamic> product) {
    if (_selectedLeadId == null || _selectedLeadId!.isEmpty) return 0;
    final found = _leads.where((lead) {
      return (lead['id'] ?? '').toString() == _selectedLeadId;
    }).toList();
    if (found.isEmpty) return 0;

    final lead = found.first;
    if (category == 'Transport') {
      return double.tryParse(
            (lead['no_of_vehicles'] ?? lead['noOfVehicles'] ?? '').toString(),
          ) ??
          0;
    }

    final adults =
        double.tryParse(
          (lead['pax_adults'] ?? lead['paxAdults'] ?? '').toString(),
        ) ??
        0;
    final children =
        double.tryParse(
          (lead['pax_children'] ?? lead['paxChildren'] ?? '').toString(),
        ) ??
        0;

    final hint = [
      _mapText(product, 'type', 'type'),
      _mapText(product, 'category', 'category'),
      _mapText(product, 'particular', 'particular'),
    ].join(' ').toLowerCase();

    if (hint.contains('child') ||
        hint.contains('children') ||
        hint.contains('kid')) {
      return children;
    }

    return adults;
  }

  Future<void> _openItemPicker(int dayIndex, int itemIndex) async {
    await _ensureRatesLoaded();
    if (!mounted) return;

    String selectedCategory = 'Transport';
    String query = '';

    final result = await showModalBottomSheet<_PickerResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, modalSetState) {
            final source = _ratesForCategory(selectedCategory);
            final list = query.trim().isEmpty
                ? source
                : source.where((row) {
                    final text = _rateLabel(
                      selectedCategory,
                      row,
                    ).toLowerCase();
                    return text.contains(query.toLowerCase());
                  }).toList();

            return Container(
              height: MediaQuery.of(ctx).size.height * 0.8,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD0D5DD),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Select Item',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: TextField(
                      onChanged: (v) => modalSetState(() => query = v),
                      decoration: InputDecoration(
                        hintText: 'Search item...',
                        prefixIcon: const Icon(Icons.search, size: 18),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: Color(0xFFD0D5DD),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children:
                          [
                            'Transport',
                            'Park Fees',
                            'Concession Fees',
                            'Others',
                          ].map((cat) {
                            final selected = selectedCategory == cat;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(cat),
                                selected: selected,
                                onSelected: (_) {
                                  modalSetState(() {
                                    selectedCategory = cat;
                                    query = '';
                                  });
                                },
                              ),
                            );
                          }).toList(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: selectedCategory == 'Others'
                        ? ListView(
                            children: [
                              ListTile(
                                leading: const Icon(Icons.add_circle_outline),
                                title: const Text('Use custom item'),
                                subtitle: const Text(
                                  'Enter item name manually in the row.',
                                ),
                                onTap: () => Navigator.pop(
                                  ctx,
                                  _PickerResult(category: 'Others'),
                                ),
                              ),
                            ],
                          )
                        : (_loadingRates
                              ? const Center(child: CircularProgressIndicator())
                              : ListView.builder(
                                  itemCount: list.length,
                                  itemBuilder: (_, i) {
                                    final row = list[i];
                                    return ListTile(
                                      leading: const Icon(
                                        Icons.inventory_2_outlined,
                                      ),
                                      title: Text(
                                        _rateLabel(selectedCategory, row),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: Text(
                                        _rateDescription(selectedCategory, row),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      onTap: () => Navigator.pop(
                                        ctx,
                                        _PickerResult(
                                          category: selectedCategory,
                                          product: row,
                                        ),
                                      ),
                                    );
                                  },
                                )),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (result == null) return;

    setState(() {
      final item = _daySections[dayIndex].items[itemIndex];
      if (result.category == 'Others') {
        item.item = 'Others';
        item.customItem = '';
        return;
      }

      final product = result.product ?? <String, dynamic>{};
      final rate = _extractRate(product);
      final qty = _autoQtyFromLead(result.category, product);
      final description = _rateDescription(result.category, product);
      item.item = result.category;
      if (description.isNotEmpty) {
        item.description = description;
      }
      item.unit = result.category == 'Transport' ? 'Vehicle' : 'Per person';
      item.rate = rate;
      if (qty > 0) {
        item.qty = qty;
      } else if (item.qty <= 0) {
        item.qty = 1;
      }
    });
  }

  Future<void> _save() async {
    final client = _clientCtrl.text.trim();
    if (client.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Client is required.')));
      return;
    }

    final invalidDayIndex = _daySections.indexWhere(
      (day) => _toIsoDate(day.dayDate).isEmpty,
    );
    if (invalidDayIndex != -1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please set a valid date for day ${invalidDayIndex + 1}.',
          ),
        ),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final preparedDaySections = <Map<String, dynamic>>[];
      final preparedLineItems = <Map<String, dynamic>>[];

      for (var i = 0; i < _daySections.length; i++) {
        final day = _daySections[i];
        final normalizedDayDate = _toIsoDate(day.dayDate);
        final normalizedDayTitle = normalizedDayDate.isNotEmpty
            ? normalizedDayDate
            : (day.dayTitle.trim().isEmpty ? 'Day ${i + 1}' : day.dayTitle);

        final dayItems = <Map<String, dynamic>>[];

        for (final item in day.items) {
          final hasAnyValue =
              item.item.trim().isNotEmpty ||
              item.customItem.trim().isNotEmpty ||
              item.description.trim().isNotEmpty ||
              item.qty > 0 ||
              item.rate > 0;

          if (!hasAnyValue) {
            continue;
          }

          final itemJson = item.toJson();
          final line = <String, dynamic>{
            'item': itemJson['item'],
            'customItem': itemJson['customItem'],
            'description': (itemJson['description'] ?? '').toString().trim(),
            'unit': (itemJson['unit'] ?? '').toString().trim(),
            'qty': item.qty,
            'rate': item.rate,
          };

          final lineWithDay = <String, dynamic>{
            'dayTitle': normalizedDayTitle,
            'dayDescription': day.dayDescription.trim(),
            ...line,
            'total': item.qty * item.rate,
          };

          dayItems.add(line);
          preparedLineItems.add(lineWithDay);
        }

        if (dayItems.isEmpty && day.dayDescription.trim().isEmpty) {
          continue;
        }

        preparedDaySections.add({
          'dayDate': normalizedDayDate,
          'dayTitle': normalizedDayTitle,
          'dayDescription': day.dayDescription.trim(),
          'items': dayItems,
        });
      }

      if (preparedDaySections.isEmpty || preparedLineItems.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please add at least one valid line item.'),
          ),
        );
        return;
      }

      final payload = {
        'leadId': (_selectedLeadId == null || _selectedLeadId!.isEmpty)
            ? null
            : _selectedLeadId,
        'client': client,
        'attention': _attentionCtrl.text.trim(),
        'quoteDate': _fmtDate(_quoteDate),
        'notes': _notesCtrl.text.trim(),
        'status': _quoteStatus,
        'daySections': preparedDaySections,
        'lineItems': preparedLineItems,
        'subtotal': _subtotal,
        'tax': _tax,
        'total': _grandTotal,
      };

      if (widget.editId != null) {
        await ApiService.put('/quotations/${widget.editId}', payload);
      } else {
        await ApiService.post('/quotations', payload);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
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

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          widget.editId != null ? 'Edit Quotation' : 'Create Quotation',
          style: const TextStyle(
            color: Color(0xFF101828),
            fontWeight: FontWeight.w700,
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF344054)),
      ),
      body: _loadingQuotation
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.fromLTRB(14, 14, 14, 88 + bottomInset),
              children: [
                Text(
                  widget.editId != null ? 'Edit Quotation' : 'Create Quotation',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF101828),
                    height: 1,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  widget.editId != null
                      ? 'Update quotation details and line items'
                      : 'Build and send a structured quotation with day sections',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF667085),
                  ),
                ),
                const SizedBox(height: 12),
                _card(title: 'Quotation Status', child: _statusChips()),
                const SizedBox(height: 12),
                _card(
                  title: 'Basic Information',
                  child: Column(
                    children: [
                      _label('Lead (optional)'),
                      const SizedBox(height: 8),
                      _leadDropdown(),
                      const SizedBox(height: 12),
                      _label('Client *'),
                      const SizedBox(height: 8),
                      _textField(
                        controller: _clientCtrl,
                        hint: 'Client company',
                        icon: Icons.business_outlined,
                      ),
                      const SizedBox(height: 12),
                      _label('Attention'),
                      const SizedBox(height: 8),
                      _textField(
                        controller: _attentionCtrl,
                        hint: 'Contact person',
                        icon: Icons.person_outline,
                      ),
                      const SizedBox(height: 12),
                      _label('Quotation Date'),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: _pickDate,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFD0D5DD)),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.calendar_month,
                                color: Color(0xFF667085),
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                _fmtDate(_quoteDate),
                                style: const TextStyle(
                                  color: Color(0xFF101828),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _label('Notes'),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _notesCtrl,
                        minLines: 3,
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText: 'Extra quotation notes...',
                          hintStyle: const TextStyle(fontSize: 13),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFFD0D5DD),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFFD0D5DD),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(kGoldColor),
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _card(
                  title: 'Itinerary / Day Sections',
                  trailing: OutlinedButton.icon(
                    onPressed: _addDay,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add Day'),
                  ),
                  child: Column(
                    children: List.generate(_daySections.length, (dayIndex) {
                      final day = _daySections[dayIndex];
                      return KeyedSubtree(
                        key: ValueKey(
                          'day-$dayIndex-${day.dayDate}-${day.dayDescription}',
                        ),
                        child: _timelineDayCard(dayIndex, day),
                      );
                    }),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE4E7EC)),
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Quotation Summary',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        '$_lineItemCount items | USD ${_subtotal.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF101828),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(kGoldColor),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'Saving...' : 'Save Quotation'),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _card({
    required String title,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF101828),
                  ),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _statusChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _statusOptions.map((status) {
        final ui = _statusUi(status);
        final selected = _quoteStatus == status;
        return InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => setState(() => _quoteStatus = status),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? ui.bg : Colors.white,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected ? ui.border : const Color(0xFFD0D5DD),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  ui.icon,
                  size: 14,
                  color: selected ? ui.fg : const Color(0xFF667085),
                ),
                const SizedBox(width: 6),
                Text(
                  status,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: selected ? ui.fg : const Color(0xFF475467),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _timelineDayCard(int dayIndex, _DayDraft day) {
    final isLast = dayIndex == _daySections.length - 1;
    const accents = [
      Color(0xFFE7C987),
      Color(0xFF9DD9BC),
      Color(0xFFBED5FF),
      Color(0xFFD7C5FF),
      Color(0xFFF5B2B5),
    ];
    final accent = accents[dayIndex % accents.length];
    final bg = Color.lerp(accent, Colors.white, 0.65) ?? Colors.white;

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 4,
                  height: 18,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Day',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF101828),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => _removeDay(dayIndex),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  color: const Color(0xFFEF4444),
                  tooltip: 'Remove day',
                ),
              ],
            ),
            const SizedBox(height: 6),
            _label('Day Date'),
            const SizedBox(height: 6),
            InkWell(
              onTap: () => _pickDayDate(dayIndex),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFD0D5DD)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.calendar_today_outlined,
                      size: 18,
                      color: Color(0xFF667085),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      day.dayDate.isEmpty ? 'Select day date' : day.dayDate,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: day.dayDate.isEmpty
                            ? const Color(0xFF98A2B3)
                            : const Color(0xFF101828),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            _label('Day Description'),
            const SizedBox(height: 6),
            TextFormField(
              key: ValueKey(
                'dayDesc-$dayIndex-${day.dayDate}-${day.dayDescription}',
              ),
              initialValue: day.dayDescription,
              onChanged: (v) => day.dayDescription = v,
              decoration: _inputDec(
                'Destination / route / notes',
                Icons.route_outlined,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Items',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _addItem(dayIndex),
                  icon: const Icon(Icons.add, size: 15),
                  label: const Text('Add Item'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ...List.generate(day.items.length, (itemIndex) {
              final item = day.items[itemIndex];
              return Container(
                margin: EdgeInsets.only(
                  bottom: itemIndex == day.items.length - 1 ? 0 : 8,
                ),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE4E7EC)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Line ${itemIndex + 1}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF475467),
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => _removeItem(dayIndex, itemIndex),
                          icon: const Icon(Icons.close_rounded, size: 16),
                          color: const Color(0xFFEF4444),
                          tooltip: 'Remove item',
                        ),
                      ],
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _openItemPicker(dayIndex, itemIndex),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF344054),
                        side: const BorderSide(color: Color(0xFFD0D5DD)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        minimumSize: const Size.fromHeight(44),
                        alignment: Alignment.centerLeft,
                      ),
                      icon: const Icon(Icons.add_circle_outline, size: 16),
                      label: Text(
                        item.item.isEmpty
                            ? 'Select item'
                            : (item.item == 'Others' &&
                                  item.customItem.trim().isNotEmpty)
                            ? 'Others - ${item.customItem.trim()}'
                            : item.item,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (item.item == 'Others') ...[
                      const SizedBox(height: 8),
                      TextFormField(
                        key: ValueKey(
                          'custom-${dayIndex}-${itemIndex}-${item.customItem}',
                        ),
                        initialValue: item.customItem,
                        onChanged: (v) => item.customItem = v,
                        decoration: _inputDec(
                          'Specify item',
                          Icons.edit_outlined,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    TextFormField(
                      key: ValueKey(
                        'desc-${dayIndex}-${itemIndex}-${item.description}',
                      ),
                      initialValue: item.description,
                      onChanged: (v) => item.description = v,
                      decoration: _inputDec(
                        'Description',
                        Icons.description_outlined,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      key: ValueKey(
                        'unit-${dayIndex}-${itemIndex}-${item.unit}',
                      ),
                      initialValue: item.unit,
                      onChanged: (v) => item.unit = v,
                      decoration: _inputDec(
                        'Unit (Per person, Vehicle...)',
                        Icons.straighten_outlined,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            key: ValueKey(
                              'qty-${dayIndex}-${itemIndex}-${item.qty}',
                            ),
                            initialValue: item.qty == 0
                                ? ''
                                : item.qty.toString(),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            onChanged: (v) {
                              item.qty = double.tryParse(v.trim()) ?? 0;
                              setState(() {});
                            },
                            decoration: _inputDec('Qty', Icons.tag_outlined),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            key: ValueKey(
                              'rate-${dayIndex}-${itemIndex}-${item.rate}',
                            ),
                            initialValue: item.rate == 0
                                ? ''
                                : item.rate.toString(),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            onChanged: (v) {
                              item.rate = double.tryParse(v.trim()) ?? 0;
                              setState(() {});
                            },
                            decoration: _inputDec(
                              'Rate',
                              Icons.attach_money_outlined,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'Line total: USD ${(item.qty * item.rate).toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF101828),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  _StatusChipUi _statusUi(String status) {
    switch (status) {
      case 'Pending':
        return const _StatusChipUi(
          bg: Color(0xFFFFF4DE),
          border: Color(0xFFF3D49A),
          fg: Color(0xFFB45309),
          icon: Icons.schedule,
        );
      case 'Sent':
        return const _StatusChipUi(
          bg: Color(0xFFEAF2FF),
          border: Color(0xFFBED5FF),
          fg: Color(0xFF1D4ED8),
          icon: Icons.send,
        );
      case 'Approved':
        return const _StatusChipUi(
          bg: Color(0xFFE9F8F0),
          border: Color(0xFF9DD9BC),
          fg: Color(0xFF0F9D67),
          icon: Icons.check_circle,
        );
      case 'Rejected':
        return const _StatusChipUi(
          bg: Color(0xFFFFEFEE),
          border: Color(0xFFF5B2B5),
          fg: Color(0xFFE5484D),
          icon: Icons.cancel,
        );
      case 'Converted':
        return const _StatusChipUi(
          bg: Color(0xFFF3EEFF),
          border: Color(0xFFD7C5FF),
          fg: Color(0xFF7C3AED),
          icon: Icons.receipt_long,
        );
      default:
        return const _StatusChipUi(
          bg: Color(0xFFF2F4F7),
          border: Color(0xFFD0D5DD),
          fg: Color(0xFF475467),
          icon: Icons.edit_note,
        );
    }
  }

  Widget _label(String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF344054),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
  }) {
    return TextField(controller: controller, decoration: _inputDec(hint, icon));
  }

  Widget _leadDropdown() {
    if (_loadingLeads) {
      return const LinearProgressIndicator(minHeight: 3);
    }

    return DropdownButtonFormField<String>(
      value: _selectedLeadId,
      isExpanded: true,
      decoration: _inputDec('Select lead', Icons.assignment_outlined),
      items: _leads.map((lead) {
        final id = (lead['id'] ?? '').toString();
        final ref = _leadText(lead, 'booking_ref', 'bookingRef');
        final client = _leadText(lead, 'client_company', 'clientCompany');
        final title = ref.isEmpty ? 'Lead #$id' : ref;
        final subtitle = client.isEmpty ? '' : ' - $client';
        return DropdownMenuItem<String>(
          value: id,
          child: Text(
            '$title$subtitle',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
          ),
        );
      }).toList(),
      onChanged: (value) {
        setState(() => _selectedLeadId = value);
        if (value != null) {
          _autofillFromLead(value);
        }
      },
    );
  }

  InputDecoration _inputDec(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF98A2B3)),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      prefixIcon: Icon(icon, size: 18, color: const Color(0xFF667085)),
      filled: true,
      fillColor: Colors.white,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFD0D5DD)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(kGoldColor), width: 1.4),
      ),
    );
  }
}

class _StatusChipUi {
  const _StatusChipUi({
    required this.bg,
    required this.border,
    required this.fg,
    required this.icon,
  });

  final Color bg;
  final Color border;
  final Color fg;
  final IconData icon;
}

class _PickerResult {
  const _PickerResult({required this.category, this.product});

  final String category;
  final Map<String, dynamic>? product;
}

class _DayDraft {
  _DayDraft({required int dayIndex})
    : dayTitle = 'Day $dayIndex',
      items = <_ItemDraft>[_ItemDraft()];

  String dayDate = '';
  String dayTitle;
  String dayDescription = '';
  List<_ItemDraft> items;

  Map<String, dynamic> toJson() {
    return {
      'dayDate': dayDate,
      'dayTitle': dayTitle,
      'dayDescription': dayDescription,
      'items': items.map((item) => item.toJson()).toList(),
    };
  }
}

class _ItemDraft {
  String item = '';
  String customItem = '';
  String description = '';
  String unit = 'Per person';
  double qty = 0;
  double rate = 0;

  Map<String, dynamic> toJson() {
    final itemName = item == 'Others' && customItem.trim().isNotEmpty
        ? customItem.trim()
        : item;

    return {
      'item': itemName,
      'customItem': customItem,
      'description': description,
      'unit': unit,
      'qty': qty,
      'rate': rate,
    };
  }
}
