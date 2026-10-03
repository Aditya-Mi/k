import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// UUIDv7: time-ordered, so new rows append to indexes instead of scattering.
String newId() => _uuid.v7();
