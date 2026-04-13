import 'package:flutter/material.dart';

class Dialpad extends StatelessWidget {
  const Dialpad({super.key, required this.onKeyTap});

  final ValueChanged<String> onKeyTap;

  static const List<String> _keys = <String>[
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '*',
    '0',
    '#',
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _keys
          .map(
            (String key) => SizedBox(
              width: 72,
              child: ElevatedButton(
                onPressed: () => onKeyTap(key),
                child: Text(key),
              ),
            ),
          )
          .toList(),
    );
  }
}
