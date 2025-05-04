import 'package:flutter/material.dart';

class Tag {
  final String name;
  final Map<int, int> ratios;
  final Color color;

  Tag({
    required this.name,
    required this.ratios,
    required this.color,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'ratios': ratios.map((key, value) => MapEntry(key.toString(), value)),
      'color': color.value,
    };
  }

  factory Tag.fromMap(Map<String, dynamic> map) {
    return Tag(
      name: map['name'],
      ratios: Map<String, dynamic>.from(map['ratios'] ?? {})
          .map((k, v) => MapEntry(int.parse(k), v)),
      color: Color(map['color']),
    );
  }
}
