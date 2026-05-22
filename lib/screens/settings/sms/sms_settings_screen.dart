import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../main.dart';
import '../../../db/app_database.dart';
import '../../../providers/db_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/sms_service.dart';

class SmsSettingsScreen extends ConsumerStatefulWidget {
  const SmsSettingsScreen({super.key});

  @override
  ConsumerState<SmsSettingsScreen> createState() => _SmsSettingsScreenState();
}

class _SmsSettingsScreenState extends ConsumerState<SmsSettingsScreen> {
  bool _smsDetectionEnabled = true;
  bool _autoConfirmHighConfidence = true;

  @override
  void initState() {
    super.initState();
    final uid = ref.read(currentUidProvider);
    _smsDetectionEnabled = globalPrefs.getBool('smsDetectionEnabled_$uid') ?? true;
    _autoConfirmHighConfidence = globalPrefs.getBool('autoConfirmHighConfidence_$uid') ?? true;
  }

  void _updateSettings(String key, bool value) async {
    final uid = ref.read(currentUidProvider);
    setState(() {
      if (key == 'detection') _smsDetectionEnabled = value;
      if (key == 'autoconfirm') _autoConfirmHighConfidence = value;
    });

    await globalPrefs.setBool('${key}Enabled_$uid', value);
  }

  // ── DEVELOPER SMS SIMULATOR UTILITY ────────────────────────────────
  void _triggerSimulatedSms(AppDatabase db, String uid) async {
    final smsService = SmsService(db);

    final mockBankSmsList = [
      {
        'sender': 'HDFCBK',
        'body': 'Alert: Rs 1200 debited from A/c XX1234 for Swiggy on 19-May-2026. Ref: UPI 67234912.',
        'display': '₹1,200 Swiggy order (HDFC Bank)'
      },
      {
        'sender': 'CANBNK',
        'body': 'Canara Bank: Amt Rs 4500 debited for Uber transaction towards airport transit on 19-May-2026.',
        'display': '₹4,500 Uber ride (Canara Bank)'
      },
      {
        'sender': 'ICICIB',
        'body': 'ICICI Bank: Credited Rs. 48000 on stipend payment payroll credit ref: NEFT 99124.',
        'display': '₹48,000 Stipend Payroll (ICICI Bank)'
      }
    ];

    if (!mounted) return;

    final selectedMock = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Simulate Bank SMS'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: mockBankSmsList.length,
            itemBuilder: (context, idx) {
              final item = mockBankSmsList[idx];
              return ListTile(
                leading: const Icon(Icons.sms_outlined),
                title: Text(item['display']!),
                onTap: () => Navigator.pop(context, item),
              );
            },
          ),
        ),
      ),
    );

    if (selectedMock != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Simulating bank SMS reception...'), duration: Duration(milliseconds: 600)),
      );

      await smsService.processSms(
        sender: selectedMock['sender']!,
        body: selectedMock['body']!,
        timestampMillis: DateTime.now().millisecondsSinceEpoch,
        uid: uid,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚡ SMS processed successfully. Simulated transaction logged: ${selectedMock['display']}.'),
            backgroundColor: const Color(0xFF1DB87A),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(appDatabaseProvider);
    final uid = ref.watch(currentUidProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('SMS Auto-Detect', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── CONFIGURATION PANEL ────────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Enable Auto-Detection'),
                    subtitle: const Text('Interceptors intercept incoming bank SMS logs in real-time'),
                    value: _smsDetectionEnabled,
                    onChanged: (val) => _updateSettings('detection', val),
                    activeColor: theme.primaryColor,
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: const Text('Auto-Confirm High Confidence'),
                    subtitle: const Text('Instantly log high-precision transactions without review'),
                    value: _autoConfirmHighConfidence,
                    onChanged: (val) => _updateSettings('autoconfirm', val),
                    activeColor: theme.primaryColor,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ── DEVELOPER ACTIONS (SIMULATION) ─────────────────────────
          Text('Sandbox Tools', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          
          Card(
            color: theme.primaryColor.withOpacity(0.06),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: theme.primaryColor.withOpacity(0.2)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'SMS Transaction Sandbox',
                    style: theme.textTheme.titleSmall?.copyWith(color: theme.primaryColor),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Simulate a real-time incoming SMS notification from Canara Bank, HDFC, or ICICI Bank to instantly test the matching, parsing, deduplication, and auto-insertion engine.',
                    style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => _triggerSimulatedSms(db, uid),
                    icon: const Icon(Icons.bolt, color: Colors.white),
                    label: const Text('Simulate Incoming Bank SMS'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
