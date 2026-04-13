enum DtmfTone {
  digit0('0'),
  digit1('1'),
  digit2('2'),
  digit3('3'),
  digit4('4'),
  digit5('5'),
  digit6('6'),
  digit7('7'),
  digit8('8'),
  digit9('9'),
  star('*'),
  hash('#');

  const DtmfTone(this.value);

  final String value;
}
