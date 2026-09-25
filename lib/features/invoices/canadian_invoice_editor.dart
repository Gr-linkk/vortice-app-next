import 'billing_fields.dart';
import 'package:vortice_app/core/unsaved_form_guard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/features/membership/organization_work_provider.dart';
import 'package:vortice_app/models/invoice.dart';
import 'package:vortice_app/sync/online_action_gate.dart';
import 'billing_profile.dart';
import 'canadian_invoice.dart';

String normalizeBillingNumber(String value) =>
    value.trim().replaceAll(',', '.');

// Match PostgreSQL's cent rounding without binary floating-point half-cent loss.
double canadianSubtotal(double hours, String rate, String parts) {
  int cents(String text) {
    final v = normalizeBillingNumber(text);
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(v)) return 0;
    final pair = v.split('.');
    return int.parse(pair[0]) * 100 +
        (pair.length == 1 ? 0 : int.parse(pair[1].padRight(2, '0')));
  }

  return (((hours * 100).round() * cents(rate) + 50) ~/ 100 + cents(parts)) /
      100;
}

class CanadianInvoiceEditor extends ConsumerStatefulWidget {
  const CanadianInvoiceEditor({
    super.key,
    required this.workOrderId,
    required this.customerName,
    required this.description,
    required this.hours,
    this.invoice,
  });
  final String workOrderId, customerName, description;
  final double hours;
  final Invoice? invoice;
  @override
  ConsumerState<CanadianInvoiceEditor> createState() =>
      _CanadianInvoiceEditorState();
}

class _TaxFields {
  _TaxFields([Map? data])
    : name = TextEditingController(text: data?['name']?.toString() ?? ''),
      rate = TextEditingController(text: data?['rate']?.toString() ?? ''),
      base = TextEditingController(text: data?['base']?.toString() ?? '');
  final TextEditingController name, rate, base;
  void dispose() {
    name.dispose();
    rate.dispose();
    base.dispose();
  }

  Map<String, dynamic> get data => {
    'name': name.text.trim(),
    'rate': normalizeBillingNumber(rate.text),
    'base': normalizeBillingNumber(base.text),
  };
}

class _CanadianInvoiceEditorState extends ConsumerState<CanadianInvoiceEditor> {
  final _form = GlobalKey<FormState>();
  final Map<String, TextEditingController> _fields = {};
  final List<_TaxFields> _taxes = [];
  String? _province, _treatment;
  bool _reviewed = false, _busy = false, _dirty = false, _saved = false;
  void _changed() {
    if (mounted) {
      setState(() {
        _dirty = true;
        _reviewed = false;
      });
    }
  }

  String t(String en, String es, String fr) => billingText(context, en, es, fr);
  @override
  void initState() {
    super.initState();
    final d = widget.invoice?.cadDetails ?? {};
    final defaults = {
      'customer_name': widget.customerName,
      'supply_description': widget.description,
      'parts_total': '0',
      'issue_date': DateTime.now().toIso8601String().split('T').first,
    };
    for (final key in [
      'customer_name',
      'customer_address',
      'supply_description',
      'labour_rate',
      'parts_total',
      'tax_review_note',
      'issue_date',
      'due_date',
      'payment_terms',
    ]) {
      _fields[key] = TextEditingController(
        text: (d[key] ?? defaults[key] ?? '').toString(),
      );
    }
    _province = d['supply_province'] as String?;
    _treatment = d['tax_treatment'] as String?;
    for (final c in _fields.values) {
      c.addListener(_changed);
    }
    _taxes.addAll((d['taxes'] as List? ?? []).map((e) => _TaxFields(e as Map)));
    for (final tax in _taxes) {
      _watchTax(tax);
    }
  }

  void _watchTax(_TaxFields tax) {
    for (final c in [tax.name, tax.rate, tax.base]) {
      c.addListener(_changed);
    }
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    for (final tax in _taxes) {
      tax.dispose();
    }
    super.dispose();
  }

  double get _subtotal => canadianSubtotal(
    widget.hours,
    _fields['labour_rate']!.text,
    _fields['parts_total']!.text,
  );
  String? _required(String? v) => v == null || v.trim().isEmpty
      ? t('Required', 'Obligatorio', 'Obligatoire')
      : null;
  String? _number(String? v, {double? max, bool rate = false}) {
    final normalized = normalizeBillingNumber(v ?? '');
    final n = double.tryParse(normalized);
    if (n == null ||
        !n.isFinite ||
        n < 0 ||
        (rate && n <= 0) ||
        (max != null && n > max)) {
      return t(
        'Enter a valid amount',
        'Introduce un importe válido',
        'Entrez un montant valide',
      );
    }
    if (!RegExp(
      rate ? r'^\d+(\.\d{1,4})?$' : r'^\d+(\.\d{1,2})?$',
    ).hasMatch(normalized)) {
      return t(
        'Check decimal places',
        'Revisa los decimales',
        'Vérifiez les décimales',
      );
    }
    return null;
  }

  Widget _field(
    String key,
    String label, {
    bool number = false,
    int lines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: BillingTextField(
      key: ValueKey(key),
      controller: _fields[key],
      enabled: !_busy,
      maxLines: lines,
      maxLength: number ? null : 2000,
      decoration: InputDecoration(labelText: label),
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      onChanged: number
          ? (_) => setState(() => _reviewed = false)
          : (_) {
              _reviewed = false;
            },
      validator: (v) {
        if (number) {
          return _number(v, max: key == 'labour_rate' ? 999999.99 : 9999999.99);
        }
        if (key.endsWith('_date')) {
          final date = DateTime.tryParse(v ?? '');
          if (date == null || date.toIso8601String().split('T').first != v) {
            return t('Use YYYY-MM-DD', 'Usa AAAA-MM-DD', 'Utilisez AAAA-MM-JJ');
          }
          if (key == 'due_date') {
            final issued = DateTime.tryParse(_fields['issue_date']!.text);
            if (issued != null && date.isBefore(issued)) {
              return t(
                'Due date must follow invoice date',
                'El vencimiento debe seguir la fecha de factura',
                'L’échéance doit suivre la date de facturation',
              );
            }
          }
        }
        return _required(v);
      },
    ),
  );
  Future<void> _editProfile(
    String organizationId,
    Map<String, dynamic> details,
  ) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => BillingProfileScreen(
          details: details,
          organizationId: organizationId,
        ),
      ),
    );
    if (mounted) {
      ref.invalidate(billingProfileProvider);
      setState(() => _reviewed = false);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate() || !_reviewed) return;
    if (!await requireOnlineAction(context, ref) || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(organizationWorkRepositoryProvider).invoice(
        widget.workOrderId,
        widget.invoice == null ? 'generate_cad' : 'revise_cad',
        {
          for (final e in _fields.entries)
            e.key: const ['labour_rate', 'parts_total'].contains(e.key)
                ? normalizeBillingNumber(e.value.text)
                : e.value.text.trim(),
          'supply_province': _province,
          'tax_treatment': _treatment,
          'taxes': _treatment == 'taxable'
              ? _taxes.map((e) => e.data).toList()
              : [],
        },
      );
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
    isDirty: () => _dirty && !_saved,
    controllers: _fields.values.toList(),
    fallbackRoute: '/work',
    busy: _busy,
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          t(
            'Customer invoice · CAD',
            'Factura al cliente · CAD',
            'Facture client · CAD',
          ),
        ),
      ),
      body: ref
          .watch(billingProfileProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => AppErrorState(
              error: e,
              onRetry: () => ref.invalidate(billingProfileProvider),
            ),
            data: (profile) {
              final issuer = Map<String, dynamic>.from(
                profile['details'] as Map? ?? {},
              );
              if (issuer.isEmpty) {
                return ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      t(
                        'Set up your company’s invoice details before creating a customer invoice.',
                        'Configura los datos de tu empresa antes de crear una factura.',
                        'Configurez les coordonnées de facturation de votre entreprise avant de créer une facture.',
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (profile['can_manage'] == true)
                      FilledButton(
                        onPressed: () => _editProfile(
                          profile['organization_id'] as String,
                          {},
                        ),
                        child: Text(
                          t(
                            'Set up company details',
                            'Configurar empresa',
                            'Configurer les coordonnées',
                          ),
                        ),
                      )
                    else
                      Text(
                        t(
                          'Ask a Company Owner to complete the invoice profile.',
                          'Pide al propietario completar los datos.',
                          'Demandez au propriétaire de l’entreprise de remplir les coordonnées.',
                        ),
                      ),
                  ],
                );
              }
              return Form(
                key: _form,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      '${issuer['legal_name']}\n${issuer['address']}\n${issuer['tax_registration'] ?? ''}',
                    ),
                    if (profile['can_manage'] == true)
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _editProfile(
                                profile['organization_id'] as String,
                                issuer,
                              ),
                        child: Text(
                          t(
                            'Edit company details',
                            'Editar datos de empresa',
                            'Modifier les coordonnées',
                          ),
                        ),
                      ),
                    Text(
                      t(
                        'Enter customer charges in Canadian dollars. Review the place of supply and every tax line; rates are not chosen automatically.',
                        'Introduce cargos en dólares canadienses. Revisa el lugar del suministro y cada impuesto; no se eligen tasas automáticamente.',
                        'Entrez les montants en dollars canadiens. Vérifiez le lieu de fourniture et chaque taxe; aucun taux n’est choisi automatiquement.',
                      ),
                    ),
                    _field(
                      'customer_name',
                      t(
                        'Customer legal or trading name',
                        'Nombre legal o comercial del cliente',
                        'Dénomination sociale ou nom commercial du client',
                      ),
                    ),
                    _field(
                      'customer_address',
                      t(
                        'Customer address',
                        'Dirección del cliente',
                        'Adresse du client',
                      ),
                      lines: 2,
                    ),
                    _field(
                      'supply_description',
                      t(
                        'Work supplied',
                        'Trabajo realizado',
                        'Travaux fournis',
                      ),
                      lines: 3,
                    ),
                    Text(
                      t(
                        'Approved labour: ${widget.hours} hours',
                        'Trabajo aprobado: ${widget.hours} horas',
                        'Main-d’œuvre approuvée : ${widget.hours} heures',
                      ),
                    ),
                    _field(
                      'labour_rate',
                      t(
                        'Labour rate (CAD/hour)',
                        'Tarifa (CAD/hora)',
                        'Taux horaire (CAD/heure)',
                      ),
                      number: true,
                    ),
                    _field(
                      'parts_total',
                      t(
                        'Customer parts charge (CAD)',
                        'Cargo de piezas (CAD)',
                        'Pièces facturées (CAD)',
                      ),
                      number: true,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '${t('Subtotal', 'Subtotal', 'Sous-total')}: ${_subtotal.toStringAsFixed(2)} CAD',
                    ),
                    const SizedBox(height: 16),
                    BillingDropdown(
                      key: const ValueKey('supply_province'),
                      initialValue: _province,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: t(
                          'Province or territory of supply',
                          'Provincia del suministro',
                          'Province ou territoire de fourniture',
                        ),
                      ),
                      items: [
                        for (final p in [
                          'AB',
                          'BC',
                          'MB',
                          'NB',
                          'NL',
                          'NS',
                          'NT',
                          'NU',
                          'ON',
                          'PE',
                          'QC',
                          'SK',
                          'YT',
                        ])
                          DropdownMenuItem(value: p, child: Text(p)),
                      ],
                      onChanged: _busy
                          ? null
                          : (v) => setState(() {
                              _province = v;
                              _dirty = true;
                              _reviewed = false;
                            }),
                      validator: _required,
                    ),
                    const SizedBox(height: 16),
                    BillingDropdown(
                      key: const ValueKey('tax_treatment'),
                      initialValue: _treatment,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: t(
                          'Reviewed tax treatment',
                          'Tratamiento fiscal revisado',
                          'Traitement fiscal vérifié',
                        ),
                      ),
                      items: [
                        for (final entry in [
                          ('taxable', t('Taxable', 'Gravado', 'Taxable')),
                          (
                            'zero_rated',
                            t('Zero-rated', 'Tasa cero', 'Détaxé'),
                          ),
                          ('exempt', t('Exempt', 'Exento', 'Exonéré')),
                          (
                            'not_registered',
                            t('Not registered', 'No registrado', 'Non inscrit'),
                          ),
                        ])
                          DropdownMenuItem(
                            value: entry.$1,
                            child: Text(entry.$2),
                          ),
                      ],
                      onChanged: _busy
                          ? null
                          : (v) => setState(() {
                              _treatment = v;
                              _dirty = true;
                              _reviewed = false;
                              if (v == 'taxable' && _taxes.isEmpty) {
                                final tax = _TaxFields();
                                _watchTax(tax);
                                _taxes.add(tax);
                                _dirty = true;
                              }
                            }),
                      validator: _required,
                    ),
                    if (_treatment == 'taxable') ...[
                      for (final tax in _taxes)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              children: [
                                BillingTextField(
                                  controller: tax.name,
                                  enabled: !_busy,
                                  decoration: InputDecoration(
                                    labelText: t(
                                      'Tax name (GST, HST, PST, QST…)',
                                      'Nombre del impuesto',
                                      'Nom de la taxe (TPS, TVH, TVP, TVQ…)',
                                    ),
                                  ),
                                  validator: _required,
                                ),
                                const SizedBox(height: 12),
                                BillingTextField(
                                  controller: tax.rate,
                                  enabled: !_busy,
                                  decoration: InputDecoration(
                                    labelText: t(
                                      'Reviewed rate (%)',
                                      'Tasa revisada (%)',
                                      'Taux vérifié (%)',
                                    ),
                                  ),
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  validator: (v) =>
                                      _number(v, max: 100, rate: true),
                                ),
                                const SizedBox(height: 12),
                                BillingTextField(
                                  controller: tax.base,
                                  enabled: !_busy,
                                  decoration: InputDecoration(
                                    labelText: t(
                                      'Taxable base (CAD)',
                                      'Base gravable (CAD)',
                                      'Assiette taxable (CAD)',
                                    ),
                                  ),
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  validator: (v) => _number(
                                    v,
                                    max: double.parse(
                                      _subtotal.toStringAsFixed(2),
                                    ),
                                  ),
                                ),
                                if (_taxes.length > 1)
                                  TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () => setState(() {
                                            _taxes.remove(tax);
                                            WidgetsBinding.instance
                                                .addPostFrameCallback(
                                                  (_) => tax.dispose(),
                                                );
                                            _dirty = true;
                                            _reviewed = false;
                                          }),
                                    child: Text(
                                      t(
                                        'Remove tax line',
                                        'Quitar impuesto',
                                        'Retirer la taxe',
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      if (_taxes.length < 4)
                        OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                  final tax = _TaxFields();
                                  _watchTax(tax);
                                  _taxes.add(tax);
                                  _dirty = true;
                                  _reviewed = false;
                                }),
                          child: Text(
                            t(
                              'Add tax line',
                              'Agregar impuesto',
                              'Ajouter une taxe',
                            ),
                          ),
                        ),
                    ],
                    _field(
                      'tax_review_note',
                      t(
                        'Tax review notes / reason for zero tax',
                        'Revisión fiscal / motivo sin impuesto',
                        'Notes de vérification / motif sans taxe',
                      ),
                      lines: 3,
                    ),
                    _field(
                      'issue_date',
                      t(
                        'Invoice date (YYYY-MM-DD)',
                        'Fecha (AAAA-MM-DD)',
                        'Date de facturation (AAAA-MM-JJ)',
                      ),
                    ),
                    _field(
                      'due_date',
                      t(
                        'Due date (YYYY-MM-DD)',
                        'Vencimiento (AAAA-MM-DD)',
                        'Échéance (AAAA-MM-JJ)',
                      ),
                    ),
                    _field(
                      'payment_terms',
                      t(
                        'Payment terms',
                        'Condiciones de pago',
                        'Modalités de paiement',
                      ),
                      lines: 2,
                    ),
                    const SizedBox(height: 16),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _reviewed,
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _reviewed = v ?? false),
                      title: Text(
                        t(
                          'I reviewed the issuer, customer, supply location and tax treatment.',
                          'Revisé emisor, cliente, lugar del suministro e impuestos.',
                          'J’ai vérifié l’émetteur, le client, le lieu de fourniture et le traitement fiscal.',
                        ),
                      ),
                    ),
                    FilledButton(
                      onPressed: _busy || !_reviewed ? null : _save,
                      child: Text(
                        _busy
                            ? t('Saving…', 'Guardando…', 'Enregistrement…')
                            : t(
                                'Save invoice draft',
                                'Guardar borrador',
                                'Enregistrer le brouillon',
                              ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
    ),
  );
}
