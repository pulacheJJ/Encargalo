import 'package:flutter/material.dart';
import '../domain/location_entry.dart';
import '../data/peru_location_catalog.dart';

/// Dependent, validated selection, not three unrelated free-text addresses.
/// Bundled real catalog works offline; cloud refresh never blocks the form.
class LocationSelector extends StatefulWidget {
  final String? initialCode, initialDistrict, allowedRegion;
  final ValueChanged<LocationEntry> onChanged;
  final LocationCatalog? catalog;
  const LocationSelector({
    super.key,
    this.initialCode,
    this.initialDistrict,
    this.allowedRegion,
    required this.onChanged,
    this.catalog,
  });
  @override
  State<LocationSelector> createState() => _LocationSelectorState();
}

class _LocationSelectorState extends State<LocationSelector> {
  late final LocationCatalog catalog;
  List<LocationEntry> rows = [];
  String? region, province, code;
  String? error;
  @override
  void initState() {
    super.initState();
    catalog = widget.catalog ?? PeruLocationCatalog();
    _load();
  }

  Future<void> _load() async {
    try {
      final all = await catalog.bundled();
      if (!mounted) return;
      rows =
          all
              .where(
                (e) =>
                    widget.allowedRegion == null ||
                    e.region == widget.allowedRegion,
              )
              .toList();
      final matches = rows.where(
        (e) =>
            widget.initialCode != null
                ? e.code == widget.initialCode
                : e.region == 'Piura' &&
                    e.district.toLowerCase() ==
                        (widget.initialDistrict ?? 'Piura').toLowerCase(),
      );
      final selected =
          matches.isEmpty
              ? rows.firstWhere(
                (e) => e.code == '200101',
                orElse: () => rows.first,
              )
              : matches.first;
      setState(() {
        region = selected.region;
        province = selected.province;
        code = selected.code;
      });
      widget.onChanged(selected);
      _refresh(selected.region);
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              error =
                  'No se pudo cargar el catálogo territorial. Reabre el formulario.',
        );
      }
    }
  }

  Future<void> _refresh(String selectedRegion) async {
    try {
      final refreshed = await catalog.refresh(selectedRegion);
      if (!mounted) return;
      setState(() {
        rows = [...rows.where((e) => e.region != selectedRegion), ...refreshed];
      });
    } catch (_) {
      /* Keep the real, versioned catalog; no fake locations. */
    }
  }

  @override
  void dispose() {
    if (widget.catalog == null) (catalog as PeruLocationCatalog).dispose();
    super.dispose();
  }

  void _selected(String value) {
    final selected = rows.firstWhere((e) => e.code == value);
    setState(() => code = value);
    widget.onChanged(selected);
  }

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Text(
        error!,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      );
    }
    if (rows.isEmpty) return const LinearProgressIndicator();
    final regions = rows.map((e) => e.region).toSet().toList()..sort();
    final provinces =
        rows
            .where((e) => e.region == region)
            .map((e) => e.province)
            .toSet()
            .toList()
          ..sort();
    final districts =
        rows.where((e) => e.region == region && e.province == province).toList()
          ..sort((a, b) => a.district.compareTo(b.district));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          value: region,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Región',
            prefixIcon: Icon(Icons.public_outlined),
          ),
          items:
              regions
                  .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                  .toList(),
          onChanged:
              widget.allowedRegion != null
                  ? null
                  : (value) {
                    if (value == null) return;
                    final first = rows.firstWhere((e) => e.region == value);
                    setState(() {
                      region = value;
                      province = first.province;
                      code = first.code;
                    });
                    widget.onChanged(first);
                    _refresh(value);
                  },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: province,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Provincia'),
          items:
              provinces
                  .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                  .toList(),
          onChanged: (value) {
            if (value == null) return;
            final first = rows.firstWhere(
              (e) => e.region == region && e.province == value,
            );
            setState(() {
              province = value;
              code = first.code;
            });
            widget.onChanged(first);
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: districts.any((e) => e.code == code) ? code : null,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Distrito',
            prefixIcon: Icon(Icons.location_on_outlined),
          ),
          items:
              districts
                  .map(
                    (d) => DropdownMenuItem(
                      value: d.code,
                      child: Text(d.district),
                    ),
                  )
                  .toList(),
          validator: (value) => value == null ? 'Selecciona tu distrito' : null,
          onChanged: (value) {
            if (value != null) _selected(value);
          },
        ),
      ],
    );
  }
}
