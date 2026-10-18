import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';

class JointScreen extends StatefulWidget {
  const JointScreen({super.key});
  @override
  State<JointScreen> createState() => _JointScreenState();
}

class _JointScreenState extends State<JointScreen> {
  final amount = TextEditingController(),
      reason = TextEditingController(),
      limit = TextEditingController();
  Timer? timer;
  Map<String, dynamic>? member;
  List<dynamic> payments = [];
  String? recipient, error;
  bool busy = false, refreshing = false;

  @override
  void initState() {
    super.initState();
    refresh();
    timer = Timer.periodic(const Duration(seconds: 10), (_) => refresh());
  }

  @override
  void dispose() {
    timer?.cancel();
    amount.dispose();
    reason.dispose();
    limit.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    if (refreshing) return;
    refreshing = true;
    try {
      final m = await ApiService.jointMembership();
      final response = m['has_joint_account'] == true
          ? await ApiService.jointPayments()
          : <String, dynamic>{};
      if (mounted)
        setState(() {
          member = m;
          payments = response['payments'] as List? ?? [];
          error = null;
        });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      refreshing = false;
    }
  }

  Future<void> act(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
      await refresh();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  double readAmount(TextEditingController c, {bool allowZero = false}) {
    final text = c.text.trim(), value = double.tryParse(c.text.trim());
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(text) ||
        value == null ||
        !value.isFinite ||
        value > 1000000 ||
        (allowZero ? value < 0 : value <= 0)) {
      throw const FormatException(
          'Enter a valid amount with at most two decimal places.');
    }
    return value;
  }

  Future<bool> confirm(String title, String message) async =>
      await showDialog<bool>(
          context: context,
          builder: (ctx) =>
              AlertDialog(title: Text(title), content: Text(message), actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Confirm')),
              ])) ??
      false;

  String status(dynamic p) => switch (p['status']) {
        'awaiting_primary' => 'Waiting for primary holder approval',
        'approved' =>
          'Approved by your trusted primary holder. You may proceed.',
        'declined' => 'Declined by the primary holder. Payment cannot proceed.',
        'ready' => 'Ready for your confirmation',
        'processing' => 'Sending to Nessie sandbox',
        'submitted' => 'Submitted to Nessie sandbox',
        'completed' => 'Completed in Nessie sandbox',
        'failed' => 'Cancelled in Nessie sandbox',
        'unknown' =>
          'Outcome unknown. Contact support before making another payment.',
        _ => p['status'].toString(),
      };

  @override
  Widget build(BuildContext context) {
    final m = member, primary = member?['role'] == 'primary';
    final recipients = m?['recipients'] as List? ?? [];
    return RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Row(children: [
                const Expanded(
                    child: Text('Joint account',
                        style: TextStyle(
                            fontSize: 23, fontWeight: FontWeight.bold))),
                IconButton(
                    onPressed: refresh,
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Refresh')
              ]),
              if (error != null)
                Text(error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              if (m == null) const Center(child: CircularProgressIndicator()),
              if (m != null && m['has_joint_account'] != true)
                const Text('No joint account is linked to your profile.'),
              if (m?['has_joint_account'] == true) ...[
                Text(
                    '${m!['account_name']} · ${primary ? 'Primary holder' : 'Dependent holder'}'),
                Text(m['threshold'] == null
                    ? 'No limit set. Every dependent payment needs primary review.'
                    : 'Dependent payments above \$${m['threshold']} need primary approval.'),
                const Text('Suspicious payments also require primary review.'),
                if (primary)
                  Card(
                      child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(children: [
                            TextField(
                                controller: limit,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                decoration: const InputDecoration(
                                    labelText:
                                        'Dependent approval limit (USD)')),
                            FilledButton(
                                onPressed: busy
                                    ? null
                                    : () => act(() async {
                                          await ApiService.setJointLimit(
                                              readAmount(limit,
                                                  allowZero: true));
                                          limit.clear();
                                        }),
                                child: const Text('Save approval limit')),
                          ]))),
                Card(
                    child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(children: [
                          const Text('New sandbox payment',
                              style: TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.bold)),
                          TextField(
                              controller: amount,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: const InputDecoration(
                                  labelText: 'Amount (USD)')),
                          DropdownButtonFormField<String>(
                              initialValue: recipient,
                              decoration: const InputDecoration(
                                  labelText: 'Recipient / merchant'),
                              items: [
                                for (final r in recipients)
                                  DropdownMenuItem<String>(
                                      value: r['id'].toString(),
                                      child: Text(r['name'].toString()))
                              ],
                              onChanged: busy
                                  ? null
                                  : (v) => setState(() => recipient = v)),
                          TextField(
                              controller: reason,
                              maxLength: 500,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                  labelText: 'Payment reason')),
                          const Text(
                              'The merchant and reason are sent to Gemini for scam-risk review. This assessment is advisory.'),
                          FilledButton(
                              onPressed: busy || recipients.isEmpty
                                  ? null
                                  : () => act(() async {
                                        final value = readAmount(amount);
                                        if (recipient == null ||
                                            reason.text.trim().length < 3) {
                                          throw const FormatException(
                                              'Select a recipient and enter a payment reason.');
                                        }
                                        if (!await confirm(
                                            'Create payment request?',
                                            'Review a \$$value payment. No money is sent yet.'))
                                          return;
                                        await ApiService.proposeJointPayment(
                                            amount: value,
                                            recipientId: recipient!,
                                            reason: reason.text.trim());
                                        amount.clear();
                                        reason.clear();
                                      }),
                              child: const Text('Review payment')),
                          if (recipients.isEmpty)
                            const Text(
                                'Ask the administrator to link Nessie recipients.'),
                        ]))),
                if (busy) const LinearProgressIndicator(),
                Text(
                    primary
                        ? 'Payment requests and activity'
                        : 'Your requests and notifications',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                if (payments.isEmpty) const Text('No payments yet.'),
                for (final p in payments)
                  Card(
                      child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text('${p['merchant']} · \$${p['amount']}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                Text(p['reason'].toString()),
                                const SizedBox(height: 8),
                                Text(status(p)),
                                Text(p['assessment']['reason'].toString()),
                                if (p['status'] == 'submitted')
                                  TextButton(
                                      onPressed: busy
                                          ? null
                                          : () => act(() async {
                                                await ApiService
                                                    .reconcileJointPayment(
                                                        p['id'].toString());
                                              }),
                                      child: const Text('Check bank status')),
                                if (p['assessment']['over_limit'] == true)
                                  const Text(
                                      'Above the limit, or no limit has been set.'),
                                if (p['can_decide'] == true)
                                  Row(children: [
                                    for (final approve in [false, true])
                                      Expanded(
                                          child: TextButton(
                                              onPressed: busy
                                                  ? null
                                                  : () => act(() async {
                                                        if (await confirm(
                                                            approve
                                                                ? 'Approve payment?'
                                                                : 'Decline payment?',
                                                            'The dependent will see your decision. Approval does not send money.')) {
                                                          await ApiService
                                                              .decideJointPayment(
                                                                  p['id']
                                                                      .toString(),
                                                                  approve);
                                                        }
                                                      }),
                                              child: Text(approve
                                                  ? 'Approve'
                                                  : 'Decline'))),
                                  ]),
                                if (p['can_execute'] == true)
                                  FilledButton(
                                      onPressed: busy ||
                                              m['execution_enabled'] != true
                                          ? null
                                          : () => act(() async {
                                                if (await confirm(
                                                    'Send sandbox payment?',
                                                    'Send \$${p['amount']} to ${p['merchant']} through Nessie sandbox?')) {
                                                  await ApiService
                                                      .executeJointPayment(
                                                          p['id'].toString());
                                                }
                                              }),
                                      child:
                                          const Text('Proceed with payment')),
                              ]))),
                if (m['execution_enabled'] != true)
                  const Text(
                      'Nessie execution is not enabled on the backend yet.'),
                const Text(
                    'Nessie sandbox only. These controls apply to payments initiated in CreditPilot.'),
              ],
            ]));
  }
}
