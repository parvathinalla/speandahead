import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';

/// Authenticated partner can review an in-app simulated proposal.
/// Does not move money or intercept external bank activity.
class PartnerInvitations extends StatefulWidget {
  const PartnerInvitations({super.key});

  @override
  State<PartnerInvitations> createState() => _PartnerInvitationsState();
}

class _PartnerInvitationsState extends State<PartnerInvitations> {
  List<dynamic> invitations = [];
  bool loading = true;
  String? error;
  bool deciding = false;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    if (mounted) setState(() { loading = true; error = null; });
    try {
      final data = await ApiService.getJointInvitations();
      if (mounted) setState(() {
        invitations = data['invitations'] as List? ?? [];
        loading = false;
      });
    } catch (exception) {
      if (mounted) setState(() {
        error = exception.toString();
        loading = false;
      });
    }
  }

  Future<void> decide(String proposalId, bool approve) async {
    if (deciding) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(approve ? 'Approve proposal?' : 'Decline proposal?'),
        content: const Text(
          'This confirms only a CreditPilot app-level simulation. '
          'No money is sent and no bank transaction is blocked.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => deciding = true);
    try {
      final response = await ApiService.decideJointProposal(
          proposalId: proposalId, approve: approve);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Proposal: ' + response['status'].toString())));
      await refresh();
    } catch (exception) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(exception.toString())));
    } finally {
      if (mounted) setState(() => deciding = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Expanded(child: Text('Partner approval inbox',
              style: TextStyle(fontSize: 15,
                fontWeight: FontWeight.w800, color: AppTheme.brandNavy))),
            IconButton(onPressed: deciding ? null : refresh,
              tooltip: 'Refresh invitations',
              icon: const Icon(Icons.refresh)),
          ]),
          const Text('Only proposals addressed to your verified Auth0 account appear here.',
            style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
          if (loading) const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator())),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(error!, style: const TextStyle(color: AppTheme.riskRed)),
          ],
          if (!loading && error == null && invitations.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text('No pending invitations.')),
          for (final item in invitations) ...[
            const Divider(),
            Text(item['merchant'].toString(), style: const TextStyle(
              fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Proposed amount: \$' + item['amount'].toString()),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: deciding ? null
                    : () => decide(item['proposal_id'].toString(), false),
                child: const Text('Decline'),
              )),
              const SizedBox(width: 8),
              Expanded(child: FilledButton(
                onPressed: deciding ? null
                    : () => decide(item['proposal_id'].toString(), true),
                child: const Text('Approve'),
              )),
            ]),
          ],
        ],
      ),
    ),
  );
}
