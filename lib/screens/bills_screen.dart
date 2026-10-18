import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';

/// Cashflow dashboard: authenticated balances + owner-editable demo bills.
class BillsScreen extends StatefulWidget {
  const BillsScreen({super.key});
  @override
  State<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends State<BillsScreen> {
  Map<String, dynamic>? forecast;
  List<Map<String, dynamic>> allBills = [];
  List<Map<String, dynamic>> transactions = [];
  List<Map<String, dynamic>> bankAccounts = [];
  Map<String, dynamic>? bankProfile;
  bool synthetic = false, loading = true;
  String? error;
  String? transactionWarning;

  @override
  void initState() {
    super.initState();
    reload();
  }

  String dollars(dynamic value) =>
      '\$' + (double.tryParse(value.toString()) ?? 0).toStringAsFixed(2);

  String shortDate(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    if (date == null) return value?.toString() ?? 'an upcoming date';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[date.month - 1] + ' ' + date.day.toString();
  }

  String shortfallPreview(Map<String, dynamic> data) {
    final bill = data['first_shortfall_bill']?.toString() ?? 'An upcoming bill';
    return 'Heads up—' + bill + ' may leave you ' +
        dollars(data['first_shortfall_amount']) + ' short on ' +
        shortDate(data['first_shortfall_date']) + '......';
  }

  Future<void> reload() async {
    if (mounted) setState(() { loading = true; error = null; });
    try {
      final bills = await ApiService.getBills();
      final dashboard = await ApiService.getDashboard();
      final result = Map<String, dynamic>.from(
          dashboard['bill_forecast'] as Map);
      final accounts = (dashboard['accounts'] as List? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      Map<String, dynamic>? profile;
      final isSynthetic = bills['source'] == 'synthetic_banking_demo';
      final entries = (bills['bills'] as List? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      entries.sort((a, b) => a['payment_date']
          .toString().compareTo(b['payment_date'].toString()));
      List<Map<String, dynamic>> recent = [];
      if (isSynthetic) {
        profile = await ApiService.getBankingProfile();
      }
      final tx = await ApiService.getTransactions(limit: 12);
      recent = (tx['transactions'] as List? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map)).toList();
      if (mounted) setState(() {
        forecast = result; allBills = entries; transactions = recent;
        bankAccounts = accounts; bankProfile = profile;
        final warnings = (tx['warnings'] as List? ?? []).join(' ');
        transactionWarning = warnings.isEmpty ? null : warnings;
        synthetic = isSynthetic; loading = false;
      });
    } catch (exception) {
      if (mounted) setState(() { error = exception.toString(); loading = false; });
    }
  }

  Future<void> editIncome() async {
    if (!synthetic) return;
    final ctrl = TextEditingController(
      text: bankProfile?['monthly_income']?.toString() ?? '0');
    try {
      final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Adjust monthly demo income'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Expected monthly income (USD)',
                helperText: 'Financial scenario only; no verified payroll'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Save')),
          ],
        ));
      if (yes != true) return;
      final income = double.tryParse(ctrl.text.trim());
      if (income == null || income < 0) {
        throw ApiException('Enter a valid nonnegative monthly income');
      }
      await ApiService.updateMonthlyIncome(income);
      if (mounted) await reload();
    } catch (exception) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(exception.toString())));
    } finally {
      ctrl.dispose();
    }
  }

  Future<void> editBill([Map<String, dynamic>? existing]) async {
    if (!synthetic) return;
    final payee = TextEditingController(text: existing?['payee']?.toString() ?? '');
    final cost = TextEditingController(
      text: existing?['payment_amount']?.toString() ?? '');
    var due = DateTime.tryParse(existing?['payment_date']?.toString() ?? '') ??
        DateTime.now().add(const Duration(days: 7));
    var category = existing?['category']?.toString() ?? 'other';
    var frequency = existing?['frequency']?.toString() ?? 'monthly';
    const categories = [
      'housing', 'utilities', 'internet', 'phone', 'insurance',
      'loan', 'fitness', 'streaming', 'education', 'transportation',
      'food', 'membership', 'other',
    ];
    if (!categories.contains(category)) category = 'other';
    if (!['monthly', 'one_time'].contains(frequency)) frequency = 'monthly';
    try {
      final save = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: Text(existing == null ? 'Add upcoming bill' : 'Edit bill'),
            content: SizedBox(width: 420, child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: payee, autofocus: true,
                  decoration: const InputDecoration(labelText: 'Payee / provider')),
                TextField(controller: cost,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Monthly payment amount (USD)')),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final selected = await showDatePicker(
                      context: dialogContext,
                      initialDate: due,
                      firstDate: DateTime.now().subtract(const Duration(days: 365)),
                      lastDate: DateTime.now().add(const Duration(days: 730)),
                    );
                    if (selected != null) update(() => due = selected);
                  },
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text('Due: ' + due.toIso8601String().substring(0, 10))),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: categories.map((name) =>
                      DropdownMenuItem(value: name, child: Text(name))).toList(),
                  onChanged: (v) { if (v != null) update(() => category = v); },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: frequency,
                  decoration: const InputDecoration(labelText: 'Frequency'),
                  items: const [
                    DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                    DropdownMenuItem(value: 'one_time', child: Text('One-time')),
                  ],
                  onChanged: (v) { if (v != null) update(() => frequency = v); },
                ),
              ]),
            )),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel')),
              FilledButton(
                onPressed: payee.text.trim().isEmpty ? null
                    : () => Navigator.pop(dialogContext, true),
                child: const Text('Save bill')),
            ],
          ),
        ),
      );
      if (save != true) return;
      final amount = double.tryParse(cost.text.trim()) ?? 0;
      if (payee.text.trim().length < 2 || amount <= 0) {
        throw ApiException('Enter a valid payee and positive payment amount');
      }
      final iso = due.toIso8601String().substring(0, 10);
      if (existing == null) {
        await ApiService.createBill(
          payee: payee.text.trim(), amount: amount, dueDate: iso,
          category: category, frequency: frequency);
      } else {
        await ApiService.updateBill(
          billId: existing['bill_id'].toString(),
          payee: payee.text.trim(), amount: amount, dueDate: iso,
          category: category, frequency: frequency);
      }
      if (!mounted) return;
      await reload();
    } catch (exception) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(exception.toString())));
    } finally {
      payee.dispose();
      cost.dispose();
    }
  }

  Future<void> removeBill(Map<String, dynamic> entry) async {
    final okay = await showDialog<bool>(context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete demo bill?'),
        content: Text('Remove ' + entry['payee'].toString() +
            ' from your personal simulated schedule?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ));
    if (okay != true) return;
    try {
      await ApiService.deleteBill(billId: entry['bill_id'].toString());
      await reload();
    } catch (exception) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(exception.toString())));
    }
  }

  Future<void> reviewTransfer() async {
    final value = double.tryParse(
        forecast?['suggested_savings_transfer'].toString() ?? '') ?? 0;
    if (value <= 0) return;
    final key = 'cp-demo-' + DateTime.now().microsecondsSinceEpoch.toString();
    try {
      final preview = await ApiService.transferPreview(
          amount: value, idempotencyKey: key);
      if (!mounted) return;
      final approved = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Confirm simulated transfer'),
          content: Text('Transfer ' + dollars(value) +
              ' from fictional savings to fictional checking?\n\n'
              'Protected reserve: ' + dollars(preview['protected_savings']) +
              '\nNo actual funds will move.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            if (preview['allowed'] == true)
              FilledButton(onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Confirm')),
          ],
        ),
      );
      if (approved != true) return;
      final result = await ApiService.executeTransfer(
          amount: value, idempotencyKey: key);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Demo transfer status: ' + result['status'].toString())));
      await reload(); // Synthetic balances now update, unlike old mock actions.
    } catch (exception) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(exception.toString())));
    }
  }

  Future<void> requestMoney() async {
    final amount = double.tryParse(
        forecast?['shortfall_amount'].toString() ?? '') ?? 0;
    if (amount <= 0) return;
    final contact = TextEditingController(text: 'Jamie');
    try {
      final requested = await showDialog<bool>(context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Request money from a contact'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Request ' + dollars(amount) +
                ' to cover the projected shortfall.'),
            const SizedBox(height: 12),
            TextField(controller: contact, autofocus: true,
              decoration: const InputDecoration(labelText: 'Contact name')),
            const SizedBox(height: 8),
            const Text('Demo request only. CreditPilot is not connected to '
                'messaging or payment contacts.',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Prepare request')),
          ],
        ));
      if (requested != true || !mounted) return;
      final name = contact.text.trim().isEmpty ? 'contact' : contact.text.trim();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Demo request prepared for ' + name + ': ' +
            dollars(amount) + '.')));
    } finally {
      contact.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) return Center(child: Column(
      mainAxisSize: MainAxisSize.min, children: [
        const Text('Unable to load bank scenario'),
        Padding(padding: const EdgeInsets.all(16),
          child: Text(error!, textAlign: TextAlign.center)),
        TextButton(onPressed: reload, child: const Text('Retry')),
      ],
    ));
    final d = forecast!;
    final shortage = d['is_shortfall'] == true;
    final proposal = double.tryParse(
        d['suggested_savings_transfer'].toString()) ?? 0;

    return Scaffold(body: SafeArea(child: RefreshIndicator(
      onRefresh: reload,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Cashflow & Bills', style: TextStyle(
            fontSize: 22, fontWeight: FontWeight.w800,
            color: AppTheme.brandNavy)),
        Text(synthetic
            ? 'Private fictional banking portfolio • interactive scenario'
            : 'Nessie sandbox accounts, bills and activity',
            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
        const SizedBox(height: 14),
        if (synthetic && bankProfile != null)
          Card(color: AppTheme.brandBlueLight,
            child: ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined,
                  color: AppTheme.brandNavy),
              title: Text('Personal financial scenario • ' +
                (bankProfile!['persona']?.toString().replaceAll('_', ' ') ?? 'member')),
              subtitle: Text('Monthly income: ' +
                  dollars(bankProfile!['monthly_income']) +
                  ' • ' + bankAccounts.length.toString() + ' fictional accounts'),
              trailing: IconButton(
                onPressed: editIncome,
                tooltip: 'Edit monthly income',
                icon: const Icon(Icons.edit_outlined)),
            )),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: metric('Checking', dollars(d['checking_balance']))),
          const SizedBox(width: 10),
          Expanded(child: metric('Bills due (7 days)', dollars(d['total_bills_due']))),
        ]),
        const SizedBox(height: 12),
        Card(color: shortage ? AppTheme.riskRedBg : const Color(0xFFE7F8EC),
          child: Padding(padding: const EdgeInsets.all(16), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(shortage ? '7-day cash warning' : 'Upcoming bills covered',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              Text(shortage ? dollars(d['shortfall_amount']) : 'On track',
                style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900,
                  color: shortage ? AppTheme.riskRed : AppTheme.brandNavy)),
              Text(shortage ? shortfallPreview(d)
                  : 'Checking covers the bills currently due in the next 7 days.',
                style: const TextStyle(fontSize: 11)),
              if (shortage) ...[
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton.icon(
                    onPressed: proposal > 0 ? reviewTransfer : null,
                    icon: const Icon(Icons.savings_outlined, size: 18),
                    label: Text('Move ' + dollars(proposal) + ' from savings')),
                  OutlinedButton.icon(
                    onPressed: requestMoney,
                    icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                    label: const Text('Request from a contact')),
                ]),
              ],
            ]))),
        if (bankAccounts.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text('My fictional accounts', style: TextStyle(
              fontWeight: FontWeight.w800, fontSize: 16)),
          Card(child: Column(children: [
            for (final account in bankAccounts)
              ListTile(
                dense: true,
                leading: Icon(
                  account['type'] == 'Credit Card'
                      ? Icons.credit_card_outlined : Icons.account_balance_outlined,
                  color: AppTheme.brandBlue),
                title: Text(account['nickname'].toString(),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text((account['institution'] ?? 'Demo institution').toString() +
                    ' •••• ' + (account['last4'] ?? '0000').toString()),
                trailing: Text(dollars(account['balance']),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
          ])),
        ],
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: Text('Upcoming bills (' + allBills.length.toString() + ')',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
          if (synthetic) FilledButton.tonalIcon(
            onPressed: () => editBill(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add bill')),
        ]),
        const SizedBox(height: 8),
        Card(child: Column(children: [
          if (allBills.isEmpty) const ListTile(title: Text('No bills yet')),
          for (final item in allBills)
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined,
                  color: AppTheme.brandBlue),
              title: Text(item['payee'].toString(),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(item['payment_date'].toString() +
                  ' • ' + (item['category']?.toString() ?? 'other')),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(dollars(item['payment_amount']),
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                if (synthetic) PopupMenuButton<String>(
                  onSelected: (action) {
                    if (action == 'edit') editBill(item);
                    if (action == 'delete') removeBill(item);
                  },
                  itemBuilder: (ctx) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ]),
            ),
        ])),
        const SizedBox(height: 14),
        const Text('7-day balance forecast', style: TextStyle(
            fontSize: 15, fontWeight: FontWeight.w800)),
        Card(child: Column(children: [
          for (final day in (d['timeline'] as List? ?? []))
            ListTile(dense: true,
              title: Text(day['event'].toString()),
              subtitle: Text(day['date'].toString()),
              trailing: Text(dollars(day['balance']),
                  style: const TextStyle(fontWeight: FontWeight.w700))),
        ])),
        if (transactions.isNotEmpty) ...[
          const SizedBox(height: 18),
          const Text('Recent simulated activity', style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.w800)),
          if (transactionWarning != null) Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(transactionWarning!, style: const TextStyle(
                fontSize: 12, color: AppTheme.textSecondary))),
          Card(child: Column(children: [
            for (final txn in transactions)
              ListTile(
                dense: true,
                title: Text(txn['merchant'].toString()),
                subtitle: Text(txn['date'].toString()),
                trailing: Text(
                  (txn['direction'] == 'credit' ? '+' : '−') +
                    dollars(txn['amount']),
                  style: TextStyle(fontWeight: FontWeight.w700,
                    color: txn['direction'] == 'credit'
                        ? AppTheme.brandBlue : AppTheme.brandNavy)),
              ),
          ])),
        ],
      ]),
    )));
  }

  Widget metric(String label, String value) => Card(
    child: Padding(padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(
            fontSize: 11, color: AppTheme.textSecondary)),
        const SizedBox(height: 5),
        Text(value, style: const TextStyle(fontSize: 21,
          fontWeight: FontWeight.w800, color: AppTheme.brandNavy)),
      ])));
}
