import 'package:flutter/material.dart';
import '../config/app_config.dart';

enum ResourceFieldType { text, number, date, select, textarea, itinerary }

class _ItineraryRowControllers {
  _ItineraryRowControllers({
    String date = '',
    String description = '',
    String allowance = '',
  }) : dateCtrl = TextEditingController(text: date),
       descriptionCtrl = TextEditingController(text: description),
       allowanceCtrl = TextEditingController(text: allowance);

  final TextEditingController dateCtrl;
  final TextEditingController descriptionCtrl;
  final TextEditingController allowanceCtrl;

  void dispose() {
    dateCtrl.dispose();
    descriptionCtrl.dispose();
    allowanceCtrl.dispose();
  }
}

typedef ResourceFieldValueSetter = void Function(String key, dynamic value);
typedef ResourceAutocompleteSelected =
    void Function(
      String fieldKey,
      String selectedValue,
      ResourceFieldValueSetter setValue,
    );
typedef ResourceFieldChanged =
    void Function(
      String fieldKey,
      dynamic value,
      ResourceFieldValueSetter setValue,
    );

class ResourceFormField {
  final String keyName;
  final String label;
  final ResourceFieldType type;
  final bool requiredField;
  final List<String> options;
  final int maxLines;
  final String? visibleWhenKey;
  final List<String> visibleWhenValues;

  const ResourceFormField({
    required this.keyName,
    required this.label,
    this.type = ResourceFieldType.text,
    this.requiredField = false,
    this.options = const <String>[],
    this.maxLines = 1,
    this.visibleWhenKey,
    this.visibleWhenValues = const <String>[],
  });
}

class ResourceFormDialog extends StatefulWidget {
  final String title;
  final List<ResourceFormField> fields;
  final Map<String, dynamic>? initialValues;
  final ResourceAutocompleteSelected? onAutocompleteSelected;
  final ResourceFieldChanged? onFieldChanged;

  const ResourceFormDialog({
    super.key,
    required this.title,
    required this.fields,
    this.initialValues,
    this.onAutocompleteSelected,
    this.onFieldChanged,
  });

  @override
  State<ResourceFormDialog> createState() => _ResourceFormDialogState();
}

class _ResourceFormDialogState extends State<ResourceFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers =
      <String, TextEditingController>{};
  final Map<String, FocusNode> _focusNodes = <String, FocusNode>{};
  final Map<String, String> _selectValues = <String, String>{};
  final Map<String, List<_ItineraryRowControllers>> _itineraryRows =
      <String, List<_ItineraryRowControllers>>{};

  @override
  void initState() {
    super.initState();
    for (final field in widget.fields) {
      final value = widget.initialValues?[field.keyName]?.toString() ?? '';
      if (field.type == ResourceFieldType.select) {
        final hasValue = value.isNotEmpty && field.options.contains(value);
        _selectValues[field.keyName] = hasValue
            ? value
            : (field.options.isNotEmpty ? field.options.first : '');
      } else if (field.type == ResourceFieldType.itinerary) {
        _itineraryRows[field.keyName] = _buildItineraryRows(
          widget.initialValues?[field.keyName],
        );
      } else {
        _controllers[field.keyName] = TextEditingController(text: value);
        _focusNodes[field.keyName] = FocusNode();
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final f in _focusNodes.values) {
      f.dispose();
    }
    for (final rows in _itineraryRows.values) {
      for (final row in rows) {
        row.dispose();
      }
    }
    super.dispose();
  }

  List<_ItineraryRowControllers> _buildItineraryRows(dynamic raw) {
    final rows = <_ItineraryRowControllers>[];

    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          final map = Map<String, dynamic>.from(item);
          final date = (map['date'] ?? '').toString();
          final description =
              (map['dayDescription'] ?? map['description'] ?? '').toString();
          final allowance =
              (map['allowancePerDay'] ?? map['allowance_per_day'] ?? '')
                  .toString();
          rows.add(
            _ItineraryRowControllers(
              date: date,
              description: description,
              allowance: allowance,
            ),
          );
        } else if (item is String && item.trim().isNotEmpty) {
          rows.add(_ItineraryRowControllers(description: item.trim()));
        }
      }
    }

    if (rows.isEmpty) {
      rows.add(_ItineraryRowControllers());
    }
    return rows;
  }

  List<Map<String, dynamic>> _itineraryPayload(String key) {
    final rows = _itineraryRows[key] ?? <_ItineraryRowControllers>[];
    return rows
        .map((row) {
          final date = row.dateCtrl.text.trim();
          final description = row.descriptionCtrl.text.trim();
          final allowanceText = row.allowanceCtrl.text.trim();
          final allowance = allowanceText.isEmpty
              ? null
              : num.tryParse(allowanceText);
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

  void _notifyItineraryChanged(String key) {
    widget.onFieldChanged?.call(key, _itineraryPayload(key), _setFieldValue);
  }

  void _addItineraryRow(String key) {
    setState(() {
      _itineraryRows.putIfAbsent(key, () => <_ItineraryRowControllers>[]);
      _itineraryRows[key]!.add(_ItineraryRowControllers());
    });
    _notifyItineraryChanged(key);
  }

  void _removeItineraryRow(String key, int index) {
    final rows = _itineraryRows[key];
    if (rows == null || rows.length <= 1 || index < 0 || index >= rows.length) {
      return;
    }
    setState(() {
      final row = rows.removeAt(index);
      row.dispose();
    });
    _notifyItineraryChanged(key);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.initialValues != null;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: theme.colorScheme.outline, width: 0.8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 26,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFF5DB), Color(0xFFFFFFFF)],
                    ),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                    border: Border(
                      bottom: BorderSide(
                        color: theme.colorScheme.outline,
                        width: 0.6,
                      ),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF4E3A4),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.tour_outlined,
                          color: Color(kGoldColor),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.title,
                              style: TextStyle(
                                color: theme.colorScheme.onSurface,
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isEditing
                                  ? 'Update the trip request and client details below.'
                                  : 'Capture client, trip, and passenger details in one clean form.',
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(
                          Icons.close,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [...widget.fields.map(_buildField)],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: theme.colorScheme.onSurfaceVariant,
                          side: BorderSide(color: theme.colorScheme.outline),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        onPressed: _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: theme.colorScheme.onPrimary,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.save_outlined, size: 18),
                        label: const Text('Save Lead'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _setFieldValue(String key, dynamic value) {
    final field = widget.fields.cast<ResourceFormField?>().firstWhere(
      (f) => f?.keyName == key,
      orElse: () => null,
    );
    if (field == null) return;

    if (field.type == ResourceFieldType.select) {
      final textValue = (value ?? '').toString();
      if (textValue.isNotEmpty &&
          field.options.isNotEmpty &&
          !field.options.contains(textValue)) {
        return;
      }
      setState(() => _selectValues[key] = textValue);
      return;
    }

    if (field.type == ResourceFieldType.itinerary) {
      final oldRows = _itineraryRows[key] ?? <_ItineraryRowControllers>[];
      for (final row in oldRows) {
        row.dispose();
      }
      _itineraryRows[key] = _buildItineraryRows(value);
      setState(() {});
      _notifyItineraryChanged(key);
      return;
    }

    final controller = _controllers[key];
    if (controller == null) return;
    controller.text = (value ?? '').toString();
    setState(() {});
  }

  Widget _buildField(ResourceFormField field) {
    if (!_isFieldVisible(field)) {
      return const SizedBox.shrink();
    }

    final label = field.requiredField ? '${field.label} *' : field.label;
    final uniqueOptions = field.options.toSet().toList();

    if (field.type == ResourceFieldType.text && field.options.isNotEmpty) {
      return _fieldShell(
        label: label,
        child: RawAutocomplete<String>(
          textEditingController: _controllers[field.keyName],
          focusNode: _focusNodes[field.keyName],
          optionsBuilder: (TextEditingValue textEditingValue) {
            final q = textEditingValue.text.trim().toLowerCase();
            if (q.isEmpty) {
              return uniqueOptions.take(8);
            }
            return uniqueOptions
                .where((o) => o.toLowerCase().contains(q))
                .take(8);
          },
          onSelected: (value) {
            _setFieldValue(field.keyName, value);
            widget.onAutocompleteSelected?.call(
              field.keyName,
              value,
              _setFieldValue,
            );
          },
          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
            return TextFormField(
              controller: controller,
              focusNode: focusNode,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              decoration: _decoration(
                hintText: 'Type to search, or enter manually',
                suffixIcon: Icon(
                  Icons.search_rounded,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  size: 18,
                ),
              ),
              validator: (value) {
                if (field.requiredField &&
                    (value == null || value.trim().isEmpty)) {
                  return '${field.label} is required';
                }
                return null;
              },
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            final list = options.toList(growable: false);
            if (list.isEmpty) return const SizedBox.shrink();
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(12),
                color: Theme.of(context).colorScheme.surface,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxHeight: 220,
                    minWidth: 280,
                    maxWidth: 520,
                  ),
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    shrinkWrap: true,
                    itemCount: list.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    itemBuilder: (context, index) {
                      final option = list[index];
                      return InkWell(
                        onTap: () => onSelected(option),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Text(
                            option,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      );
    }

    if (field.type == ResourceFieldType.select) {
      final rawValue =
          _selectValues[field.keyName] ??
          (uniqueOptions.isNotEmpty ? uniqueOptions.first : '');
      final value = uniqueOptions.contains(rawValue) ? rawValue : '';
      return _fieldShell(
        label: label,
        child: DropdownButtonFormField<String>(
          initialValue: value.isNotEmpty ? value : null,
          dropdownColor: Theme.of(context).colorScheme.surface,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          iconEnabledColor: Theme.of(context).colorScheme.onSurfaceVariant,
          decoration: _decoration(),
          items: uniqueOptions
              .map(
                (option) => DropdownMenuItem<String>(
                  value: option,
                  child: Text(
                    option,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: (value) {
            final next = value ?? '';
            setState(() => _selectValues[field.keyName] = next);
            widget.onFieldChanged?.call(field.keyName, next, _setFieldValue);
          },
          validator: (value) {
            if (field.requiredField &&
                (value == null || value.trim().isEmpty)) {
              return '${field.label} is required';
            }
            return null;
          },
        ),
      );
    }

    if (field.type == ResourceFieldType.date) {
      return _fieldShell(
        label: label,
        child: TextFormField(
          controller: _controllers[field.keyName],
          readOnly: true,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          decoration: _decoration(
            hintText: 'Select date',
            suffixIcon: Icon(
              Icons.calendar_today_outlined,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              size: 18,
            ),
          ),
          onTap: () => _selectDate(field.keyName),
          validator: (value) {
            if (field.requiredField &&
                (value == null || value.trim().isEmpty)) {
              return '${field.label} is required';
            }
            return null;
          },
        ),
      );
    }

    if (field.type == ResourceFieldType.textarea) {
      final effectiveMaxLines = field.maxLines > 1 ? field.maxLines : 4;
      final effectiveMinLines = effectiveMaxLines >= 3 ? 3 : effectiveMaxLines;
      return _fieldShell(
        label: label,
        child: TextFormField(
          controller: _controllers[field.keyName],
          maxLines: effectiveMaxLines,
          minLines: effectiveMinLines,
          keyboardType: TextInputType.multiline,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          decoration: _decoration(
            hintText: 'Enter ${field.label.toLowerCase()}',
          ),
          validator: (value) {
            if (field.requiredField &&
                (value == null || value.trim().isEmpty)) {
              return '${field.label} is required';
            }
            return null;
          },
        ),
      );
    }

    if (field.type == ResourceFieldType.itinerary) {
      final rows =
          _itineraryRows[field.keyName] ?? <_ItineraryRowControllers>[];
      return _fieldShell(
        label: label,
        child: Column(
          children: [
            ...List<Widget>.generate(rows.length, (index) {
              final row = rows[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline,
                    width: 0.7,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Line Item ${index + 1}',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove line',
                          onPressed: rows.length > 1
                              ? () => _removeItineraryRow(field.keyName, index)
                              : null,
                          icon: const Icon(Icons.delete_outline, size: 18),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: row.dateCtrl,
                      readOnly: true,
                      decoration: _decoration(
                        hintText: 'Date',
                        suffixIcon: Icon(
                          Icons.calendar_today_outlined,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          size: 18,
                        ),
                      ),
                      onTap: () => _selectItineraryDate(field.keyName, index),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: row.descriptionCtrl,
                      onChanged: (_) => _notifyItineraryChanged(field.keyName),
                      decoration: _decoration(hintText: 'Day Description'),
                      validator: (value) {
                        if (!field.requiredField) return null;
                        final hasAny = rows.any((r) {
                          final date = r.dateCtrl.text.trim();
                          final desc = r.descriptionCtrl.text.trim();
                          final allw = r.allowanceCtrl.text.trim();
                          return date.isNotEmpty ||
                              desc.isNotEmpty ||
                              allw.isNotEmpty;
                        });
                        if (!hasAny) {
                          return '${field.label} requires at least one line item';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: row.allowanceCtrl,
                      onChanged: (_) => _notifyItineraryChanged(field.keyName),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: _decoration(hintText: 'Allowance Per Day'),
                    ),
                  ],
                ),
              );
            }),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _addItineraryRow(field.keyName),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Line Item'),
              ),
            ),
          ],
        ),
      );
    }

    final keyboardType = field.type == ResourceFieldType.number
        ? const TextInputType.numberWithOptions(decimal: true)
        : TextInputType.text;

    return _fieldShell(
      label: label,
      child: TextFormField(
        controller: _controllers[field.keyName],
        keyboardType: keyboardType,
        maxLines: field.maxLines,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        decoration: _decoration(hintText: 'Enter ${field.label.toLowerCase()}'),
        validator: (value) {
          if (field.requiredField && (value == null || value.trim().isEmpty)) {
            return '${field.label} is required';
          }
          return null;
        },
      ),
    );
  }

  bool _isFieldVisible(ResourceFormField field) {
    if (field.visibleWhenKey == null || field.visibleWhenValues.isEmpty) {
      return true;
    }
    final parentKey = field.visibleWhenKey!;
    final selected = _selectValues[parentKey] ?? '';
    return field.visibleWhenValues.contains(selected);
  }

  Widget _fieldShell({required String label, required Widget child}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 6),
            child: Text(
              label,
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }

  InputDecoration _decoration({String? hintText, Widget? suffixIcon}) {
    final theme = Theme.of(context);
    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: theme.colorScheme.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: theme.colorScheme.outline, width: 0.8),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(color: Color(kGoldColor), width: 1.2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: theme.colorScheme.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: theme.colorScheme.error, width: 1.2),
      ),
    );
  }

  Future<void> _selectDate(String fieldKey) async {
    final controller = _controllers[fieldKey];
    if (controller == null) return;

    final currentText = controller.text.trim();
    DateTime? initialDate;

    if (currentText.isNotEmpty) {
      try {
        initialDate = DateTime.parse(currentText);
      } catch (_) {
        initialDate = null;
      }
    }

    final selected = await showDatePicker(
      context: context,
      initialDate: initialDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (context, child) {
        final theme = Theme.of(context);
        return Theme(
          data: theme.copyWith(
            colorScheme: theme.colorScheme.copyWith(
              primary: const Color(kGoldColor),
              surface: theme.colorScheme.surface,
              onSurface: theme.colorScheme.onSurface,
            ),
          ),
          child: child ?? const SizedBox(),
        );
      },
    );

    if (selected != null) {
      final formatted = selected.toIso8601String().split('T').first;
      controller.text = formatted;
      setState(() {});
      widget.onFieldChanged?.call(fieldKey, formatted, _setFieldValue);
    }
  }

  Future<void> _selectItineraryDate(String fieldKey, int index) async {
    final rows = _itineraryRows[fieldKey];
    if (rows == null || index < 0 || index >= rows.length) return;

    final controller = rows[index].dateCtrl;
    final currentText = controller.text.trim();
    DateTime? initialDate;

    if (currentText.isNotEmpty) {
      try {
        initialDate = DateTime.parse(currentText);
      } catch (_) {
        initialDate = null;
      }
    }

    final selected = await showDatePicker(
      context: context,
      initialDate: initialDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (context, child) {
        final theme = Theme.of(context);
        return Theme(
          data: theme.copyWith(
            colorScheme: theme.colorScheme.copyWith(
              primary: const Color(kGoldColor),
              surface: theme.colorScheme.surface,
              onSurface: theme.colorScheme.onSurface,
            ),
          ),
          child: child ?? const SizedBox(),
        );
      },
    );

    if (selected != null) {
      controller.text = selected.toIso8601String().split('T').first;
      setState(() {});
      _notifyItineraryChanged(fieldKey);
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final payload = <String, dynamic>{};
    for (final field in widget.fields) {
      if (field.type == ResourceFieldType.select) {
        payload[field.keyName] = _selectValues[field.keyName] ?? '';
      } else if (field.type == ResourceFieldType.itinerary) {
        final rows =
            _itineraryRows[field.keyName] ?? <_ItineraryRowControllers>[];
        payload[field.keyName] = rows
            .map((row) {
              final date = row.dateCtrl.text.trim();
              final description = row.descriptionCtrl.text.trim();
              final allowanceText = row.allowanceCtrl.text.trim();
              final allowance = allowanceText.isEmpty
                  ? null
                  : num.tryParse(allowanceText);
              return <String, dynamic>{
                'date': date,
                'dayDescription': description,
                'allowancePerDay': allowance,
              };
            })
            .where((row) {
              final date = (row['date'] ?? '').toString().trim();
              final description = (row['dayDescription'] ?? '')
                  .toString()
                  .trim();
              final allowance = row['allowancePerDay'];
              return date.isNotEmpty ||
                  description.isNotEmpty ||
                  allowance != null;
            })
            .toList();
      } else {
        payload[field.keyName] = _controllers[field.keyName]?.text.trim() ?? '';
      }
    }

    Navigator.pop(context, payload);
  }
}
