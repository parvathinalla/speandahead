import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';

class AutoPayScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const AutoPayScreen({super.key, this.onBack});
  @override
  State<AutoPayScreen> createState() => _AutoPayScreenState();
}

class _AutoPayScreenState extends State<AutoPayScreen> {
  double targetUtil = 29;
  final savingsInput = TextEditingController(text: '0');
  double get assumedSavings => double.tryParse(savingsInput.text) ?? 0;
  List<Map<String, dynamic>> cardCatalog = [];
  String? account;
  Map<String, dynamic>? result;
  String? error;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadCards();
  }

  @override
  void dispose() {
    savingsInput.dispose();
    super.dispose();
  }

  Future<void> loadCards() async {
    setState(() { loading = true; error = null; });
    try {
      final catalog = await ApiService.getCardCatalog();
      final cards = (catalog['cards'] as List? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      if (cards.isEmpty) throw ApiException('No credit cards available in your demo profile');
      cardCatalog = cards;
      account = cards.first['account'].toString();
      await refresh();
    } catch (e) {
      if (mounted) setState(() { error = e.toString(); loading = false; });
    }
  }

  String dollars(dynamic v) =>
      '\$' + (double.tryParse(v.toString()) ?? 0).toStringAsFixed(2);

  Future<void> refresh() async {
    if (account == null) return;
    if (mounted) setState(() { loading = true; error = null; });
    try {
      final response = await ApiService.getAutoPayPreview(
        targetPct: targetUtil,
        account: account!,
        assumedSavingsTransfer: assumedSavings,
      );
      if (mounted) setState(() { result = response; loading = false; });
    } catch (e) {
      if (mounted) setState(() { error = e.toString(); loading = false; });
    }
  }

  Future<void> schedulePlan() async {
    if ((double.tryParse(result?['recommended_payment_amount'].toString() ?? '') ?? 0) <= 0) {
      return;
    }
    final confirm = await showDialog<bool>(context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Demo AutoPay Plan'),
        content: Text(
          'Plan ' + dollars(result?['recommended_payment_amount']) +
          ' of credit-card paydown.\n\n'
          'This is a stored simulation only. It DOES NOT pay your card, '
          'schedule a real bank transfer or contact a credit bureau.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save Plan')),
        ]));
    if (confirm != true) return;
    try {
      final response = await ApiService.scheduleAutoPay(
        targetPct: targetUtil,
        account: account!,
        assumedSavingsTransfer: assumedSavings,
      );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Plan status: ' + response['status'].toString())));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = result;
    final positive = (double.tryParse(d?['recommended_payment_amount'].toString() ?? '') ?? 0) > 0;

    return Scaffold(body: SafeArea(child: RefreshIndicator(
      onRefresh: refresh,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Container(padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF07284C), Color(0xFF0A3D75)]),
            borderRadius: BorderRadius.circular(18)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (widget.onBack != null)
              IconButton(onPressed: widget.onBack,
                  icon: const Icon(Icons.arrow_back, color: Colors.white)),
            const Text('Smart Utilization AutoPay',
                style: TextStyle(color: Colors.white,
                    fontWeight: FontWeight.w800, fontSize: 19)),
            const SizedBox(height: 8),
            const Text('Estimate an affordable early payment while protecting upcoming bills.',
                style: TextStyle(color: Colors.white70)),
          ])),
        const SizedBox(height: 14),
        Card(child: Padding(padding: const EdgeInsets.all(14),
          child: Column(children: [
            DropdownButtonFormField<String>(
              value: cardCatalog.any((c) => c['account'] == account) ? account : null,
              decoration: const InputDecoration(labelText: 'Choose your demo credit card'),
              items: cardCatalog.map((c) => DropdownMenuItem<String>(
                value: c['account'].toString(),
                child: Text(c['display_name'].toString() +
                    ' ••••' + c['last4'].toString(),
                    overflow: TextOverflow.ellipsis),
              )).toList(),
              onChanged: (v) { if (v != null) { account = v; refresh(); } },
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<double>(
              value: targetUtil,
              decoration: const InputDecoration(labelText: 'Target utilization'),
              items: const [
                DropdownMenuItem(value: 29, child: Text('29%')),
                DropdownMenuItem(value: 25, child: Text('25%')),
                DropdownMenuItem(value: 20, child: Text('20%')),
                DropdownMenuItem(value: 10, child: Text('10%')),
              ],
              onChanged: (v) { if (v != null) { targetUtil = v; refresh(); } },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: savingsInput,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'What-if transfer from savings (USD)',
                helperText: 'Any amount; scenario only, no real funds moved',
                prefixIcon: Icon(Icons.savings_outlined),
              ),
              onSubmitted: (_) => refresh(),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: refresh,
              icon: const Icon(Icons.calculate_outlined),
              label: const Text('Recalculate plan'),
            ),
          ]))),
        if (loading) const Padding(padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator())),
        if (error != null) Card(child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(children: [
              Text(error!, style: const TextStyle(color: AppTheme.riskRed)),
              TextButton(onPressed: refresh, child: const Text('Retry')),
            ]))),
        if (!loading && d != null) ...[
          Text(d['card_display_name']?.toString() ?? 'Credit card',
              style: const TextStyle(fontSize: 16,
                  fontWeight: FontWeight.w800, color: AppTheme.brandNavy)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: metric('Credit limit', dollars(d['card_limit']))),
            const SizedBox(width: 8),
            Expanded(child: metric('Card balance', dollars(d['current_balance']))),
          ]),
          const SizedBox(height: 10),
          Card(child: Padding(padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Current utilization', style: TextStyle(fontSize: 12,
                  color: AppTheme.textSecondary)),
              Text(d['current_utilization_pct'].toString() + '%',
                  style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: (double.tryParse(d['current_utilization_pct'].toString()) ?? 0)
                    .clamp(0, 100) / 100,
                minHeight: 9,
                backgroundColor: const Color(0xFFE2E8F0),
                color: AppTheme.riskRed,
              ),
              const SizedBox(height: 12),
              row('Needed for target', dollars(d['suggested_paydown_amount'])),
              row('Checking after funding assumption', dollars(d['checking_funds'])),
              row('Upcoming bills protected', dollars(d['upcoming_bills_2weeks'])),
              row('Safety buffer', dollars(d['safety_buffer'])),
              row('Safe payment amount', dollars(d['recommended_payment_amount'])),
              row('Projected utilization', d['projected_utilization_pct'].toString() + '%'),
            ]))),
          const SizedBox(height: 12),
          Card(color: AppTheme.brandBlueLight,
            child: Padding(padding: const EdgeInsets.all(15),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(positive
                    ? 'Suggested early payment: ' + dollars(d['recommended_payment_amount'])
                    : 'No affordable early payment today',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
                        color: AppTheme.brandNavy)),
                const SizedBox(height: 6),
                Text(d['alert_message'].toString(),
                    style: const TextStyle(fontSize: 12)),
                Text('Estimated statement close: ' + d['expected_statement_date'].toString(),
                    style: const TextStyle(fontSize: 11)),
              ]))),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: positive ? schedulePlan : null,
            child: const Text('Save Demo AutoPay Plan')),
          const SizedBox(height: 8),
          const Text('Reporting dates are estimates. Under 30% does not guarantee a '
                     'credit score increase. No payments are automated in this demo.',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
        ],
      ]),
    )));
  }

  Widget metric(String label, String value) => Card(child: Padding(
    padding: const EdgeInsets.all(14),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 11,
          color: AppTheme.textSecondary)),
      const SizedBox(height: 5),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w800,
          fontSize: 20, color: AppTheme.brandNavy)),
    ]),
  ));

  Widget row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Flexible(child: Text(label, style: const TextStyle(fontSize: 11))),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
    ]),
  );
}
