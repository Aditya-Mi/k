import '../bank_definition.dart';
import 'axis.dart';
import 'kotak.dart';
import 'bob.dart';
import 'catalogue.dart';

/// Register new banks here.
final List<BankDefinition> builtInBanks = [
  axisBank,
  kotakBank,
  bobBank,
  ...catalogueBanks,
];
