import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';

class _CopilotMessage {
  final String role;
  final String text;
  final Map<String, dynamic>? plan;
  const _CopilotMessage(this.role, this.text, {this.plan});
}

const _welcomeMessage = _CopilotMessage(
  'assistant',
  'Tell me your trip plan and the expected cost of each part. I’ll build a card-by-card strategy using your current balances, rewards and upcoming bills.',
);

Future<void> showCardsTripCopilot(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _CardsTripCopilotSheet(),
  );
}

class _CardsTripCopilotSheet extends StatefulWidget {
  const _CardsTripCopilotSheet();
  @override
  State<_CardsTripCopilotSheet> createState() => _CardsTripCopilotSheetState();
}

class _CardsTripCopilotSheetState extends State<_CardsTripCopilotSheet> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _inputFocus = FocusNode();
  final List<_CopilotMessage> _messages = [_welcomeMessage];
  final List<Map<String, String>> _history = [];
  bool _busy = false;
  String? _error;
  double _targetPct = 30;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  String _money(dynamic value) =>
      '\$${(double.tryParse(value.toString()) ?? 0).toStringAsFixed(2)}';

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final message = _input.text.trim();
    if (_busy || message.length < 2 || message.length > 1500) return;
    _input.clear();
    final requestHistory = List<Map<String, String>>.from(_history);
    setState(() {
      _busy = true;
      _error = null;
      _messages.add(_CopilotMessage('user', message));
    });
    _scrollToBottom();
    try {
      final result = await ApiService.planTripSpending(
        message: message,
        history: requestHistory,
        targetPct: _targetPct,
      );
      if (!mounted) return;
      final reply = result['assistant_message']?.toString().trim();
      final assistantText = reply == null || reply.isEmpty
          ? 'I mapped the purchases in your trip plan.'
          : reply;
      setState(() {
        _messages.add(
          _CopilotMessage('assistant', assistantText, plan: result),
        );
        _history
          ..add({'role': 'user', 'content': message})
          ..add({'role': 'assistant', 'content': assistantText});
        if (_history.length > 8) {
          _history.removeRange(0, _history.length - 8);
        }
      });
    } catch (exception) {
      if (mounted) setState(() => _error = exception.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
      _scrollToBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: Container(
          height: MediaQuery.sizeOf(context).height * .92,
          decoration: const BoxDecoration(
            color: Color(0xFFF7F9FC),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              _header(),
              _strategyBar(),
              Expanded(
                child: ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  children: [
                    for (final message in _messages) _message(message),
                    if (_messages.length == 1) _welcomeExperience(),
                    if (_busy) _thinkingCard(),
                    if (_error != null)
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.riskRedBg,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: AppTheme.riskRedText),
                        ),
                      ),
                  ],
                ),
              ),
              _composer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 15, 10, 15),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF061B35), Color(0xFF0A4B8F), Color(0xFF2563EB)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF38BDF8), Color(0xFFA78BFA)],
              ),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Color(0x5538BDF8), blurRadius: 16)],
            ),
            child: const Icon(Icons.auto_awesome, color: Colors.white),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Flexible(
                      child: Text(
                        'Trip Spending Copilot',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFA78BFA).withValues(alpha: .22),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: const Color(0xFFA78BFA)),
                      ),
                      child: const Text(
                        'AI PRO',
                        style: TextStyle(
                          color: Color(0xFFE9D5FF),
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .8,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                const Row(
                  children: [
                    Icon(Icons.circle, color: Color(0xFF4ADE80), size: 8),
                    SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        'Live planning • Verified card math • No transactions',
                        style: TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close assistant',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _strategyBar() {
    final modes = <(String, double, IconData)>[
      ('Protect credit', 20, Icons.shield_outlined),
      ('Balanced', 30, Icons.balance_outlined),
      ('Max rewards', 100, Icons.stars_outlined),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 9, 14, 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppTheme.borderSubtle)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const Text(
              'Planning mode',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 10),
            for (final mode in modes) ...[
              ChoiceChip(
                avatar: Icon(mode.$3, size: 15),
                label: Text(mode.$1),
                selected: _targetPct == mode.$2,
                onSelected: _busy
                    ? null
                    : (_) => setState(() => _targetPct = mode.$2),
              ),
              const SizedBox(width: 7),
            ],
          ],
        ),
      ),
    );
  }

  Widget _welcomeExperience() {
    return Container(
      margin: const EdgeInsets.only(top: 2, bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFFFFF), Color(0xFFF1F5FF)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD8E5FA)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'One message. A complete spending strategy.',
            style: TextStyle(
              color: AppTheme.brandNavy,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 12),
          _Capability(
            icon: Icons.route_outlined,
            title: 'Multi-purchase itinerary',
            subtitle: 'Flights, stays, dining and transport in one plan',
          ),
          _Capability(
            icon: Icons.account_balance_wallet_outlined,
            title: 'Cumulative card intelligence',
            subtitle: 'Every planned charge updates the next decision',
          ),
          _Capability(
            icon: Icons.warning_amber_rounded,
            title: 'Cash-flow guardrails',
            subtitle: 'Upcoming bills stay visible before rewards',
          ),
        ],
      ),
    );
  }

  Widget _thinkingCard() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFEFF6FF), Color(0xFFF5F3FF)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Building your smart itinerary',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  'Parsing costs → simulating balances → ranking cards',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _message(_CopilotMessage message) {
    final user = message.role == 'user';
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        width: user ? null : double.infinity,
        constraints: BoxConstraints(maxWidth: user ? 560 : 780),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          gradient: user
              ? const LinearGradient(
                  colors: [Color(0xFF0A4B8F), Color(0xFF2563EB)],
                )
              : null,
          color: user ? null : Colors.white,
          borderRadius: BorderRadius.circular(17),
          border: user ? null : Border.all(color: AppTheme.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!user) ...[
              const Row(
                children: [
                  Icon(Icons.auto_awesome, size: 14, color: Color(0xFF7C3AED)),
                  SizedBox(width: 5),
                  Text(
                    'COPILOT',
                    style: TextStyle(
                      color: Color(0xFF7C3AED),
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .8,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
            Text(
              message.text,
              style: TextStyle(
                color: user ? Colors.white : AppTheme.brandNavy,
                height: 1.4,
              ),
            ),
            if (message.plan != null) _plan(message.plan!),
          ],
        ),
      ),
    );
  }

  Widget _plan(Map<String, dynamic> plan) {
    final recommendations = (plan['recommendations'] as List? ?? const [])
        .whereType<Map>()
        .toList();
    final missing = (plan['missing_information'] as List? ?? const []);
    if (recommendations.isEmpty && missing.isEmpty) return const SizedBox();
    final summary = Map<String, dynamic>.from(
      (plan['summary'] as Map?) ?? const <String, dynamic>{},
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (recommendations.isNotEmpty) ...[
          const SizedBox(height: 12),
          _planHero(plan, summary, recommendations),
          const SizedBox(height: 10),
          for (var index = 0; index < recommendations.length; index++)
            _recommendation(
              Map<String, dynamic>.from(recommendations[index]),
              index,
            ),
        ],
        if (missing.isNotEmpty) ...[
          const SizedBox(height: 9),
          for (final item in missing)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.help_outline, size: 17),
                  const SizedBox(width: 6),
                  Expanded(child: Text(item.toString())),
                ],
              ),
            ),
        ],
        if (recommendations.isNotEmpty) ...[
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => _copyPlan(plan),
                icon: const Icon(Icons.copy_all_outlined, size: 17),
                label: const Text('Copy plan'),
              ),
              const SizedBox(width: 7),
              TextButton.icon(
                onPressed: () => _inputFocus.requestFocus(),
                icon: const Icon(Icons.tune, size: 17),
                label: const Text('Refine'),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Start a new plan',
                onPressed: _startOver,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          Text(
            plan['disclaimer']?.toString() ?? '',
            style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
          ),
        ],
      ],
    );
  }

  Widget _planHero(
    Map<String, dynamic> plan,
    Map<String, dynamic> summary,
    List<Map<dynamic, dynamic>> recommendations,
  ) {
    final safeCount = recommendations
        .where((item) => item['verdict']?.toString() == 'safe_to_spend')
        .length;
    final allSafe = safeCount == recommendations.length;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F2F53), Color(0xFF174E86)],
        ),
        borderRadius: BorderRadius.all(Radius.circular(18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.route, color: Color(0xFF7DD3FC), size: 20),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  plan['trip_title']?.toString() ?? 'Your trip plan',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color:
                      (allSafe
                              ? const Color(0xFF4ADE80)
                              : const Color(0xFFFBBF24))
                          .withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  allSafe ? 'READY' : 'REVIEW',
                  style: TextStyle(
                    color: allSafe
                        ? const Color(0xFF86EFAC)
                        : const Color(0xFFFDE68A),
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              _heroMetric('PLANNED SPEND', _money(summary['planned_spend'])),
              _heroMetric('EST. REWARDS', _money(summary['estimated_rewards'])),
              _heroMetric(
                'CASH-FLOW SAFE',
                '$safeCount/${recommendations.length}',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroMetric(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 8,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _recommendation(Map<String, dynamic> item, int index) {
    final card = Map<String, dynamic>.from(
      (item['recommended_card'] as Map?) ?? const <String, dynamic>{},
    );
    final alternatives = (item['alternatives'] as List? ?? const [])
        .whereType<Map>()
        .toList();
    final safe = item['verdict']?.toString() == 'safe_to_spend';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: safe ? const Color(0xFF86EFAC) : const Color(0xFFFDBA74),
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: index == 0,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          childrenPadding: const EdgeInsets.fromLTRB(13, 0, 13, 13),
          leading: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2FF),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              _categoryIcon(item['category']?.toString()),
              size: 19,
              color: AppTheme.brandBlue,
            ),
          ),
          title: Text(
            '${item['merchant_or_purpose']} • ${_money(item['amount'])}',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
          ),
          subtitle: Text(
            card.isEmpty
                ? 'No card has enough available credit'
                : '${card['display_name']} • ${card['reward_rate_pct']}% rewards',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: safe ? AppTheme.successGreenText : const Color(0xFF9A3412),
              fontSize: 11,
            ),
          ),
          children: [
            if (card.isNotEmpty) ...[
              _utilizationMeter(card),
              const SizedBox(height: 9),
              Row(
                children: [
                  _detailMetric('Reward value', _money(card['rewards_amount'])),
                  _detailMetric(
                    'Credit left',
                    _money(card['available_credit_after']),
                  ),
                  _detailMetric(
                    'Card ending',
                    '•••• ${card['last4'] ?? '0000'}',
                  ),
                ],
              ),
            ],
            if (!safe) ...[
              const SizedBox(height: 9),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${item['headline'] ?? 'Review before spending'}\n${item['timing_advice'] ?? ''}',
                  style: const TextStyle(
                    color: Color(0xFF9A3412),
                    fontSize: 10,
                    height: 1.35,
                  ),
                ),
              ),
            ],
            if (alternatives.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'NEXT BEST OPTIONS',
                  style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .7,
                  ),
                ),
              ),
              const SizedBox(height: 5),
              for (final alternative in alternatives)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.credit_card, size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${alternative['display_name']} • ${alternative['reward_rate_pct']}% • ${alternative['utilization_after_pct']}% utilization',
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _utilizationMeter(Map<String, dynamic> card) {
    final utilization =
        (double.tryParse(card['utilization_after_pct'].toString()) ?? 0)
            .clamp(0, 100)
            .toDouble();
    final color = utilization < 20
        ? const Color(0xFF16A34A)
        : utilization < 30
        ? const Color(0xFFF59E0B)
        : const Color(0xFFDC2626);
    return Column(
      children: [
        Row(
          children: [
            const Text('Projected utilization', style: TextStyle(fontSize: 10)),
            const Spacer(),
            Text(
              '${utilization.toStringAsFixed(2)}%',
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: utilization / 100,
            minHeight: 7,
            backgroundColor: const Color(0xFFE5E7EB),
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _detailMetric(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 9, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Future<void> _copyPlan(Map<String, dynamic> plan) async {
    final items = (plan['recommendations'] as List? ?? const [])
        .whereType<Map>();
    final lines = <String>[
      plan['trip_title']?.toString() ?? 'Trip spending plan',
      for (final item in items)
        '${item['merchant_or_purpose']}: ${_money(item['amount'])} — '
            '${(item['recommended_card'] as Map?)?['display_name'] ?? 'No available card'}',
      'Planning estimate only; no purchase or payment was initiated.',
    ];
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Trip strategy copied.')));
  }

  void _startOver() {
    setState(() {
      _messages
        ..clear()
        ..add(_welcomeMessage);
      _history.clear();
      _error = null;
    });
    _input.clear();
    _inputFocus.requestFocus();
  }

  IconData _categoryIcon(String? category) {
    switch (category) {
      case 'flights':
        return Icons.flight_takeoff;
      case 'travel':
        return Icons.hotel_outlined;
      case 'dining':
        return Icons.restaurant_outlined;
      case 'transit':
        return Icons.directions_transit;
      case 'gas':
        return Icons.local_gas_station_outlined;
      case 'groceries':
        return Icons.local_grocery_store_outlined;
      default:
        return Icons.shopping_bag_outlined;
    }
  }

  Widget _composer() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppTheme.borderSubtle)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                focusNode: _inputFocus,
                enabled: !_busy,
                minLines: 1,
                maxLines: 4,
                maxLength: 1500,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: const InputDecoration(
                  hintText: 'Describe your trip and expected costs…',
                  prefixIcon: Icon(Icons.travel_explore_outlined),
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 9),
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF2563EB), Color(0xFF7C3AED)],
                ),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                tooltip: 'Send trip plan',
                onPressed: _busy ? null : _send,
                color: Colors.white,
                icon: const Icon(Icons.arrow_upward_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Capability extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _Capability({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFE5EDFF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: AppTheme.brandBlue),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
