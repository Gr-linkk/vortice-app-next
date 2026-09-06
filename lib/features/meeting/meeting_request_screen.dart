import 'package:vortice_app/core/app_dropdown_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/meeting/meeting_provider.dart';

class MeetingRequestScreen extends ConsumerStatefulWidget {
  const MeetingRequestScreen({super.key});

  @override
  ConsumerState<MeetingRequestScreen> createState() =>
      _MeetingRequestScreenState();
}

class _MeetingRequestScreenState extends ConsumerState<MeetingRequestScreen> {
  final _formKey = GlobalKey<FormState>();

  String? _interest;
  String? _vesselCount;
  String? _contactMethod;
  final _notesCtrl = TextEditingController();

  static const _interestOptions = [
    'Routine Maintenance',
    'Repair',
    'Fleet Management',
    'Telemetry & Monitoring',
    'Other',
  ];

  static const _vesselCountOptions = ['1', '2-5', '5+'];

  static const _contactOptions = ['WhatsApp', 'Email', 'Phone'];

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final success = await ref
        .read(meetingRequestControllerProvider.notifier)
        .submitRequest(
          interest: _interest,
          vesselCount: _vesselCount,
          contactMethod: _contactMethod,
          notes: _notesCtrl.text.trim(),
        );

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Request sent! We'll be in touch within 24 hours."),
          backgroundColor: AppColors.success,
        ),
      );
      context.pop();
    } else if (mounted) {
      final err =
          ref.read(meetingRequestControllerProvider).error?.toString() ??
          'Unknown error';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), backgroundColor: AppColors.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(meetingRequestControllerProvider).isLoading;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Request Consultation'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  "Tell us a bit about what you're looking for and we'll reach out to set up a consultation.",
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 24),

                // What are you looking for?
                AppDropdownField<String>(
                  initialValue: _interest,
                  decoration: const InputDecoration(
                    labelText: 'What are you looking for?',
                    prefixIcon: Icon(Icons.build_outlined),
                  ),
                  dropdownColor: AppColors.surfaceVariant,
                  items: _interestOptions
                      .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                      .toList(),
                  onChanged: (v) => setState(() => _interest = v),
                  validator: (v) =>
                      v == null ? 'Please select an option' : null,
                ),
                const SizedBox(height: 16),

                // How many vessels?
                AppDropdownField<String>(
                  initialValue: _vesselCount,
                  decoration: const InputDecoration(
                    labelText: 'How many vessels?',
                    prefixIcon: Icon(Icons.directions_boat_outlined),
                  ),
                  dropdownColor: AppColors.surfaceVariant,
                  items: _vesselCountOptions
                      .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                      .toList(),
                  onChanged: (v) => setState(() => _vesselCount = v),
                  validator: (v) =>
                      v == null ? 'Please select an option' : null,
                ),
                const SizedBox(height: 16),

                // Preferred contact method
                AppDropdownField<String>(
                  initialValue: _contactMethod,
                  decoration: const InputDecoration(
                    labelText: 'Preferred contact method',
                    prefixIcon: Icon(Icons.contact_phone_outlined),
                  ),
                  dropdownColor: AppColors.surfaceVariant,
                  items: _contactOptions
                      .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                      .toList(),
                  onChanged: (v) => setState(() => _contactMethod = v),
                  validator: (v) =>
                      v == null ? 'Please select an option' : null,
                ),
                const SizedBox(height: 16),

                // Notes (optional)
                TextFormField(
                  controller: _notesCtrl,
                  maxLines: 4,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Anything else we should know? (optional)',
                    alignLabelWithHint: true,
                    prefixIcon: Padding(
                      padding: EdgeInsets.only(bottom: 60),
                      child: Icon(Icons.notes_outlined),
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                ElevatedButton(
                  onPressed: isLoading ? null : _submit,
                  child: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Request Consultation'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
