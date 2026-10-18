import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';

class AutoPayScreen extends StatefulWidget {
  final VoidCallback? onBack;
  final String? preferredAccount;

  const AutoPayScreen({super.key, this.onBack, this.preferredAccount});

  @override
  State<AutoPayScreen> createState() => _AutoPayScreenState();
}

class _AutoPayScreenState extends State<AutoPayScreen> {
  double safetyBuffer = 100;
  int reminderLeadDays = 5;
  int processingDays = 3;
  bool remindersEnabled = true;
  bool loading = true;
  bool activating = false;
  bool guardActive = false;
  bool portfolioActivating = false;
  bool portfolioGuardActive = false;
  bool includeAvailableSavings = false;
  double savingsReserve = 1000;
  List<Map<String, dynamic>> cardCatalog = [];
  String? account;
  Map<String, dynamic>? result;
  Map<String, dynamic>? portfolioResult;
  String? error;

  @override
  void initState() {
    super.initState();
    loadCards();
  }

  @override
  void didUpdateWidget(covariant AutoPayScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.preferredAccount != null &&
        widget.preferredAccount != oldWidget.preferredAccount &&
        cardCatalog.any((card) => card['account'] == widget.preferredAccount)) {
      account = widget.preferredAccount;
      guardActive = false;
      refresh();
    }
  }

  String dollars(dynamic value) =>
      '\$${(double.tryParse(value.toString()) ?? 0).toStringAsFixed(2)}';

  String dateLabel(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) return 'Not available';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[parsed.month - 1]} ${parsed.day}, ${parsed.year}';
  }

  Future<void> loadCards() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final catalog = await ApiService.getCardCatalog();
      final cards = (catalog['cards'] as List? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      if (cards.isEmpty) {
        throw ApiException('No credit cards are available for this account');
      }
      cardCatalog = cards;
      account = cards.any((card) => card['account'] == widget.preferredAccount)
          ? widget.preferredAccount
          : cards.first['account'].toString();
      await refresh();
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        error = exception.toString();
        loading = false;
      });
    }
  }

  Future<void> refresh() async {
    if (account == null) return;
    setState(() {
      loading = true;
      error = null;
      guardActive = false;
    });
    try {
      final responses = await Future.wait([
        ApiService.getAutoPayPreview(
          account: account!,
          safetyBuffer: safetyBuffer,
          reminderLeadDays: reminderLeadDays,
          paymentProcessingDays: processingDays,
          notificationsEnabled: remindersEnabled,
        ),
        ApiService.getPortfolioAutoPayPreview(
          safetyBuffer: safetyBuffer,
          savingsReserve: savingsReserve,
          includeAvailableSavings: includeAvailableSavings,
          reminderLeadDays: reminderLeadDays,
          paymentProcessingDays: processingDays,
          notificationsEnabled: remindersEnabled,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        result = responses[0];
        portfolioResult = responses[1];
        loading = false;
      });
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        error = exception.toString();
        loading = false;
      });
    }
  }

  Future<void> activateGuard() async {
    final amount =
        double.tryParse(
          result?['recommended_payment_amount']?.toString() ?? '',
        ) ??
        0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Activate Statement Guard?'),
        content: Text(
          amount > 0
              ? 'CreditPilot will store reminders to review an early payment of '
                    '${dollars(amount)} by ${dateLabel(result?['early_payment_date'])}, '
                    'followed by a statement-balance reminder before '
                    '${dateLabel(result?['estimated_payment_due_date'])}.\n\n'
                    'No payment is initiated. Reporting dates and score effects cannot be guaranteed.'
              : 'CreditPilot will monitor this card and remind you to recheck '
                    'the balance and available cash by '
                    '${dateLabel(result?['early_payment_date'])}. No affordable '
                    'early payment is currently identified.\n\n'
                    'followed by a statement-balance reminder before '
                    '${dateLabel(result?['estimated_payment_due_date'])}.\n\n'
                    'No payment is initiated. Reporting dates and score effects cannot be guaranteed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Activate'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => activating = true);
    try {
      final response = await ApiService.scheduleAutoPay(
        account: account!,
        safetyBuffer: safetyBuffer,
        reminderLeadDays: reminderLeadDays,
        paymentProcessingDays: processingDays,
        notificationsEnabled: remindersEnabled,
      );
      if (!mounted) return;
      setState(() {
        guardActive = true;
        activating = false;
      });
      final pushReady = response['device_push_configured'] == true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            pushReady ? 'Statement Guard and device notifications are active.' : 'Statement Guard is active. Reminders are saved in the app; device push still needs notification-provider setup.',
          ),
        ),
      );
    } catch (exception) {
      if (!mounted) return;
      setState(() => activating = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(exception.toString())));
    }
  }

  Future<void> activatePortfolioGuard() async {
    final plan = portfolioResult;
    if (plan == null) return;
    final total = plan['allocated_payment_total'];
    final cards = (plan['cards'] as List? ?? const []).length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Activate Portfolio Statement Guard?'),
        content: Text(
          'Monitor $cards cards and store the optimized ${dollars(total)} '
          'early-payment plan. CreditPilot will create a reminder for each '
          'estimated statement window.\n\nNo funds move automatically, and '
          'issuer dates must be confirmed before paying.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Activate'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => portfolioActivating = true);
    try {
      final response = await ApiService.schedulePortfolioAutoPay(
        safetyBuffer: safetyBuffer,
        savingsReserve: savingsReserve,
        includeAvailableSavings: includeAvailableSavings,
        reminderLeadDays: reminderLeadDays,
        paymentProcessingDays: processingDays,
        notificationsEnabled: remindersEnabled,
      );
      if (!mounted) return;
      setState(() {
        portfolioActivating = false;
        portfolioGuardActive = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Portfolio Statement Guard is active for '
            '${response['cards_monitored']} cards. In-app reminders are saved.',
          ),
        ),
      );
    } catch (exception) {
      if (!mounted) return;
      setState(() => portfolioActivating = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(exception.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = result;
    final payment =
        double.tryParse(
          data?['recommended_payment_amount']?.toString() ?? '',
        ) ??
        0;
    final current =
        double.tryParse(data?['current_utilization_pct']?.toString() ?? '') ??
        0;
    final projected =
        double.tryParse(data?['projected_utilization_pct']?.toString() ?? '') ??
        0;
    final recommendedTarget = double.tryParse(
      data?['recommended_target_pct']?.toString() ?? '',
    );

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _header(),
              if (!loading && portfolioResult != null) ...[
                const SizedBox(height: 14),
                _portfolioOptimizer(portfolioResult!),
              ],
              const SizedBox(height: 14),
              _controls(),
              if (loading)
                const Padding(
                  padding: EdgeInsets.all(28),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (error != null) _errorCard(),
              if (!loading && data != null) ...[
                const SizedBox(height: 12),
                _paymentHero(
                  data,
                  payment,
                  current,
                  projected,
                  recommendedTarget,
                ),
                const SizedBox(height: 10),
                _targetLadder(data),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _metric(
                        'Credit limit',
                        dollars(data['card_limit']),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _metric(
                        'Current balance',
                        dollars(data['current_balance']),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _timeline(data),
                const SizedBox(height: 10),
                _cashProtection(data),
                const SizedBox(height: 10),
                _reminderCard(data),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: remindersEnabled && !activating
                      ? activateGuard
                      : null,
                  icon: Icon(
                    guardActive
                        ? Icons.notifications_active
                        : Icons.add_alert_outlined,
                  ),
                  label: Text(
                    activating
                        ? 'Activating…'
                        : guardActive
                        ? 'Statement Guard Active'
                        : 'Activate Statement Guard',
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'This is planning guidance, not credit repair advice. Issuers may report on different dates. Lower utilization may help, but no target guarantees a score result. Always use the issuer’s actual statement balance and due date.',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF07284C), Color(0xFF0A4B8F)],
      ),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.onBack != null)
          IconButton(
            onPressed: widget.onBack,
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
        const Row(
          children: [
            Icon(Icons.shield_outlined, color: Color(0xFF7DD3FC)),
            SizedBox(width: 8),
            Text(
              'Statement Guard',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 21,
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        const Text(
          'Plan an affordable early payment before the statement closes, then protect the final due date.',
          style: TextStyle(color: Colors.white70, height: 1.35),
        ),
      ],
    ),
  );

  Widget _controls() => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            initialValue: cardCatalog.any((card) => card['account'] == account)
                ? account
                : null,
            decoration: const InputDecoration(labelText: 'Credit card'),
            items: cardCatalog
                .map(
                  (card) => DropdownMenuItem<String>(
                    value: card['account'].toString(),
                    child: Text(
                      '${card['display_name']} •••• ${card['last4']}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              account = value;
              refresh();
            },
          ),
          const SizedBox(height: 10),
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.auto_awesome, color: AppTheme.brandBlue),
              SizedBox(width: 9),
              Expanded(
                child: Text(
                  'CreditPilot automatically chooses the lowest target that does not use money protected for bills or your safety buffer.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _portfolioOptimizer(Map<String, dynamic> data) {
    final cards = (data['cards'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final before = data['aggregate_utilization_before_pct'] ?? 0;
    final after = data['aggregate_utilization_after_pct'] ?? 0;
    return Card(
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppTheme.brandBlue, width: 1.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppTheme.brandBlueLight,
                  child: Icon(Icons.hub_outlined, color: AppTheme.brandBlue),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Portfolio Payment Optimizer',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'One protected budget across every statement',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            Row(
              children: [
                Expanded(
                  child: _optimizerMetric(
                    'Portfolio utilization',
                    '$before% → $after%',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _optimizerMetric(
                    'Optimized payments',
                    dollars(data['allocated_payment_total']),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  for (final card in cards) ...[
                    _allocationRow(card),
                    if (card != cards.last)
                      const Divider(height: 18, color: AppTheme.borderSubtle),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: includeAvailableSavings,
              title: const Text(
                'Include available savings',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                'Keep ${dollars(savingsReserve)} protected, then optimize only the remaining cash.',
              ),
              onChanged: (value) {
                setState(() {
                  includeAvailableSavings = value;
                  portfolioGuardActive = false;
                });
                refresh();
              },
            ),
            Text(
              data['funding_explanation']?.toString() ?? '',
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Priority: ${data['optimization_order']}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppTheme.brandNavy,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: remindersEnabled && !portfolioActivating
                    ? activatePortfolioGuard
                    : null,
                icon: Icon(
                  portfolioGuardActive
                      ? Icons.verified_outlined
                      : Icons.auto_fix_high,
                ),
                label: Text(
                  portfolioActivating
                      ? 'Activating…'
                      : portfolioGuardActive
                      ? 'Portfolio Guard Active'
                      : 'Activate Optimized Plan',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _optimizerMetric(String label, String value) => Container(
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(
      color: AppTheme.brandBlueLight,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w900,
            color: AppTheme.brandNavy,
          ),
        ),
      ],
    ),
  );

  Widget _allocationRow(Map<String, dynamic> card) {
    final payment =
        double.tryParse(card['recommended_payment_amount'].toString()) ?? 0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          payment > 0 ? Icons.payments_outlined : Icons.visibility_outlined,
          color: payment > 0 ? AppTheme.brandBlue : AppTheme.textMuted,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${card['display_name']} •••• ${card['last4']}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(
                '${card['current_utilization_pct']}% → ${card['projected_utilization_pct']}% · pay by ${dateLabel(card['pay_by_date'])}',
                style: const TextStyle(
                  fontSize: 10,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          payment > 0 ? dollars(payment) : 'Monitor',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: payment > 0 ? AppTheme.brandBlue : AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _paymentHero(
    Map<String, dynamic> data,
    double payment,
    double current,
    double projected,
    double? recommendedTarget,
  ) {
    final needsPayment = payment > 0;
    return Card(
      color: needsPayment ? const Color(0xFFEFF6FF) : AppTheme.successGreenBg,
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              data['card_display_name']?.toString() ?? 'Credit card',
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              needsPayment
                  ? 'Pay ${dollars(payment)} by ${dateLabel(data['early_payment_date'])}'
                  : 'No affordable early payment recommended today',
              style: const TextStyle(
                color: AppTheme.brandNavy,
                fontSize: 21,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${current.toStringAsFixed(1)}% current  →  ${projected.toStringAsFixed(1)}% projected',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: (current / 100).clamp(0, 1),
              minHeight: 9,
              borderRadius: BorderRadius.circular(20),
              backgroundColor: Colors.white,
              color: recommendedTarget == null || current > recommendedTarget
                  ? const Color(0xFFF59E0B)
                  : AppTheme.successGreen,
            ),
            const SizedBox(height: 8),
            Text(
              'Payment deadline includes a $processingDays-day processing buffer before the estimated statement close.',
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _targetLadder(Map<String, dynamic> data) {
    final options = (data['target_options'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final selected = double.tryParse(
      data['recommended_target_pct']?.toString() ?? '',
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Automatic cash-safe target',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                ),
                Chip(
                  avatar: Icon(
                    selected == null ? Icons.visibility_outlined : Icons.check,
                    size: 16,
                  ),
                  label: Text(
                    selected == null
                        ? 'Monitor only'
                        : '${selected.toStringAsFixed(0)}% selected',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final option in options) ...[
              _targetTier(option, selected),
              if (option != options.last) const SizedBox(height: 8),
            ],
            const SizedBox(height: 12),
            Text(
              data['target_explanation']?.toString() ?? '',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.brandNavy,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _targetTier(Map<String, dynamic> option, double? selected) {
    final target = double.tryParse(option['target_pct'].toString()) ?? 0;
    final affordable = option['affordable'] == true;
    final isSelected = selected == target;
    final label = target == 10
        ? 'Preferred'
        : target == 20
        ? 'Balanced fallback'
        : 'Below-30% fallback';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isSelected ? AppTheme.successGreenBg : AppTheme.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? AppTheme.successGreen : AppTheme.borderSubtle,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: isSelected
                ? AppTheme.successGreen
                : AppTheme.brandBlueLight,
            child: Text(
              '${target.toStringAsFixed(0)}%',
              style: TextStyle(
                color: isSelected ? Colors.white : AppTheme.brandBlue,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  '${dollars(option['payment_needed'])} needed',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            isSelected
                ? Icons.check_circle
                : affordable
                ? Icons.check_circle_outline
                : Icons.lock_outline,
            color: isSelected
                ? AppTheme.successGreen
                : affordable
                ? AppTheme.brandBlue
                : AppTheme.textMuted,
          ),
        ],
      ),
    );
  }

  Widget _timeline(Map<String, dynamic> data) {
    final stages = (data['timeline'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Two-stage payment timeline',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 13),
            for (var index = 0; index < stages.length; index++)
              _timelineStage(stages[index], index, index == stages.length - 1),
          ],
        ),
      ),
    );
  }

  Widget _timelineStage(Map<String, dynamic> stage, int index, bool last) {
    final amount = stage['amount'];
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 30,
            child: Column(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: index == 0
                      ? AppTheme.brandBlue
                      : AppTheme.brandBlueLight,
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      color: index == 0 ? Colors.white : AppTheme.brandBlue,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (!last)
                  Expanded(
                    child: Container(width: 2, color: AppTheme.borderSubtle),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          stage['stage']?.toString() ?? '',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      if (amount != null)
                        Text(
                          dollars(amount),
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                    ],
                  ),
                  Text(
                    dateLabel(stage['date']),
                    style: const TextStyle(
                      color: AppTheme.brandBlue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    stage['description']?.toString() ?? '',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cashProtection(Map<String, dynamic> data) => Card(
    child: Padding(
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                color: AppTheme.brandBlue,
              ),
              SizedBox(width: 8),
              Text(
                'Cash protection',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 9),
          _valueRow('Checking available', dollars(data['checking_funds'])),
          _valueRow(
            'Upcoming bills protected',
            dollars(data['upcoming_bills_2weeks']),
          ),
          _valueRow('Safety buffer', dollars(data['safety_buffer'])),
          _valueRow(
            'Maximum safe payment',
            dollars(data['max_safe_payment_today']),
          ),
        ],
      ),
    ),
  );

  Widget _reminderCard(Map<String, dynamic> data) => Card(
    child: Padding(
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: remindersEnabled,
            title: const Text(
              'Statement reminders',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: const Text(
              'Early-payment, statement-close and due-date reminders',
            ),
            onChanged: (value) {
              setState(() => remindersEnabled = value);
              refresh();
            },
          ),
          if (remindersEnabled) ...[
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: reminderLeadDays,
                    decoration: const InputDecoration(labelText: 'First alert'),
                    items: const [
                      DropdownMenuItem(value: 3, child: Text('3 days early')),
                      DropdownMenuItem(value: 5, child: Text('5 days early')),
                      DropdownMenuItem(value: 7, child: Text('7 days early')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      reminderLeadDays = value;
                      refresh();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: processingDays,
                    decoration: const InputDecoration(
                      labelText: 'Processing buffer',
                    ),
                    items: const [
                      DropdownMenuItem(value: 2, child: Text('2 days')),
                      DropdownMenuItem(value: 3, child: Text('3 days')),
                      DropdownMenuItem(value: 5, child: Text('5 days')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      processingDays = value;
                      refresh();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Text(
              'Estimated reporting window: ${dateLabel((data['estimated_reporting_window'] as Map?)?['start'])}–${dateLabel((data['estimated_reporting_window'] as Map?)?['end'])}. The issuer may report on a different date.',
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _metric(String label, String value) => Card(
    child: Padding(
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: AppTheme.brandNavy,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _valueRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(child: Text(label, style: const TextStyle(fontSize: 12))),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    ),
  );

  Widget _errorCard() => Card(
    color: AppTheme.riskRedBg,
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Text(error!, style: const TextStyle(color: AppTheme.riskRedText)),
          TextButton(onPressed: refresh, child: const Text('Retry')),
        ],
      ),
    ),
  );
}
