import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';

class JointScreen extends StatefulWidget {
  const JointScreen({super.key});
  @override
  State<JointScreen> createState() => _JointScreenState();
}

class _JointScreenState extends State<JointScreen> {
  final amountController = TextEditingController(text: '850');
  final merchantController = TextEditingController(text: 'Electronics Store');
  Map<String, dynamic>? result;
  String? error, proposalId, proposalStatus;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    evaluate();
  }

  @override
  void dispose() {
    amountController.dispose();
    merchantController.dispose();
    super.dispose();
  }

  double get value => double.tryParse(amountController.text) ?? 0;

  Future<void> evaluate() async {
    if (value <= 0) {
      setState(() => error = 'Enter a valid positive amount');
      return;
    }
    setState(() { loading = true; error = null; });
    try {
      final response = await ApiService.evaluateJoint(
        amount: value,
        merchant: merchantController.text,
        category: 'shopping',
      );
      if (mounted) setState(() {
        result = response; loading = false; proposalId = null; proposalStatus = null;
      });
    } catch (e) {
      if (mounted) setState(() { error = e.toString(); loading = false; });
    }
  }

  Future<void> requestApproval() async {
    try {
      final response = await ApiService.requestJointApproval(
        amount: value, merchant: merchantController.text);
      if (mounted) setState(() {
        proposalId = response['proposal_id'].toString();
        proposalStatus = response['status'].toString();
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> respond(bool approve) async {
    if (proposalId == null) return;
    try {
      final response = await ApiService.decideJointProposal(
        proposalId: proposalId!, approve: approve);
      if (mounted) setState(() => proposalStatus = response['status'].toString());
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: SafeArea(child: ListView(
      padding: const EdgeInsets.all(16), children: [
        const Text('Joint Account Check', style: TextStyle(
            fontWeight: FontWeight.w800, fontSize: 22, color: AppTheme.brandNavy)),
        const SizedBox(height: 4),
        const Text('Review an unusual payment before initiating it in the app.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
        const SizedBox(height: 14),
        Card(child: Padding(padding: const EdgeInsets.all(14),
          child: Column(children: [
            TextField(controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Proposed payment amount', prefixIcon: Icon(Icons.attach_money))),
            const SizedBox(height: 10),
            TextField(controller: merchantController,
              decoration: const InputDecoration(
                labelText: 'Recipient or merchant', prefixIcon: Icon(Icons.store_outlined))),
            const SizedBox(height: 14),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: loading ? null : evaluate,
              child: const Text('Check Before Paying'))),
          ]))),
        const SizedBox(height: 12),
        if (loading) const Center(child: CircularProgressIndicator()),
        if (error != null) Card(child: Padding(
          padding: const EdgeInsets.all(14), child: Text(error!,
            style: const TextStyle(color: AppTheme.riskRed)))),
        if (result != null && !loading) ...[
          Card(color: result!['is_unusual'] == true
              ? AppTheme.riskRedBg : const Color(0xFFE7F8EC),
            child: Padding(padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(result!['is_unusual'] == true
                    ? 'Unusual proposed payment' : 'No unusual-spend threshold triggered',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 17,
                      color: AppTheme.brandNavy)),
                const SizedBox(height: 8),
                Text(result!['risk_reason'].toString()),
                const SizedBox(height: 8),
                Text('Available joint-demo account balance: \$' +
                    result!['account_balance'].toString()),
                const SizedBox(height: 8),
                const Text('Transaction has NOT been submitted to the bank.',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
              ]))),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: proposalId == null && result!['is_unusual'] == true
                ? requestApproval : null,
            child: const Text('Request Trusted Partner Approval')),
          if (proposalStatus != null) ...[
            const SizedBox(height: 10),
            Card(child: Padding(padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Proposal status: ' + proposalStatus!,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                const Text('Simulated second participant: Jamie',
                    style: TextStyle(fontSize: 11)),
                if (proposalStatus == 'awaiting_partner')
                  Row(children: [
                    Expanded(child: OutlinedButton(
                      onPressed: () => respond(false),
                      child: const Text('Demo: Decline'))),
                    const SizedBox(width: 8),
                    Expanded(child: ElevatedButton(
                      onPressed: () => respond(true),
                      child: const Text('Demo: Approve'))),
                  ]),
              ]))),
          ],
          const SizedBox(height: 12),
          const Text(
            'This is a simulation of in-app consent. It cannot stop, intercept, '
            'or require approval for transactions initiated directly with Capital One.',
            style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
        ],
      ],
    )));
  }
}
