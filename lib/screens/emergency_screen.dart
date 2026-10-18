import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/location_service.dart';
import '../theme/app_theme.dart';

class EmergencyScreen extends StatefulWidget {
  const EmergencyScreen({super.key});

  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen> {
  final costController = TextEditingController(text: '1000');
  double buffer = 300;
  Map<String, dynamic>? result;
  Map<String, dynamic>? hurricaneResult;
  String? error;
  String? hurricaneError;
  bool loading = false;
  bool hurricaneLoading = false;

  @override
  void initState() {
    super.initState();
    evaluate();
    loadHurricaneSimulation();
  }

  @override
  void dispose() {
    costController.dispose();
    super.dispose();
  }

  double get cost => double.tryParse(costController.text) ?? 0;
  String dollars(dynamic value) =>
      '\$${(double.tryParse(value.toString()) ?? 0).toStringAsFixed(2)}';

  Future<void> evaluate() async {
    if (cost < 0) {
      setState(() => error = 'Enter a nonnegative emergency amount');
      return;
    }
    if (mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      final response =
          await ApiService.evaluateEmergency(cost: cost, buffer: buffer);
      if (mounted) {
        setState(() {
          result = response;
          loading = false;
        });
      }
    } catch (exception) {
      if (mounted) {
        setState(() {
          error = exception.toString();
          loading = false;
        });
      }
    }
  }

  Future<void> enableHurricaneSimulation() async {
    setState(() {
      hurricaneLoading = true;
      hurricaneError = null;
    });
    try {
      final location = await LocationService.instance.refresh();
      final position = location.position;
      if (position == null) {
        throw ApiException(location.message);
      }
      final response = await ApiService.subscribeHurricaneSimulation(
        latitude: position.latitude,
        longitude: position.longitude,
        safetyBuffer: buffer,
      );
      if (mounted) {
        setState(() {
          hurricaneResult = response;
          hurricaneLoading = false;
        });
      }
    } catch (exception) {
      if (mounted) {
        setState(() {
          hurricaneError = exception.toString();
          hurricaneLoading = false;
        });
      }
    }
  }

  Future<void> loadHurricaneSimulation() async {
    try {
      final response = await ApiService.getHurricaneSimulation();
      if (mounted && response['alert_subscribed'] == true) {
        setState(() => hurricaneResult = response);
      }
    } catch (_) {
      // The manual emergency calculator remains available if this optional
      // simulation cannot be loaded.
    }
  }

  Future<void> disableHurricaneSimulation() async {
    setState(() {
      hurricaneLoading = true;
      hurricaneError = null;
    });
    try {
      await ApiService.unsubscribeHurricaneSimulation();
      if (mounted) {
        setState(() {
          hurricaneResult = null;
          hurricaneLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Daily hurricane simulation disabled.')),
        );
      }
    } catch (exception) {
      if (mounted) {
        setState(() {
          hurricaneError = exception.toString();
          hurricaneLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final gap = double.tryParse(result?['potential_gap'].toString() ?? '') ?? 0;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Emergency Readiness',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppTheme.brandNavy,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Plan for an unexpected expense while keeping upcoming bills covered.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
            ),
            const SizedBox(height: 14),
            _hurricaneCard(),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    TextField(
                      controller: costController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Emergency cost estimate',
                        prefixIcon: Icon(Icons.emergency_outlined),
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<double>(
                      value: buffer,
                      decoration:
                          const InputDecoration(labelText: 'Safety reserve'),
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('\$0')),
                        DropdownMenuItem(value: 100, child: Text('\$100')),
                        DropdownMenuItem(value: 300, child: Text('\$300')),
                        DropdownMenuItem(value: 500, child: Text('\$500')),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => buffer = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: loading ? null : evaluate,
                        child: const Text('Estimate Emergency Readiness'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (loading) const Center(child: CircularProgressIndicator()),
            if (error != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      Text(error!,
                          style: const TextStyle(color: AppTheme.riskRed)),
                      TextButton(
                          onPressed: evaluate, child: const Text('Retry')),
                    ],
                  ),
                ),
              ),
            if (!loading && result != null) ...[
              Card(
                color: gap > 0 ? AppTheme.riskRedBg : const Color(0xFFE7F8EC),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        gap > 0
                            ? 'Additional funding may be needed'
                            : 'Current cash covers this estimate',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        gap > 0 ? 'Gap: ${dollars(gap)}' : 'Covered',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color:
                              gap > 0 ? AppTheme.riskRed : AppTheme.brandNavy,
                        ),
                      ),
                      Text('Coverage: ${result!['coverage_pct']}%'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    item(
                        'Checking + Savings', result!['total_available_funds']),
                    item(
                        'Upcoming bills', result!['protected_committed_bills']),
                    item('Safety reserve', result!['safety_buffer']),
                    item('Usable cash', result!['usable_cash_buffer']),
                    item('Estimated emergency cost',
                        result!['estimated_emergency_cost']),
                    item('Potential gap', result!['potential_gap']),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _hurricaneCard() {
    final assessment = hurricaneResult;
    final gap = double.tryParse(
          assessment?['potential_gap']?.toString() ?? '',
        ) ??
        0;
    final expenses = assessment?['additional_expenses'] as Map?;
    return Card(
      color: const Color(0xFFEAF3FF),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.cyclone, color: AppTheme.brandBlue),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Hurricane budget simulation',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.brandNavy,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Use your location once to choose a broad region and estimate extra food, power, travel, lodging, and home-protection costs. You will receive at most one simulated alert per day.',
              style: TextStyle(color: AppTheme.textSecondary, height: 1.35),
            ),
            const SizedBox(height: 8),
            const Text(
              'Planning exercise only — not an official storm forecast, warning, or evacuation order.',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
            if (hurricaneLoading) ...[
              const SizedBox(height: 14),
              const Center(child: CircularProgressIndicator()),
            ] else if (assessment == null) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: enableHurricaneSimulation,
                  icon: const Icon(Icons.location_on_outlined),
                  label: const Text('Use location and enable daily simulation'),
                ),
              ),
            ] else ...[
              const Divider(height: 28),
              Text(
                '${assessment['region']} • ${gap > 0 ? 'Potential gap ${dollars(gap)}' : 'Covered with ${dollars(assessment['remaining_cushion'])} left'}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: gap > 0 ? AppTheme.riskRed : AppTheme.brandNavy,
                ),
              ),
              const SizedBox(height: 8),
              Text(assessment['status_message']?.toString() ?? ''),
              const SizedBox(height: 10),
              if (expenses != null)
                ...expenses.entries.map(
                  (entry) => item(entry.key.toString(), entry.value),
                ),
              item('Total simulated storm costs',
                  assessment['estimated_emergency_cost']),
              item('Upcoming bills', assessment['protected_committed_bills']),
              item('Safety reserve', assessment['safety_buffer']),
              item('Cash available for this plan',
                  assessment['usable_cash_buffer']),
              const SizedBox(height: 4),
              Text(
                assessment['location_storage']?.toString() ?? '',
                style: const TextStyle(
                    fontSize: 11, color: AppTheme.textSecondary),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: disableHurricaneSimulation,
                  child: const Text('Disable daily simulation'),
                ),
              ),
            ],
            if (hurricaneError != null) ...[
              const SizedBox(height: 10),
              Text(
                hurricaneError!,
                style: const TextStyle(color: AppTheme.riskRed),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget item(String label, dynamic value) => ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        trailing: Text(
          dollars(value),
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: AppTheme.brandNavy,
          ),
        ),
      );
}
