import 'dart:convert';

import 'package:maintenance_local/maintenance_domain.dart';
import 'package:maintenance_local/model.dart';

Json procedureCopy(Json value) => jsonDecode(jsonEncode(value)) as Json;

List<Json> procedureItems(Json value) => (value['items'] as List)
    .map((item) => procedureCopy(Map<String, dynamic>.from(item as Map)))
    .toList();

/// Synthetic definitions distinguish absent, null, empty, and explicit zero.
List<Json> procedureFixtureItems() => [
  {
    'id': 'guard',
    'label': 'Inspect the synthetic guard',
    'input_type': 'check',
    'required': false,
    'allow_na': true,
  },
  {
    'id': 'lower-zero',
    'label': 'Synthetic pressure',
    'input_type': 'number',
    'unit': 'bar',
    'min': 0,
    'max': null,
    'required': true,
    'allow_na': false,
  },
  {
    'id': 'upper-zero',
    'label': 'Synthetic relative temperature',
    'input_type': 'number',
    'unit': null,
    'min': null,
    'max': 0,
  },
  {
    'id': 'unbounded',
    'label': 'Synthetic unrestricted reading',
    'input_type': 'number',
  },
  {
    'id': 'condition',
    'label': 'Describe the synthetic condition',
    'input_type': 'text',
    'unit': '',
    'required': false,
  },
];

Json procedurePublicationFixture({String id = 'source-publication'}) =>
    makeTemplate(
      id: id,
      title: 'Synthetic inspection source',
      version: 7,
      provenance: {
        'kind': 'manual-reference',
        'reference': 'Synthetic local reference, page 12',
      },
      items: procedureFixtureItems(),
    );
