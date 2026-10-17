import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';

class BillsScreen extends StatefulWidget {
  const BillsScreen({super.key});
  @override
  State<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends State<BillsScreen> {
  Map<String, dynamic>? data;
  String? error;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    reload();
  }

  String dollars(dynamic v) => '\$' + (double.tryParse(v.toString()) ?? 0).toStringAsFixed(2);

  Future<void> reload() async {
    if (mounted) setState(() { loading = true; error = null; });
    try {
      final response = await ApiService.getBillForecast();
      if (mounted) setState(() { data = response; loading = false; });
    } catch (e) {
      if (mounted) setState(() { error = e.toString(); loading = false; });
    }
  }

  Future<void> reviewTransfer() async {
    final transfer = double.tryParse(data?['suggested_savings_transfer'].toString() ?? '') ?? 0;
    if (transfer <= 0) return;
    final key = 'cp-demo-' + DateTime.now().microsecondsSinceEpoch.toString();
    try {
      final preview = await ApiService.transferPreview(amount: transfer, idempotencyKey: key);
      if (!mounted) return;
      final allow = preview['allowed'] == true;
      final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Review Savings Transfer'),
          content: Text('Move ' + dollars(transfer) + ' from savings to checking?\n\n'
              'Maximum safe transfer: ' + dollars(preview['max_safe_transfer']) +
              '\n\nThis is a sandbox simulation, not a real bank payment.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            if (allow)
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Confirm Simulation')),
          ],
        ),
      );
      if (yes == true) {
        final response = await ApiService.executeTransfer(
            amount: transfer, idempotencyKey: key);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Transfer status: ' + response['status'].toString())));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Could not load live account data'),
        Padding(padding: const EdgeInsets.all(16),
            child: Text(error!, textAlign: TextAlign.center)),
        TextButton(onPressed: reload, child: const Text('Retry')),
      ]));
    }

    final d = data!;
    final payments = (d['upcoming_bills'] as List?) ?? [];
    final timeline = (d['timeline'] as List?) ?? [];
    final shortfall = d['is_shortfall'] == true;
    final suggestion = double.tryParse(d['suggested_savings_transfer'].toString()) ?? 0;

    return Scaffold(body: SafeArea(child: RefreshIndicator(
      onRefresh: reload,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Bill Forecast', style: TextStyle(
            fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.brandNavy)),
        const SizedBox(height: 4),
        const Text('Nessie balances • Simulated upcoming bills',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: metric('Checking', dollars(d['checking_balance']))),
          const SizedBox(width: 10),
          Expanded(child: metric('Due in 14 days', dollars(d['total_bills_due']))),
        ]),
        const SizedBox(height: 12),
        Card(color: shortfall ? AppTheme.riskRedBg : const Color(0xFFE7F8EC),
          child: Padding(padding: const EdgeInsets.all(16), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(shortfall ? 'Potential bill shortfall' : 'Scheduled bills covered',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              Text(shortfall ? dollars(d['shortfall_amount']) : 'On track',
                  style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900,
                    color: shortfall ? AppTheme.riskRed : AppTheme.brandNavy)),
              const Text('Forecast only, not a guaranteed future balance.',
                  style: TextStyle(fontSize: 10)),
            ]))),
        const SizedBox(height: 14),
        const Text('Upcoming Bills', style: TextStyle(fontSize: 15,
            fontWeight: FontWeight.w800, color: AppTheme.brandNavy)),
        Card(child: Column(children: [
          if (payments.isEmpty) const ListTile(title: Text('No upcoming bills')),
          for (final item in payments)
            ListTile(
              leading: const Icon(Icons.receipt_long, color: AppTheme.brandBlue),
              title: Text(item['payee'].toString()),
              subtitle: Text(item['due_date'].toString()),
              trailing: Text(dollars(item['amount']),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
        ])),
        const SizedBox(height: 14),
        const Text('Projected Balance', style: TextStyle(fontSize: 15,
            fontWeight: FontWeight.w800, color: AppTheme.brandNavy)),
        Card(child: Column(children: [
          for (final day in timeline)
            ListTile(dense: true,
              title: Text(day['event'].toString()),
              subtitle: Text(day['date'].toString()),
              trailing: Text(dollars(day['balance']),
                  style: const TextStyle(fontWeight: FontWeight.w700))),
        ])),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: suggestion > 0 ? reviewTransfer : null,
          child: Text('Review Savings Option: ' + dollars(suggestion)),
        ),
        const SizedBox(height: 6),
        TextButton.icon(onPressed: reload, icon: const Icon(Icons.refresh),
          label: const Text('Refresh Account Balances')),
      ]),
    )));
  }

  Widget metric(String label, String value) => Card(
    child: Padding(padding: const EdgeInsets.all(14), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
        const SizedBox(height: 5),
        Text(value, style: const TextStyle(fontSize: 22,
            fontWeight: FontWeight.w800, color: AppTheme.brandNavy)),
      ],
    )));
}
