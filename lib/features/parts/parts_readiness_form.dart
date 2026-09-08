part of 'parts_readiness_screen.dart';

class PartInput {
  const PartInput(
    this.keyName,
    this.label, {
    this.value = '',
    this.number = false,
    this.required = true,
    this.date = false,
  });
  final String keyName, label, value;
  final bool number, required, date;
}

class _PartsForm extends StatefulWidget {
  const _PartsForm({
    required this.title,
    required this.fields,
    required this.es,
  });
  final String title;
  final List<PartInput> fields;
  final bool es;
  @override
  State<_PartsForm> createState() => _PartsFormState();
}

class _PartsFormState extends State<_PartsForm> {
  final _key = GlobalKey<FormState>();
  late final _controllers = {
    for (final field in widget.fields)
      field.keyName: TextEditingController(text: field.value),
  };
  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 420,
      child: Form(
        key: _key,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final field in widget.fields)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: TextFormField(
                    controller: _controllers[field.keyName],
                    decoration: InputDecoration(labelText: field.label),
                    keyboardType: field.number
                        ? const TextInputType.numberWithOptions(decimal: true)
                        : TextInputType.text,
                    maxLength: field.number ? 12 : 300,
                    validator: (value) {
                      final text = value?.trim() ?? '';
                      if (text.isEmpty) {
                        return field.required
                            ? (widget.es ? 'Campo obligatorio' : 'Required')
                            : null;
                      }
                      if (field.number) {
                        final number = double.tryParse(text);
                        if (number == null ||
                            !number.isFinite ||
                            number < 0 ||
                            number >= 1000000 ||
                            !RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(text)) {
                          return widget.es
                              ? 'Usa un número positivo con hasta dos decimales'
                              : 'Use a nonnegative number with up to two decimals';
                        }
                      }
                      if (field.date) {
                        final date = DateTime.tryParse(text);
                        if (date == null ||
                            date.toIso8601String().substring(0, 10) != text) {
                          return widget.es
                              ? 'Usa AAAA-MM-DD'
                              : 'Use YYYY-MM-DD';
                        }
                      }
                      return null;
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(widget.es ? 'Cancelar' : 'Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!_key.currentState!.validate()) return;
          Navigator.pop(context, <String, dynamic>{
            for (final f in widget.fields)
              f.keyName: f.number
                  ? double.parse(_controllers[f.keyName]!.text.trim())
                  : _controllers[f.keyName]!.text.trim(),
          });
        },
        child: Text(widget.es ? 'Guardar' : 'Save'),
      ),
    ],
  );
}
