import 'package:flutter/material.dart';

class DistanceFilterRange {
  final String label;
  final double? minKm;
  final double? maxKm;
  final bool includeMin;

  const DistanceFilterRange({
    required this.label,
    this.minKm,
    this.maxKm,
    this.includeMin = false,
  });
}

class SearchFiltersValue {
  final DistanceFilterRange? distanceRange;
  final String? province;

  const SearchFiltersValue({
    this.distanceRange,
    this.province,
  });
}

const List<DistanceFilterRange> kDistanceFilterRanges = [
  DistanceFilterRange(label: '1–5 km', minKm: 1, maxKm: 5, includeMin: true),
  DistanceFilterRange(label: '5–10 km', minKm: 5, maxKm: 10),
  DistanceFilterRange(label: '10–15 km', minKm: 10, maxKm: 15),
  DistanceFilterRange(label: '15–20 km', minKm: 15, maxKm: 20),
  DistanceFilterRange(label: '25–30 km', minKm: 25, maxKm: 30),
  DistanceFilterRange(label: '>30 km', minKm: 30, maxKm: null),
];

Future<SearchFiltersValue?> showSearchFiltersBottomSheet({
  required BuildContext context,
  DistanceFilterRange? selectedDistanceRange,
  String? selectedProvince,
  required List<String> provinces,
}) {
  var tempDistance = selectedDistanceRange;
  var tempProvince = selectedProvince;

  return showModalBottomSheet<SearchFiltersValue>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                16 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Filters',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Distance Filter (Total KM)',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: kDistanceFilterRanges.map((range) {
                      final selected = tempDistance?.label == range.label;
                      return ChoiceChip(
                        label: Text(range.label),
                        selected: selected,
                        onSelected: (_) {
                          setModalState(() {
                            tempDistance = selected ? null : range;
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Province Filter',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: provinces.map((province) {
                      final selected = tempProvince == province;
                      return ChoiceChip(
                        label: Text(province),
                        selected: selected,
                        onSelected: (_) {
                          setModalState(() {
                            tempProvince = selected ? null : province;
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.pop(
                              context,
                              const SearchFiltersValue(
                                distanceRange: null,
                                province: null,
                              ),
                            );
                          },
                          child: const Text('Clear'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(
                              context,
                              SearchFiltersValue(
                                distanceRange: tempDistance,
                                province: tempProvince,
                              ),
                            );
                          },
                          child: const Text('Apply'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
