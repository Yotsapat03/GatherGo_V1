import 'package:flutter/material.dart';

import '../localization/admin_strings.dart';
import 'report_models.dart';

class CardShell extends StatelessWidget {
  final Widget child;
  const CardShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFDCDCDC),
        borderRadius: BorderRadius.circular(10),
      ),
      child: child,
    );
  }
}

class SummaryField extends StatelessWidget {
  final String label;
  final String value;
  const SummaryField({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 130,
          child: Text(label, style: const TextStyle(fontSize: 12)),
        ),
        Expanded(
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(value, style: const TextStyle(fontSize: 12)),
          ),
        ),
      ],
    );
  }
}

class EventSummaryCard extends StatelessWidget {
  final RegistrationSummary summary;

  const EventSummaryCard({
    super.key,
    required this.summary,
  });

  @override
  Widget build(BuildContext context) {
    return CardShell(
      child: Column(
        children: [
          SummaryField(
            label: AdminStrings.text('total_events'),
            value: summary.totalEvents.toString().padLeft(2, '0'),
          ),
          const SizedBox(height: 8),
          SummaryField(
            label: AdminStrings.text('total_spot'),
            value: summary.totalSpot.toString().padLeft(2, '0'),
          ),
          const SizedBox(height: 8),
          SummaryField(
            label: AdminStrings.text('total_big_event'),
            value: summary.totalBigEvent.toString().padLeft(2, '0'),
          ),
        ],
      ),
    );
  }
}

class EmptyInfo extends StatelessWidget {
  const EmptyInfo({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        AdminStrings.text('empty_information'),
        style: const TextStyle(color: Colors.black54, fontSize: 14),
      ),
    );
  }
}

class PrimaryPurpleButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const PrimaryPurpleButton(
      {super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF6C63FF),
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class MiniDropdown extends StatelessWidget {
  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;

  const MiniDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          style: const TextStyle(fontSize: 12, color: Colors.black),
          items: items
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: (v) {
            if (v == null) return;
            onChanged(v);
          },
        ),
      ),
    );
  }
}

class SearchBarMini extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;

  const SearchBarMini({
    super.key,
    required this.controller,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(Icons.search, size: 18, color: Colors.black54),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              decoration: InputDecoration(
                hintText: AdminStrings.text('search'),
                border: InputBorder.none,
                isDense: true,
              ),
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
