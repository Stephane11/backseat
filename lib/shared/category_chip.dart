import 'package:flutter/material.dart';

import '../core/models/analysis.dart';

String categoryLabel(ItemCategory category) {
  return switch (category) {
    ItemCategory.statistics => 'Statistics',
    ItemCategory.ml => 'ML',
    ItemCategory.aiEngineering => 'AI engineering',
    ItemCategory.dataEngineering => 'Data engineering',
    ItemCategory.delivery => 'Delivery',
    ItemCategory.other => 'Other',
  };
}

class CategoryChip extends StatelessWidget {
  const CategoryChip({super.key, required this.category});

  final ItemCategory category;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(categoryLabel(category)),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
