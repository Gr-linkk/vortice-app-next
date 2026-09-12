/// Stored readings retain their original unit. Conversion is for display only.
const meterUnits = ['hours', 'km', 'mi'];

String meterSymbol(String? unit) => switch (unit) {
  'km' => 'km',
  'mi' => 'mi',
  _ => 'h',
};

String meterName(String? unit, bool es) => switch (unit) {
  'km' => es ? 'Kilómetros' : 'Kilometres',
  'mi' => es ? 'Millas' : 'Miles',
  _ => es ? 'Horas' : 'Hours',
};

String formatMeter(num? value, String? unit) => value == null
    ? '— ${meterSymbol(unit)}'
    : '${value == value.roundToDouble() ? value.toInt() : value.toStringAsFixed(1)} ${meterSymbol(unit)}';

double convertDistance(num value, String from, String to) {
  if (!value.isFinite ||
      !['km', 'mi'].contains(from) ||
      !['km', 'mi'].contains(to)) {
    throw ArgumentError('Only finite distance readings can be converted.');
  }
  return from == to
      ? value.toDouble()
      : from == 'mi'
      ? value * 1.609344
      : value / 1.609344;
}
