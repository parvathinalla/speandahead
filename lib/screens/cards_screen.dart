import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';

class CardsScreen extends StatefulWidget {
  final Function(int)? onNavigateTab;
  const CardsScreen({super.key, this.onNavigateTab});
  @override
  State<CardsScreen> createState() => _CardsScreenState();
}

class _CardsScreenState extends State<CardsScreen> {
  final amountController = TextEditingController(text: '120');
  String category = 'groceries';
  bool loading = true;
  Map<String, dynamic>? result;
  String? error;

  @override
  void initState() {
    super.initState();
    evaluate();
  }

  @override
  void dispose() {
    amountController.dispose();
    super.dispose();
  }

  double get price => double.tryParse(amountController.text) ?? 0;
  String dollars(dynamic v) => '\$' + (double.tryParse(v.toString()) ?? 0).toStringAsFixed(2);

  Future<void> evaluate() async {
    if (price <= 0) {
      setState(() => error = 'Enter a purchase amount greater than zero.');
      return;
    }
    setState(() { loading = true; error = null; });
    try {
      final response = await ApiService.evaluateCards(
        amount: price, category: category, merchant: 'Demo merchant');
      if (mounted) setState(() { result = response; loading = false; });
    } catch (e) {
      if (mounted) setState(() { error = e.toString(); loading = false; });
    }
  }

  Future<void> simulate() async {
    try {
      final response = await ApiService.simulatePurchase(
          amount: price, category: category, emergencyCost: 1000);
      if (!mounted) return;
      final card = (response['recommended_card'] as Map?) ?? {};
      final cash = (response['cashflow_before_purchase'] as Map?) ?? {};
      final emergency = (response['emergency_stress_test'] as Map?) ?? {};
      showDialog<void>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Financial Decision Preview'),
        content: Text(
          'Recommended: ' + (card['display_name']?.toString() ?? card['card_name'].toString()) +
          '\nUpcoming bills: ' + dollars(cash['total_bills_due']) +
          '\nChecking shortage: ' + dollars(cash['shortfall_amount']) +
          '\nEmergency funding gap: ' + dollars(emergency['potential_gap']) +
          '\n\nNo money or credit was moved.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'))],
      ));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardList = (result?['cards'] as List?) ?? [];
    final best = (result?['recommended_card'] as Map?) ?? {};

    return Scaffold(body: SafeArea(child: ListView(
      padding: const EdgeInsets.all(16), children: [
        const Text('Best Card for This Purchase', style: TextStyle(
            fontSize: 21, fontWeight: FontWeight.w800, color: AppTheme.brandNavy)),
        const SizedBox(height: 4),
        const Text('Rewards and credit utilization together. Sandbox estimates only.',
            style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
        const SizedBox(height: 14),
        Card(child: Padding(padding: const EdgeInsets.all(14),
          child: Column(children: [
            TextField(controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Purchase amount (USD)', prefixIcon: Icon(Icons.shopping_cart))),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: category,
              decoration: const InputDecoration(labelText: 'Merchant category'),
              items: const [
                DropdownMenuItem(value: 'groceries', child: Text('Groceries')),
                DropdownMenuItem(value: 'gas', child: Text('Gas')),
                DropdownMenuItem(value: 'dining', child: Text('Dining')),
                DropdownMenuItem(value: 'other', child: Text('Other')),
              ],
              onChanged: (v) { if (v != null) setState(() => category = v); }),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity,
              child: ElevatedButton(onPressed: evaluate,
                child: const Text('Find Best Card'))),
          ]))),
        const SizedBox(height: 10),
        if (loading) const Center(child: CircularProgressIndicator()),
        if (error != null) Card(child: Padding(padding: const EdgeInsets.all(14),
          child: Column(children: [
            Text(error!, style: const TextStyle(color: AppTheme.riskRed)),
            TextButton(onPressed: evaluate, child: const Text('Retry')),
          ]))),
        if (!loading && result != null) ...[
          Card(color: AppTheme.brandBlueLight,
            child: Padding(padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Recommended option', style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600)),
                Text(best.isEmpty ? 'No card has enough available credit'
                                  : best['display_name']?.toString() ?? best['card_name'].toString(),
                    style: const TextStyle(color: AppTheme.brandNavy,
                        fontWeight: FontWeight.w900, fontSize: 21)),
                if (best.isNotEmpty) Text(
                  'Fictional offer • Rewards: ' + dollars(best['rewards_amount']) +
                  ' • After-purchase utilization: ' +
                  best['utilization_after_pct'].toString() + '%'),
                const SizedBox(height: 6),
                const Text('Prioritizes available credit and chosen utilization target before rewards.',
                    style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
              ]))),
          const SizedBox(height: 10),
          for (final item in cardList)
            Card(child: ListTile(
              leading: const Icon(Icons.credit_card, color: AppTheme.brandBlue),
              title: Text(item['display_name']?.toString() ?? item['card_name'].toString()),
              subtitle: Text('•••• ' + (item['last4']?.toString() ?? '0000') + ' • ' +
                  (item['issuer']?.toString() ?? 'Fictional issuer') + '\nCurrent utilization: ' +
                  item['current_utilization_pct'].toString() +
                  '% → ' + item['utilization_after_pct'].toString() + '%'),
              trailing: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(dollars(item['rewards_amount']),
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const Text('rewards', style: TextStyle(fontSize: 10)),
              ]),
            )),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: best.isNotEmpty ? simulate : null,
            child: const Text('Compare Future Consequences')),
          const SizedBox(height: 8),
          TextButton.icon(onPressed: () => widget.onNavigateTab?.call(2),
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Plan an Early Utilization Payment')),
          const Text('No charge is processed. Rewards and credit limits are simulated;'
                     ' future credit score changes are not guaranteed.',
              style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
        ],
      ],
    )));
  }
}
