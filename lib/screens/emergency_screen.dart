import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';

class EmergencyScreen extends StatefulWidget {
  const EmergencyScreen({super.key});
  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen> {
  final costController = TextEditingController(text: '1000');
  double buffer = 300;
  Map<String, dynamic>? result;
  String? error;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    evaluate();
  }

  @override
  void dispose() {
    costController.dispose();
    super.dispose();
  }

  double get cost => double.tryParse(costController.text) ?? 0;
  String dollars(dynamic v) =>
      '\$' + (double.tryParse(v.toString()) ?? 0).toStringAsFixed(2);

  Future<void> evaluate() async {
    if (cost < 0) {
      setState(() => error = 'Enter a nonnegative emergency amount');
      return;
    }
    if (mounted) setState(() { loading = true; error = null; });
    try {
      final response = await ApiService.evaluateEmergency(
          cost: cost, buffer: buffer);
      if (mounted) setState(() { result = response; loading = false; });
    } catch (e) {
      if (mounted) setState(() { error = e.toString(); loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final gap = double.tryParse(result?['potential_gap'].toString() ?? '') ?? 0;
    return Scaffold(body: SafeArea(child: ListView(
      padding: const EdgeInsets.all(16), children: [
        const Text('Emergency Readiness', style: TextStyle(
            fontSize: 22, fontWeight: FontWeight.w800,
            color: AppTheme.brandNavy)),
        const SizedBox(height: 4),
        const Text('Can your cash cover an unexpected expense while preserving bills?',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
        const SizedBox(height: 14),
        Card(child: Padding(padding: const EdgeInsets.all(14),
          child: Column(children: [
            TextField(controller: costController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Emergency cost estimate',
                prefixIcon: Icon(Icons.emergency_outlined))),
            const SizedBox(height: 10),
            DropdownButtonFormField<double>(
              value: buffer,
              decoration: const InputDecoration(labelText: 'Protected safety reserve'),
              items: const [
                DropdownMenuItem(value: 0, child: Text('\$0')),
                DropdownMenuItem(value: 100, child: Text('\$100')),
                DropdownMenuItem(value: 300, child: Text('\$300')),
                DropdownMenuItem(value: 500, child: Text('\$500')),
              ],
              onChanged: (v) { if (v != null) setState(() => buffer = v); }),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity,
              child: ElevatedButton(onPressed: loading ? null : evaluate,
                child: const Text('Estimate Emergency Readiness'))),
          ]))),
        const SizedBox(height: 12),
        if (loading) const Center(child: CircularProgressIndicator()),
        if (error != null) Card(child: Padding(padding: const EdgeInsets.all(14),
          child: Column(children: [
            Text(error!, style: const TextStyle(color: AppTheme.riskRed)),
            TextButton(onPressed: evaluate, child: const Text('Retry')),
          ]))),
        if (!loading && result != null) ...[
          Card(color: gap > 0 ? AppTheme.riskRedBg : const Color(0xFFE7F8EC),
            child: Padding(padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(gap > 0 ? 'Additional funding may be needed'
                             : 'Current cash covers this estimate',
                    style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(gap > 0 ? 'Gap: ' + dollars(gap) : 'Covered',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900,
                      color: gap > 0 ? AppTheme.riskRed : AppTheme.brandNavy)),
                Text('Coverage: ' + result!['coverage_pct'].toString() + '%'),
              ]))),
          const SizedBox(height: 12),
          Card(child: Column(children: [
            item('Checking + Savings', result!['total_available_funds']),
            item('Upcoming bills', result!['protected_committed_bills']),
            item('Safety reserve', result!['safety_buffer']),
            item('Usable cash', result!['usable_cash_buffer']),
            item('Estimated emergency cost', result!['estimated_emergency_cost']),
            item('Potential gap', result!['potential_gap']),
          ])),
          const SizedBox(height: 10),
          const Card(child: Padding(padding: EdgeInsets.all(12),
            child: Text(
              'This is an affordability stress test, not a weather forecast '
              'or an emergency prediction. It uses Nessie sandbox balances '
              'and locally simulated future bills.',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
          )),
        ],
      ],
    )));
  }

  Widget item(String label, dynamic value) => ListTile(
    dense: true,
    title: Text(label),
    trailing: Text(dollars(value),
      style: const TextStyle(fontWeight: FontWeight.w800,
          color: AppTheme.brandNavy)),
  );
}
