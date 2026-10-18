import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';

/// Authenticated personal finance chat. Gemini never receives client-supplied
/// balances: the API reads verified Nessie/sandbox accounts for each message.
class CreditPilotChatScreen extends StatefulWidget {
  const CreditPilotChatScreen({super.key});

  @override
  State<CreditPilotChatScreen> createState() => _CreditPilotChatScreenState();
}

class _CreditPilotChatScreenState extends State<CreditPilotChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<Map<String, String>> _messages = [];
  bool _busy = false;
  bool _loading = true;
  bool _memoryOn = false;
  String? _error;
  String _bankSource = 'banking sandbox';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await ApiService.agentSettings();
      final enabled = settings['memory_enabled'] == true;
      final history = enabled ? await ApiService.agentHistory() : null;
      final entries = (history?['history'] as List? ?? [])
          .whereType<Map>()
          .map((x) => <String, String>{
            'role': x['role']?.toString() ?? 'assistant',
            'content': x['content']?.toString() ?? '',
          }).toList();
      if (!mounted) return;
      setState(() {
        _memoryOn = enabled;
        _bankSource = settings['source_of_banking_balances']
                ?.toString().replaceAll('_', ' ') ?? 'banking sandbox';
        _messages.addAll(entries);
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _scrollBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(_scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut);
  }

  Future<void> _send([String? suggested]) async {
    final question = (suggested ?? _input.text).trim();
    if (_busy || question.length < 2 || question.length > 1300) return;
    _input.clear();
    setState(() {
      _error = null;
      _busy = true;
      _messages.add({'role': 'user', 'content': question});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollBottom());
    try {
      final response = await ApiService.agentChat(question);
      if (!mounted) return;
      setState(() {
        _bankSource = response['bank_data_source']
            ?.toString().replaceAll('_', ' ') ?? _bankSource;
        _messages.add({
          'role': 'assistant',
          'content': response['response']?.toString()
              ?? 'The advisor did not return an answer.',
        });
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollBottom());
      }
    }
  }

  Future<void> _setMemory(bool value) async {
    if (_busy) return;
    try {
      final result = await ApiService.agentConsent(value);
      if (!mounted) return;
      setState(() => _memoryOn = result['memory_enabled'] == true);
      if (!value && mounted) {
        // Clear displayed history so the interface matches server deletion.
        setState(() => _messages.clear());
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Saved preferences and conversation history deleted.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _savePreference() async {
    if (!_memoryOn) return;
    final controller = TextEditingController();
    try {
      final note = await showDialog<String>(context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Save a preference'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Example: Keep at least \$500 in checking, or prefer '
              'cash-back rewards over travel points.'),
            TextField(controller: controller, maxLength: 350,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'What should CreditPilot remember?')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel')),
            FilledButton(onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
                child: const Text('Save')),
          ],
        ));
      if (note == null || note.length < 3) return;
      await ApiService.rememberPreference(note);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Preference saved to your private memory.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())));
    } finally {
      controller.dispose();
    }
  }

  Future<void> _manageMemories() async {
    if (!_memoryOn) return;
    try {
      final result = await ApiService.agentMemories();
      if (!mounted) return;
      final memories = (result['memories'] as List? ?? [])
          .whereType<Map>().toList();
      await showDialog<void>(context: context,
        builder: (dialogContext) => StatefulBuilder(builder: (context, update) =>
          AlertDialog(
            title: const Text('My saved preferences'),
            content: SizedBox(width: 410, child: memories.isEmpty
              ? const Text('No preferences saved yet.')
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 350),
                  child: ListView(shrinkWrap: true, children: [
                    for (final note in memories)
                      ListTile(
                        title: Text(note['note']?.toString() ?? ''),
                        trailing: IconButton(
                          tooltip: 'Delete preference',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            try {
                              await ApiService.deletePreference(
                                note['id'].toString());
                              update(() => memories.remove(note));
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(e.toString())));
                              }
                            }
                          },
                        ),
                      ),
                  ]),
                )),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close')),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _clearMemories() async {
    final confirm = await showDialog<bool>(context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete my AI memory?'),
        content: const Text('Delete all saved preferences and prior AI chats? '
            'Your fictional banking accounts and bills will remain unchanged.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete memory')),
        ],
      ));
    if (confirm != true) return;
    try {
      await ApiService.clearAgentMemory();
      if (mounted) setState(() => _messages.clear());
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _privacySettings() async {
    await showModalBottomSheet<void>(context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, redraw) =>
        SafeArea(child: Padding(padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('AI memory & privacy', style:
                TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text('Gemini processes your question and a limited snapshot '
                'of your own sandbox banking context. Memory is optional. '
                'Only an opt-in stores chat history and preferences.'),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Remember my preferences & conversations'),
                subtitle: const Text('Switching off deletes saved AI memory.'),
                value: _memoryOn,
                onChanged: (next) async {
                  await _setMemory(next);
                  if (ctx.mounted) redraw(() {});
                },
              ),
              OutlinedButton.icon(
                onPressed: _memoryOn ? () async {
                  Navigator.pop(ctx); await _savePreference();
                } : null,
                icon: const Icon(Icons.bookmark_add_outlined),
                label: const Text('Save new preference'),
              ),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: _memoryOn ? () async {
                  Navigator.pop(ctx); await _manageMemories();
                } : null,
                icon: const Icon(Icons.manage_accounts_outlined),
                label: const Text('View or delete preferences'),
              ),
              const SizedBox(height: 6),
              TextButton.icon(
                onPressed: _memoryOn ? () async {
                  Navigator.pop(ctx); await _clearMemories();
                } : null,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete all AI memory and chat history'),
              ),
            ]),
        )),
      ),
    );
  }

  Widget _bubble(Map<String, String> item) {
    final isUser = item['role'] == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 7),
        padding: const EdgeInsets.all(14),
        constraints: const BoxConstraints(maxWidth: 620),
        decoration: BoxDecoration(
          color: isUser ? AppTheme.brandBlue : const Color(0xFFF0F4FA),
          borderRadius: BorderRadius.circular(17),
        ),
        child: SelectableText(item['content'] ?? '',
          style: TextStyle(height: 1.5,
            color: isUser ? Colors.white : AppTheme.brandNavy)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ask CreditPilot'),
        actions: [
          IconButton(
            onPressed: _privacySettings,
            tooltip: 'AI memory and privacy',
            icon: Icon(_memoryOn ? Icons.bookmarks : Icons.settings_outlined),
          ),
        ],
      ),
      body: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          width: double.infinity,
          color: AppTheme.brandBlueLight,
          child: Text('Simulation only • $_bankSource • No real transfers',
            style: const TextStyle(fontSize: 11,
              color: AppTheme.brandNavy)),
        ),
        Expanded(child: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(controller: _scroll,
            padding: const EdgeInsets.all(16),
            children: [
              if (_messages.isEmpty) ...[
                const SizedBox(height: 25),
                const Icon(Icons.auto_awesome, size: 48,
                  color: AppTheme.brandBlue),
                const SizedBox(height: 14),
                const Center(child: Text('Your financial thinking partner',
                  style: TextStyle(fontSize: 18,
                    fontWeight: FontWeight.w800))),
                const SizedBox(height: 8),
                const Center(child: Text(
                  'Uses your sandbox accounts and optional saved preferences.',
                  textAlign: TextAlign.center)),
                const SizedBox(height: 22),
                for (final idea in [
                  'Can I afford a \$900 laptop next month?',
                  'Which of my credit cards is better for groceries?',
                  'Help me plan my bills and protect \$500 in savings.',
                ])
                  Padding(padding: const EdgeInsets.only(bottom: 8),
                    child: OutlinedButton(
                      onPressed: () => _send(idea),
                      child: Text(idea))),
              ],
              for (final item in _messages) _bubble(item),
              if (_busy) const Padding(
                padding: EdgeInsets.all(12),
                child: Row(children: [
                  SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 12),
                  Text('Analyzing your financial scenario...'),
                ])),
              if (_error != null) Padding(padding: const EdgeInsets.all(8),
                child: Text(_error!, style: const TextStyle(
                  color: AppTheme.riskRed))),
            ],
          ),
        ),
        SafeArea(top: false,
          child: Padding(padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(child: TextField(
                controller: _input,
                enabled: !_busy && !_loading,
                minLines: 1, maxLines: 3, maxLength: 1300,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: const InputDecoration(
                  hintText: 'Ask about spending, bills or goals...',
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
              )),
              const SizedBox(width: 10),
              IconButton.filled(
                tooltip: 'Send message',
                onPressed: _busy || _loading ? null : () => _send(),
                icon: const Icon(Icons.send_rounded),
              ),
            ]),
          )),
      ]),
    );
  }
}
