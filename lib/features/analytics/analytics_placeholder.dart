// Analytics placeholder
import 'package:flutter/material.dart';

class AnalyticsPlaceholder extends StatelessWidget {
  const AnalyticsPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.auto_graph_rounded, size: 64, color: Color(0xFF2563EB)),
        const SizedBox(height: 16),
        Text('Analytics & AI Dashboard',
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(color: Colors.white)),
        const SizedBox(height: 8),
        Text('Phase 4 — Coming Soon',
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(color: Colors.white38)),
      ]),
    );
  }
}
