import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/app_theme.dart';
import '../../core/api_client/api_client.dart';
import '../../shared/debounced_button.dart';
import '../../shared/disclaimer_banner.dart';
import '../../shared/status_badge.dart';

class JointNewTransferScreen extends StatefulWidget {
  const JointNewTransferScreen({super.key});

  @override
  State<JointNewTransferScreen> createState() => _JointNewTransferScreenState();
}

class _JointNewTransferScreenState extends State<JointNewTransferScreen> {
  final TextEditingController _amountController = TextEditingController(text: "850");
  final TextEditingController _merchantController = TextEditingController(text: "Best Buy");
  String _selectedCategory = "Electronics";
  Map<String, dynamic>? _precheckResult;

  Future<void> _runPrecheck() async {
    final amount = double.tryParse(_amountController.text) ?? 850.0;
    final res = await ApiClient.instance.precheckJoint(
      amount: amount,
      merchant: _merchantController.text,
    );
    if (mounted) {
      setState(() {
        _precheckResult = res;
      });
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _merchantController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Pre-check Joint Transfer"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/joint'),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: StatusBadge(type: StatusBadgeType.demoFixture, compact: true),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("TRANSFER DETAILS", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.textMuted)),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _amountController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: "Amount (\$)",
                          prefixText: "\$ ",
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _merchantController,
                        decoration: const InputDecoration(
                          labelText: "Merchant or Payee",
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _selectedCategory,
                        decoration: const InputDecoration(labelText: "Category"),
                        items: const [
                          DropdownMenuItem(value: "Electronics", child: Text("Electronics")),
                          DropdownMenuItem(value: "Groceries", child: Text("Groceries")),
                          DropdownMenuItem(value: "Home Improvement", child: Text("Home Improvement")),
                          DropdownMenuItem(value: "Travel", child: Text("Travel")),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedCategory = val);
                        },
                      ),
                      const SizedBox(height: 16),
                      DebouncedButton(
                        onPressed: _runPrecheck,
                        backgroundColor: AppTheme.brandBlue,
                        child: const Text("Evaluate In-App Risk & Threshold"),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              if (_precheckResult != null) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: (_precheckResult!["is_unusual"] ?? false) ? AppTheme.riskRedBg : AppTheme.successGreenBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: (_precheckResult!["is_unusual"] ?? false) ? const Color(0xFFFECACA) : const Color(0xFFA7F3D0),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            (_precheckResult!["is_unusual"] ?? false) ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                            color: (_precheckResult!["is_unusual"] ?? false) ? AppTheme.riskRed : AppTheme.successGreen,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            (_precheckResult!["is_unusual"] ?? false) ? "Partner Review Triggered" : "Standard Transfer (No Review Required)",
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: (_precheckResult!["is_unusual"] ?? false) ? AppTheme.riskRedText : AppTheme.successGreenText,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _precheckResult!["explanation"] ?? "Evaluation complete.",
                        style: TextStyle(
                          fontSize: 11.5,
                          color: (_precheckResult!["is_unusual"] ?? false) ? AppTheme.riskRedText : AppTheme.successGreenText,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],

              const DisclaimerBanner(
                text: "CreditPilot pre-checks apply to app-initiated transfers. Outside direct debit or bank transactions are not intercepted.",
              ),
            ],
          ),
        ),
      ),
    );
  }
}
