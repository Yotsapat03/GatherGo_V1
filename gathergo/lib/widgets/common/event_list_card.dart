import 'package:flutter/material.dart';

class EventListCard extends StatelessWidget {
  final Widget image;
  final String title;
  final List<String> chips;
  final Widget? badge;
  final VoidCallback? onTap;
  final Widget? imageFooter;
  final Color chipBackgroundColor;
  final Color chipBorderColor;

  const EventListCard({
    super.key,
    required this.image,
    required this.title,
    required this.chips,
    this.badge,
    this.onTap,
    this.imageFooter,
    this.chipBackgroundColor = const Color(0xFFF5F5F5),
    this.chipBorderColor = const Color(0xFFE0E0E0),
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(14, 14, 18, 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFD8DEE8)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 88,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(
                        width: 88,
                        height: 88,
                        child: image,
                      ),
                    ),
                    if (imageFooter != null) ...[
                      const SizedBox(height: 8),
                      imageFooter!,
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 10),
                          badge!,
                        ],
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.chevron_right,
                          color: Color(0xFF98A2B3),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: chips
                          .where((chip) =>
                              chip.trim().isNotEmpty && chip.trim() != '-')
                          .map(
                            (chip) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: chipBackgroundColor,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: chipBorderColor,
                                ),
                              ),
                              child: Text(
                                chip,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
