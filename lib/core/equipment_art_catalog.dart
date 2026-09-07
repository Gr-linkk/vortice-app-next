import 'dart:ui';

/// Bundled, categorical illustrations, not photographs of a particular asset.
enum EquipmentArt {
  motorYacht('Motor yacht', 'Yate a motor'),
  sailingYacht('Sailing yacht', 'Velero'),
  catamaran('Catamaran', 'Catamarán'),
  sportFisher('Sport fishing boat', 'Barco de pesca'),
  workBoat('Work boat', 'Lancha de trabajo'),
  centerConsole('Center console boat', 'Lancha de consola central'),
  hydraulicDredge('Hydraulic dredge', 'Draga hidráulica'),
  cutterDredge('Cutter suction dredge', 'Draga de corte y succión'),
  excavator('Excavator', 'Excavadora'),
  wheelLoader('Wheel loader', 'Cargadora de ruedas'),
  bulldozer('Bulldozer', 'Bulldozer'),
  generator('Diesel generator', 'Generador diésel'),
  pump('Pump', 'Bomba'),
  crane('Crane', 'Grúa'),
  other('Equipment', 'Equipo'),
  engine('Engine', 'Motor'),
  rib('RIB / Inflatable Boat', 'Lancha semirrígida / inflable', 'rib.png'),
  aluminumSkiff('Aluminum Skiff', 'Lancha de aluminio', 'aluminum-skiff.png'),
  cabinCruiser('Cabin Cruiser', 'Lancha cabinada', 'cabin-cruiser.png'),
  trawler('Commercial Trawler', 'Arrastrero comercial', 'trawler.png'),
  purseSeiner('Purse Seiner', 'Pesquero de cerco', 'purse-seiner.png'),
  tugboat('Tugboat', 'Remolcador', 'tugboat.png'),
  backhoeLoader('Backhoe Loader', 'Retroexcavadora', 'backhoe-loader.png'),
  skidSteer('Skid Steer', 'Minicargadora', 'skid-steer.png'),
  dumpTruck('Dump Truck', 'Camión volquete', 'dump-truck.png'),
  motorGrader('Motor Grader', 'Motoniveladora', 'motor-grader.png'),
  forklift('Forklift', 'Montacargas', 'forklift.png'),
  telehandler('Telehandler', 'Manipulador telescópico', 'telehandler.png'),
  roadRoller('Road Roller', 'Rodillo compactador', 'road-roller.png'),
  mobileCrane('Mobile Crane', 'Grúa móvil', 'mobile-crane.png'),
  towerCrane('Tower Crane', 'Grúa torre', 'tower-crane.png'),
  davit('Davit', 'Pescante', 'davit.png'),
  lightVehicle(
    'LV / Light Vehicle',
    'LV / Vehículo ligero',
    'light-vehicle.png',
  ),
  highwayTruck('Highway Truck', 'Camión de carretera', 'highway-truck.png');

  const EquipmentArt(this.label, this.spanishLabel, [this.file]);
  final String label;
  final String spanishLabel;
  final String? file;

  String get imagePath => file == null ? assetPath : 'assets/equipment/$file';

  static const assetPath = 'assets/equipment/technical-equipment.png';
  static const columns = 4;
  static const sourceSize = 1254.0;

  /// Verified bounds of complete subjects in the generated atlas. The model
  /// did not respect equal cells, so equal-quarter slicing would cut boats.
  Rect get sourceRect => index < _subjectBounds.length
      ? _subjectBounds[index]
      : const Rect.fromLTWH(0, 0, sourceSize, sourceSize);
}

const _subjectBounds = <Rect>[
  Rect.fromLTRB(45, 120, 352, 325),
  Rect.fromLTRB(385, 40, 615, 350),
  Rect.fromLTRB(650, 42, 905, 354),
  Rect.fromLTRB(923, 72, 1225, 353),
  Rect.fromLTRB(45, 454, 320, 588),
  Rect.fromLTRB(333, 439, 619, 592),
  Rect.fromLTRB(621, 390, 925, 620),
  Rect.fromLTRB(928, 407, 1223, 608),
  Rect.fromLTRB(44, 649, 329, 890),
  Rect.fromLTRB(333, 688, 620, 890),
  Rect.fromLTRB(630, 686, 905, 890),
  Rect.fromLTRB(949, 653, 1230, 900),
  Rect.fromLTRB(54, 965, 337, 1174),
  Rect.fromLTRB(379, 912, 588, 1188),
  Rect.fromLTRB(633, 929, 905, 1170),
  Rect.fromLTRB(936, 931, 1206, 1175),
];

// Full stable IDs from seed/asset-types.json. Never match UUID suffixes.
const _seedTypes = <String, EquipmentArt>{
  '00000000-0000-0000-0000-000000000001': EquipmentArt.motorYacht,
  '00000000-0000-0000-0000-000000000002': EquipmentArt.sailingYacht,
  '00000000-0000-0000-0000-000000000003': EquipmentArt.catamaran,
  '00000000-0000-0000-0000-000000000004': EquipmentArt.sportFisher,
  '00000000-0000-0000-0000-000000000005': EquipmentArt.workBoat,
  '00000000-0000-0000-0000-000000000006': EquipmentArt.centerConsole,
  '00000000-0000-0000-0000-000000000007': EquipmentArt.hydraulicDredge,
  '00000000-0000-0000-0000-000000000008': EquipmentArt.cutterDredge,
  '00000000-0000-0000-0000-000000000009': EquipmentArt.excavator,
  '00000000-0000-0000-0000-00000000000a': EquipmentArt.wheelLoader,
  '00000000-0000-0000-0000-00000000000b': EquipmentArt.bulldozer,
  '00000000-0000-0000-0000-00000000000c': EquipmentArt.generator,
  '00000000-0000-0000-0000-00000000000d': EquipmentArt.other,
  '00000000-0000-0000-0000-00000000000e': EquipmentArt.pump,
  '00000000-0000-0000-0000-00000000000f': EquipmentArt.crane,
  '00000000-0000-0000-0000-000000000010': EquipmentArt.engine,
  '00000000-0000-0000-0000-000000000011': EquipmentArt.rib,
  '00000000-0000-0000-0000-000000000012': EquipmentArt.aluminumSkiff,
  '00000000-0000-0000-0000-000000000013': EquipmentArt.cabinCruiser,
  '00000000-0000-0000-0000-000000000014': EquipmentArt.trawler,
  '00000000-0000-0000-0000-000000000015': EquipmentArt.purseSeiner,
  '00000000-0000-0000-0000-000000000016': EquipmentArt.tugboat,
  '00000000-0000-0000-0000-000000000017': EquipmentArt.backhoeLoader,
  '00000000-0000-0000-0000-000000000018': EquipmentArt.skidSteer,
  '00000000-0000-0000-0000-000000000019': EquipmentArt.dumpTruck,
  '00000000-0000-0000-0000-00000000001a': EquipmentArt.motorGrader,
  '00000000-0000-0000-0000-00000000001b': EquipmentArt.forklift,
  '00000000-0000-0000-0000-00000000001c': EquipmentArt.telehandler,
  '00000000-0000-0000-0000-00000000001d': EquipmentArt.roadRoller,
  '00000000-0000-0000-0000-00000000001e': EquipmentArt.mobileCrane,
  '00000000-0000-0000-0000-00000000001f': EquipmentArt.towerCrane,
  '00000000-0000-0000-0000-000000000020': EquipmentArt.davit,
  '00000000-0000-0000-0000-000000000021': EquipmentArt.lightVehicle,
  '00000000-0000-0000-0000-000000000022': EquipmentArt.highwayTruck,
};

const _namedTypes = <String, EquipmentArt>{
  'motor yacht': EquipmentArt.motorYacht,
  'sailing yacht': EquipmentArt.sailingYacht,
  'catamaran': EquipmentArt.catamaran,
  'sport fisher': EquipmentArt.sportFisher,
  'panga / work boat': EquipmentArt.workBoat,
  'work boat': EquipmentArt.workBoat,
  'center console': EquipmentArt.centerConsole,
  'hydraulic dredge': EquipmentArt.hydraulicDredge,
  'cutter suction dredge': EquipmentArt.cutterDredge,
  'excavator': EquipmentArt.excavator,
  'wheel loader': EquipmentArt.wheelLoader,
  'bulldozer': EquipmentArt.bulldozer,
  'diesel genset': EquipmentArt.generator,
  'diesel generator': EquipmentArt.generator,
  'generator': EquipmentArt.generator,
  'pump': EquipmentArt.pump,
  'centrifugal pump': EquipmentArt.pump,
  'ballast pump': EquipmentArt.pump,
  'crane': EquipmentArt.crane,
  'marine crane': EquipmentArt.crane,
  'engine': EquipmentArt.engine,
  'diesel engine': EquipmentArt.engine,
  'marine engine': EquipmentArt.engine,
  'custom / other': EquipmentArt.other,
  'rib / inflatable boat': EquipmentArt.rib,
  'aluminum skiff': EquipmentArt.aluminumSkiff,
  'cabin cruiser': EquipmentArt.cabinCruiser,
  'commercial trawler': EquipmentArt.trawler,
  'purse seiner': EquipmentArt.purseSeiner,
  'tugboat': EquipmentArt.tugboat,
  'backhoe loader': EquipmentArt.backhoeLoader,
  'skid steer': EquipmentArt.skidSteer,
  'dump truck': EquipmentArt.dumpTruck,
  'motor grader': EquipmentArt.motorGrader,
  'forklift': EquipmentArt.forklift,
  'telehandler': EquipmentArt.telehandler,
  'road roller': EquipmentArt.roadRoller,
  'mobile crane': EquipmentArt.mobileCrane,
  'tower crane': EquipmentArt.towerCrane,
  'davit': EquipmentArt.davit,
  'lv / light vehicle': EquipmentArt.lightVehicle,
  'lv': EquipmentArt.lightVehicle,
  'light vehicle': EquipmentArt.lightVehicle,
  'highway truck': EquipmentArt.highwayTruck,
};

/// [typeName] must be the selected catalog type, never an asset's display name.
EquipmentArt equipmentArtFor({String? assetTypeId, String? typeName}) {
  final stable = _seedTypes[assetTypeId?.trim().toLowerCase()];
  if (stable != null) return stable;
  final normalized = typeName?.trim().toLowerCase().replaceAll(
    RegExp(r'\s+'),
    ' ',
  );
  return _namedTypes[normalized] ?? EquipmentArt.other;
}
