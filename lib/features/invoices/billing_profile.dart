import 'billing_fields.dart';
import 'package:vortice_app/core/unsaved_form_guard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/membership/membership_provider.dart';
import 'package:vortice_app/sync/online_action_gate.dart';
import 'canadian_invoice.dart';

class BillingProfileRepository {
  Future<Map<String, dynamic>> load() async => Map<String, dynamic>.from(
    await supabase.rpc('organization_billing_profile') as Map,
  );
  Future<void> save(String organizationId, Map<String, dynamic> details) async {
    await supabase.rpc(
      'save_organization_billing_profile',
      params: {'p_organization': organizationId, 'p_details': details},
    );
  }
}

final billingProfileRepositoryProvider = Provider(
  (ref) => BillingProfileRepository(),
);
final billingProfileProvider = FutureProvider<Map<String, dynamic>>((
  ref,
) async {
  ref.watch(sessionProvider);
  await ref.watch(organizationContextProvider.future);
  return ref.watch(billingProfileRepositoryProvider).load();
});

class BillingProfileScreen extends ConsumerStatefulWidget {
  const BillingProfileScreen({
    super.key,
    required this.details,
    required this.organizationId,
  });
  final Map<String, dynamic> details;
  final String organizationId;
  @override
  ConsumerState<BillingProfileScreen> createState() =>
      _BillingProfileScreenState();
}

class _BillingProfileScreenState extends ConsumerState<BillingProfileScreen> {
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _fields = {
    for (final k in ['legal_name', 'address', 'contact', 'tax_registration'])
      k: TextEditingController(text: widget.details[k]?.toString() ?? ''),
  };
  late String? _registration = widget.details['registration_status'] as String?;
  bool _busy = false, _saved = false;
  bool get _dirty =>
      !_saved &&
      (_registration != widget.details['registration_status'] ||
          _fields.entries.any(
            (e) => e.value.text != (widget.details[e.key]?.toString() ?? ''),
          ));
  String t(String en, String es, String fr) => billingText(context, en, es, fr);
  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate() ||
        !await requireOnlineAction(context, ref) ||
        !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(billingProfileRepositoryProvider)
          .save(widget.organizationId, {
            for (final e in _fields.entries) e.key: e.value.text.trim(),
            'registration_status': _registration,
          });
      ref.invalidate(billingProfileProvider);
      if (mounted) {
        setState(() {
          _saved = true;
          _busy = false;
        });
        await WidgetsBinding.instance.endOfFrame;
        if (mounted) Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(context, e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => UnsavedFormGuard(
    isDirty: () => _dirty,
    controllers: _fields.values.toList(),
    busy: _busy,
    fallbackRoute: '/more',
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          t(
            'Company invoice details',
            'Datos de facturación',
            'Coordonnées de facturation',
          ),
        ),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              t(
                'These details identify your company on new invoices. Issued invoices keep their saved details.',
                'Estos datos identifican a tu empresa en nuevas facturas. Las facturas emitidas conservan sus datos.',
                'Ces coordonnées identifient votre entreprise sur les nouvelles factures. Les factures émises conservent leurs coordonnées enregistrées.',
              ),
            ),
            for (final f in [
              (
                'legal_name',
                t(
                  'Legal or trading name',
                  'Nombre legal o comercial',
                  'Dénomination sociale ou nom commercial',
                ),
              ),
              (
                'address',
                t(
                  'Business address',
                  'Dirección comercial',
                  'Adresse de l’entreprise',
                ),
              ),
              (
                'contact',
                t(
                  'Billing email or phone',
                  'Correo o teléfono de facturación',
                  'Courriel ou téléphone de facturation',
                ),
              ),
            ])
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: BillingTextField(
                  controller: _fields[f.$1],
                  enabled: !_busy,
                  maxLines: f.$1 == 'address' ? 3 : 1,
                  maxLength: 1000,
                  decoration: InputDecoration(labelText: f.$2),
                  validator: (v) => v!.trim().isEmpty
                      ? t('Required', 'Obligatorio', 'Obligatoire')
                      : null,
                ),
              ),
            const SizedBox(height: 16),
            BillingDropdown(
              initialValue: _registration,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: t(
                  'Tax registration',
                  'Registro fiscal',
                  'Inscription fiscale',
                ),
              ),
              items: [
                DropdownMenuItem(
                  value: 'registered',
                  child: Text(t('Registered', 'Registrado', 'Inscrit')),
                ),
                DropdownMenuItem(
                  value: 'not_registered',
                  child: Text(
                    t('Not registered', 'No registrado', 'Non inscrit'),
                  ),
                ),
              ],
              onChanged: _busy
                  ? null
                  : (v) => setState(() => _registration = v),
              validator: (v) => v == null
                  ? t(
                      'Choose registration status',
                      'Elige el estado de registro',
                      'Choisissez le statut d’inscription',
                    )
                  : null,
            ),
            const SizedBox(height: 16),
            BillingTextField(
              controller: _fields['tax_registration'],
              enabled: !_busy,
              maxLines: 3,
              maxLength: 1000,
              decoration: InputDecoration(
                labelText: t(
                  'Tax registration numbers',
                  'Números de registro fiscal',
                  'Numéros d’inscription fiscale',
                ),
                helperText: t(
                  'Include each applicable tax name and registration number.',
                  'Incluye cada impuesto aplicable y su número de registro.',
                  'Indiquez chaque taxe applicable et son numéro d’inscription.',
                ),
              ),
              validator: (v) =>
                  _registration == 'registered' && v!.trim().isEmpty
                  ? t(
                      'Required when registered',
                      'Obligatorio para registrados',
                      'Obligatoire si inscrit',
                    )
                  : null,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(
                _busy
                    ? t('Saving…', 'Guardando…', 'Enregistrement…')
                    : t(
                        'Save company details',
                        'Guardar datos',
                        'Enregistrer les coordonnées',
                      ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
