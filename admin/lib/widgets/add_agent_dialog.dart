import 'package:flutter/material.dart';

/// Quick "+ NEW AGENT" dialog shared by the Gym Delivery and Subscription
/// Delivery pages, so a manager can grow the delivery_agents roster without
/// needing developer-only Settings access.
Future<void> showAddAgentDialog(
  BuildContext context, {
  required Future<String?> Function(String name, String phone) onAdd,
}) async {
  final name = TextEditingController();
  final phone = TextEditingController();

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('New delivery agent'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Name')),
          TextField(
              controller: phone,
              decoration: const InputDecoration(labelText: 'Phone')),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ADD')),
      ],
    ),
  );
  if (ok != true) return;
  if (name.text.trim().isEmpty) return;

  final err = await onAdd(name.text.trim(), phone.text.trim());
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(err ?? 'Agent added ✅'),
    backgroundColor: err == null ? Colors.green[700] : Colors.red[700],
  ));
}
