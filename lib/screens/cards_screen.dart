import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/location_service.dart';
import '../theme/app_theme.dart';
import '../widgets/cards_trip_copilot.dart';

class CardsScreen extends StatefulWidget {
  final Function(int)? onNavigateTab;
  final void Function(String account)? onPlanPaydown;

  const CardsScreen({super.key, this.onNavigateTab, this.onPlanPaydown});

  @override
  State<CardsScreen> createState() => _CardsScreenState();
}

class _CardsScreenState extends State<CardsScreen> {
  static const _categories = <String, String>{
    'groceries': 'Groceries',
    'gas': 'Gas or EV charging',
    'dining': 'Dining or coffee',
    'flights': 'Flights and airfare',
    'travel': 'Travel',
    'transit': 'Transit or parking',
    'streaming': 'Streaming',
    'shopping': 'Shopping',
    'entertainment': 'Entertainment',
    'other': 'Other purchase',
  };

  final amountController = TextEditingController(text: '50');
  final merchantController = TextEditingController();
  Timer? _amountDebounce;
  String category = 'other';
  bool useCurrentLocation = true;
  bool locating = true;
  bool evaluating = false;
  int _requestNumber = 0;
  List<Map<String, dynamic>> nearbyPlaces = [];
  String? selectedPlaceId;
  String? locationMessage;
  Map<String, dynamic>? result;
  String? error;

  @override
  void initState() {
    super.initState();
    _loadCurrentLocation();
  }

  @override
  void dispose() {
    _amountDebounce?.cancel();
    amountController.dispose();
    merchantController.dispose();
    super.dispose();
  }

  double? get price {
    final value = double.tryParse(amountController.text.trim());
    return value != null && value.isFinite ? value : null;
  }

  Map<String, dynamic> get cardResult => Map<String, dynamic>.from(
    (result?['card_options'] as Map?) ?? const <String, dynamic>{},
  );

  Map<String, dynamic> get guidance => Map<String, dynamic>.from(
    (result?['purchase_guidance'] as Map?) ?? const <String, dynamic>{},
  );

  Map<String, dynamic> get cashflow => Map<String, dynamic>.from(
    (result?['cashflow_before_purchase'] as Map?) ?? const <String, dynamic>{},
  );

  Map<String, dynamic>? get selectedPlace {
    for (final place in nearbyPlaces) {
      if (place['place_id']?.toString() == selectedPlaceId) return place;
    }
    return null;
  }

  String dollars(dynamic value) =>
      '\$${(double.tryParse(value.toString()) ?? 0).toStringAsFixed(2)}';

  String get _fingerprint =>
      '${amountController.text.trim()}|${merchantController.text.trim()}|$category';

  void _invalidateResult({bool scheduleEvaluation = false}) {
    _requestNumber++;
    setState(() {
      result = null;
      error = null;
      evaluating = false;
    });
    if (scheduleEvaluation && merchantController.text.trim().isNotEmpty) {
      _amountDebounce?.cancel();
      _amountDebounce = Timer(const Duration(milliseconds: 450), evaluate);
    }
  }

  void _setAmount(double amount, {bool debounce = true}) {
    amountController.text = amount.toStringAsFixed(amount % 1 == 0 ? 0 : 2);
    amountController.selection = TextSelection.collapsed(
      offset: amountController.text.length,
    );
    _invalidateResult(scheduleEvaluation: debounce);
  }

  Future<void> _loadCurrentLocation({bool refresh = false}) async {
    setState(() {
      locating = true;
      locationMessage = 'Finding nearby merchants…';
      useCurrentLocation = true;
    });
    final location = refresh
        ? await LocationService.instance.refresh()
        : await LocationService.instance.initialize();
    if (!mounted) return;
    if (location.position == null) {
      setState(() {
        locating = false;
        useCurrentLocation = false;
        locationMessage = location.message;
      });
      return;
    }

    try {
      final response = await ApiService.getNearbyMerchants(
        latitude: location.position!.latitude,
        longitude: location.position!.longitude,
      );
      if (!mounted) return;
      final places = ((response['places'] as List?) ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      if (places.isEmpty) {
        setState(() {
          locating = false;
          useCurrentLocation = false;
          locationMessage = response['configured'] == false
              ? 'Nearby merchant detection is unavailable. Enter the merchant manually.'
              : 'No purchase location was identified nearby. Enter it manually or try again.';
        });
        return;
      }
      nearbyPlaces = places;
      _selectPlace(places.first, notify: false);
      setState(() {
        locating = false;
        locationMessage =
            'Nearby merchant detected. Confirm the location before paying.';
      });
      await evaluate();
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        locating = false;
        useCurrentLocation = false;
        locationMessage = exception.toString();
      });
    }
  }

  void _selectPlace(Map<String, dynamic> place, {bool notify = true}) {
    merchantController.text = place['name']?.toString() ?? '';
    final detectedCategory = place['category']?.toString() ?? 'other';
    category = _categories.containsKey(detectedCategory)
        ? detectedCategory
        : 'other';
    selectedPlaceId = place['place_id']?.toString();
    _requestNumber++;
    result = null;
    error = null;
    if (notify) {
      setState(() {});
      evaluate();
    }
  }

  void _setInputMode(bool locationMode) {
    if (locationMode == useCurrentLocation) return;
    setState(() {
      useCurrentLocation = locationMode;
      result = null;
      error = null;
    });
    if (locationMode) {
      _loadCurrentLocation(refresh: true);
    } else {
      selectedPlaceId = null;
      merchantController.clear();
      category = 'other';
    }
  }

  Future<void> evaluate() async {
    final purchaseAmount = price;
    final merchant = merchantController.text.trim();
    if (purchaseAmount == null ||
        purchaseAmount <= 0 ||
        purchaseAmount > 100000) {
      setState(() => error = 'Enter an amount between \$0.01 and \$100,000.');
      return;
    }
    if (merchant.isEmpty) {
      setState(() => error = 'Enter or select a merchant.');
      return;
    }

    final request = ++_requestNumber;
    final requestFingerprint = _fingerprint;
    setState(() {
      evaluating = true;
      error = null;
    });
    try {
      final response = await ApiService.simulatePurchase(
        amount: purchaseAmount,
        category: category,
        merchant: merchant,
      );
      if (!mounted ||
          request != _requestNumber ||
          requestFingerprint != _fingerprint) {
        return;
      }
      setState(() {
        result = response;
        evaluating = false;
      });
    } catch (exception) {
      if (!mounted || request != _requestNumber) return;
      setState(() {
        error = exception.toString();
        evaluating = false;
      });
    }
  }

  void _showReasoning() {
    final reasons = (guidance['reasons'] as List?) ?? const [];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Why this recommendation?',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              for (final reason in reasons)
                Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.check_circle_outline,
                        size: 18,
                        color: AppTheme.brandBlue,
                      ),
                      const SizedBox(width: 9),
                      Expanded(child: Text(reason.toString())),
                    ],
                  ),
                ),
              const Divider(),
              Text(
                guidance['calculation_note']?.toString() ?? '',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _planPaydown(Map best) {
    final account = best['card_name']?.toString();
    if (account == null) return;
    if (widget.onPlanPaydown != null) {
      widget.onPlanPaydown!(account);
    } else {
      widget.onNavigateTab?.call(2);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cards = (cardResult['cards'] as List?) ?? const [];
    final best = (result?['recommended_card'] as Map?) ?? const {};
    final currentPrice = (price ?? 50).clamp(1, 1000).toDouble();

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('trip-copilot-button'),
        heroTag: 'cards-trip-copilot',
        tooltip: 'Open Trip Spending Copilot',
        onPressed: () => showCardsTripCopilot(context),
        backgroundColor: const Color(0xFF111F3D),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.auto_awesome),
        label: const Text('Copilot AI'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _header(),
            const SizedBox(height: 14),
            _modeSelector(),
            if (useCurrentLocation || locationMessage != null) ...[
              const SizedBox(height: 10),
              _locationStatus(),
            ],
            const SizedBox(height: 12),
            _purchaseInput(currentPrice),
            if (evaluating)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: LinearProgressIndicator(),
              ),
            if (error != null) ...[
              const SizedBox(height: 10),
              Card(
                color: AppTheme.riskRedBg,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    error!,
                    style: const TextStyle(color: AppTheme.riskRedText),
                  ),
                ),
              ),
            ],
            if (result != null) ...[
              const SizedBox(height: 12),
              _verdictCard(best),
              const SizedBox(height: 10),
              _impactSummary(),
              const SizedBox(height: 10),
              _timingCard(),
              const SizedBox(height: 16),
              const Text(
                'Card comparison',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.brandNavy,
                ),
              ),
              const SizedBox(height: 8),
              for (final raw in cards)
                _cardOption(Map<String, dynamic>.from(raw as Map), best),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _showReasoning,
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Why This Recommendation?'),
              ),
              if (best.isNotEmpty &&
                  (double.tryParse(best['paydown_to_target'].toString()) ?? 0) >
                      0) ...[
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () => _planPaydown(best),
                  icon: const Icon(Icons.trending_down),
                  label: Text(
                    'Plan ${dollars(best['paydown_to_target'])} Paydown First',
                  ),
                ),
              ],
              const SizedBox(height: 10),
              const Text(
                'Confirm the merchant category and issuer reward terms before paying. No purchase or payment is initiated from this screen.',
                style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF07284C), Color(0xFF0A4B8F)],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bolt, color: Color(0xFF7DD3FC)),
              SizedBox(width: 7),
              Text(
                'SpendAhead Live',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          SizedBox(height: 7),
          Text(
            'The right card, at the right place, without compromising what comes next.',
            style: TextStyle(color: Colors.white70, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _modeSelector() {
    return Row(
      children: [
        Expanded(
          child: _modeButton(
            selected: useCurrentLocation,
            icon: Icons.my_location,
            label: 'Current location',
            onPressed: () => _setInputMode(true),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _modeButton(
            selected: !useCurrentLocation,
            icon: Icons.edit_location_alt_outlined,
            label: 'Enter manually',
            onPressed: () => _setInputMode(false),
          ),
        ),
      ],
    );
  }

  Widget _purchaseInput(double currentPrice) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (useCurrentLocation && nearbyPlaces.isNotEmpty)
              DropdownButtonFormField<String>(
                key: ValueKey(selectedPlaceId),
                initialValue: selectedPlaceId,
                decoration: InputDecoration(
                  labelText: 'Detected merchant',
                  prefixIcon: const Icon(Icons.storefront_outlined),
                  helperText:
                      '${selectedPlace?['proximity_confidence'] ?? 'low'} proximity confidence · confirm before paying',
                ),
                items: nearbyPlaces.map((place) {
                  final distance = place['distance_m'];
                  final suffix = distance == null ? '' : ' · ${distance}m';
                  return DropdownMenuItem(
                    value: place['place_id']?.toString(),
                    child: Text(
                      '${place['name']}$suffix',
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (id) {
                  for (final place in nearbyPlaces) {
                    if (place['place_id']?.toString() == id) {
                      _selectPlace(place);
                      return;
                    }
                  }
                },
              )
            else
              TextField(
                controller: merchantController,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => _invalidateResult(scheduleEvaluation: true),
                decoration: const InputDecoration(
                  labelText: 'Merchant or purchase purpose',
                  hintText: 'Example: coffee shop, airline ticket, supermarket',
                  prefixIcon: Icon(Icons.storefront_outlined),
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => _invalidateResult(scheduleEvaluation: true),
              decoration: const InputDecoration(
                labelText: 'What-if purchase amount (USD)',
                prefixIcon: Icon(Icons.attach_money),
              ),
            ),
            Slider(
              value: currentPrice,
              min: 1,
              max: 1000,
              divisions: 200,
              label: dollars(currentPrice),
              onChanged: (value) => _setAmount((value / 5).round() * 5),
            ),
            Wrap(
              spacing: 7,
              children: [25, 50, 100, 250]
                  .map(
                    (amount) => ActionChip(
                      label: Text('\$$amount'),
                      onPressed: () => _setAmount(amount.toDouble()),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              key: ValueKey(category),
              initialValue: category,
              decoration: const InputDecoration(
                labelText: 'Reward category',
                prefixIcon: Icon(Icons.category_outlined),
              ),
              items: _categories.entries
                  .map(
                    (entry) => DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                category = value;
                _invalidateResult(scheduleEvaluation: true);
              },
            ),
            const SizedBox(height: 8),
            const Text(
              'Recommendations update automatically as you change the purchase.',
              style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _verdictCard(Map best) {
    final verdict = guidance['verdict']?.toString() ?? 'caution';
    final safe = verdict == 'safe_to_spend';
    final blocked = verdict == 'no_capacity' || verdict == 'consider_waiting';
    final color = safe
        ? AppTheme.successGreenText
        : blocked
        ? AppTheme.riskRedText
        : const Color(0xFF9A3412);
    final background = safe
        ? AppTheme.successGreenBg
        : blocked
        ? AppTheme.riskRedBg
        : const Color(0xFFFFF7ED);
    final icon = safe
        ? Icons.verified_outlined
        : blocked
        ? Icons.warning_amber_rounded
        : Icons.info_outline;
    return Card(
      color: background,
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Text(
                  verdict.replaceAll('_', ' ').toUpperCase(),
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .4,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              guidance['headline']?.toString() ?? 'Review this purchase',
              style: const TextStyle(
                color: AppTheme.brandNavy,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (best.isNotEmpty) ...[
              const SizedBox(height: 9),
              Text(
                '${blocked ? 'If you proceed, use' : 'Use'} ${best['display_name'] ?? best['card_name']} •••• ${best['last4'] ?? '0000'}',
                style: const TextStyle(
                  color: AppTheme.brandNavy,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '${best['reward_rate_pct']}% rewards · ${dollars(best['rewards_amount'])} estimated value · ${best['utilization_after_pct']}% utilization',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _impactSummary() {
    return Row(
      children: [
        Expanded(
          child: _metric(
            'Overall utilization',
            '${cardResult['aggregate_utilization_before_pct']}% → ${cardResult['aggregate_utilization_after_pct']}%',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _metric(
            'Bills next ${cashflow['horizon_days'] ?? 14} days',
            dollars(cashflow['total_bills_due']),
          ),
        ),
      ],
    );
  }

  Widget _timingCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.schedule, color: AppTheme.brandBlue),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Timing guidance',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 3),
                  Text(guidance['timing_advice']?.toString() ?? ''),
                  const SizedBox(height: 6),
                  Text(
                    'Checking after upcoming bills: ${dollars(guidance['cash_after_upcoming_bills'])}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardOption(Map<String, dynamic> item, Map best) {
    final recommended = item['card_name'] == best['card_name'];
    final hasCapacity = item['has_capacity'] == true;
    final withinTarget = item['within_target'] == true;
    return Card(
      shape: recommended
          ? RoundedRectangleBorder(
              side: const BorderSide(color: AppTheme.brandBlue, width: 1.5),
              borderRadius: BorderRadius.circular(12),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final details = _cardDetails(
              item,
              hasCapacity: hasCapacity,
              withinTarget: withinTarget,
            );
            if (constraints.maxWidth >= 680) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 290, child: _cardFace(item, recommended)),
                  const SizedBox(width: 18),
                  Expanded(child: details),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _cardFace(item, recommended),
                const SizedBox(height: 13),
                details,
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _cardDetails(
    Map<String, dynamic> item, {
    required bool hasCapacity,
    required bool withinTarget,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                item['benefit_summary']?.toString() ?? 'Everyday card rewards',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppTheme.brandNavy,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Chip(
              label: Text(
                item['decision_label']?.toString() ?? 'Alternative',
                style: const TextStyle(fontSize: 10),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 13,
          runSpacing: 7,
          children: [
            _statPill('${item['reward_rate_pct']}% rewards'),
            _statPill('${dollars(item['rewards_amount'])} value'),
            _statPill('${item['utilization_after_pct']}% utilization'),
            _statPill('${dollars(item['available_credit_after'])} credit left'),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          item['decision_explanation']?.toString() ?? '',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: hasCapacity && withinTarget
                ? AppTheme.successGreenText
                : AppTheme.riskRedText,
          ),
        ),
      ],
    );
  }

  Widget _statPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Text(text, style: const TextStyle(fontSize: 11)),
    );
  }

  Widget _cardFace(Map<String, dynamic> item, bool recommended) {
    final colors = _cardColors(item['visual_theme']?.toString() ?? 'ocean');
    final name =
        item['display_name']?.toString() ?? item['card_name'].toString();
    return AspectRatio(
      aspectRatio: 1.62,
      child: Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: colors.last.withValues(alpha: .25),
              blurRadius: 14,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -24,
              bottom: -45,
              child: Container(
                width: 145,
                height: 145,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .12),
                    width: 18,
                  ),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.contactless,
                      color: Colors.white70,
                      size: 24,
                    ),
                    const Spacer(),
                    if (recommended)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .18),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: const Text(
                          'BEST FOR THIS PURCHASE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                  ],
                ),
                const Spacer(),
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${item['issuer'] ?? 'Card issuer'}',
                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                ),
                const Spacer(),
                Row(
                  children: [
                    Text(
                      '••••  ••••  ••••  ${item['last4'] ?? '0000'}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .6,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      item['network']?.toString().toUpperCase() ?? 'CARD',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Color> _cardColors(String theme) {
    switch (theme) {
      case 'aurora':
        return const [Color(0xFF312E81), Color(0xFF0E7490), Color(0xFF0F172A)];
      case 'forest':
      case 'emerald':
        return const [Color(0xFF064E3B), Color(0xFF059669)];
      case 'violet':
      case 'plum':
        return const [Color(0xFF4C1D95), Color(0xFFBE185D)];
      case 'copper':
        return const [Color(0xFF7C2D12), Color(0xFFEA580C)];
      case 'rose':
        return const [Color(0xFF881337), Color(0xFFE11D48)];
      case 'sky':
        return const [Color(0xFF075985), Color(0xFF38BDF8)];
      case 'slate':
      case 'graphite':
        return const [Color(0xFF111827), Color(0xFF475569)];
      case 'midnight':
        return const [Color(0xFF020617), Color(0xFF1E3A8A)];
      default:
        return const [Color(0xFF0C4A6E), Color(0xFF0284C7)];
    }
  }

  Widget _metric(String label, String value) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: AppTheme.brandNavy,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeButton({
    required bool selected,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return selected
        ? ElevatedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(label),
          )
        : OutlinedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(label),
          );
  }

  Widget _locationStatus() {
    final confidence = selectedPlace?['proximity_confidence']?.toString();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: useCurrentLocation
            ? const Color(0xFFEFF6FF)
            : const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          if (locating)
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(
              useCurrentLocation
                  ? Icons.location_on_outlined
                  : Icons.location_off_outlined,
              size: 20,
              color: useCurrentLocation
                  ? AppTheme.brandBlue
                  : AppTheme.textSecondary,
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              confidence == null
                  ? locationMessage ?? 'Location is ready.'
                  : '${locationMessage ?? ''} ${confidence.toUpperCase()} proximity confidence.',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          if (!locating)
            IconButton(
              tooltip:
                  LocationService.instance.lastResult?.status ==
                      AppLocationStatus.deniedForever
                  ? 'Open location settings'
                  : 'Refresh nearby merchants',
              onPressed: () async {
                if (LocationService.instance.lastResult?.status ==
                    AppLocationStatus.deniedForever) {
                  await LocationService.instance.openSettings();
                } else {
                  await _loadCurrentLocation(refresh: true);
                }
              },
              icon: Icon(
                LocationService.instance.lastResult?.status ==
                        AppLocationStatus.deniedForever
                    ? Icons.settings_outlined
                    : Icons.refresh,
                size: 20,
              ),
            ),
        ],
      ),
    );
  }
}
