import 'package:flutter/material.dart';

class SmartMeasurementLogo extends StatelessWidget {
  final double size;

  const SmartMeasurementLogo({super.key, this.size = 70.0});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(size * 0.25),
        border: Border.all(color: Colors.cyanAccent.withOpacity(0.6), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.cyanAccent.withOpacity(0.25),
            blurRadius: 15,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            Icons.filter_center_focus,
            color: Colors.cyanAccent,
            size: size * 0.55,
          ),
          Container(
            width: size * 0.15,
            height: size * 0.15,
            decoration: const BoxDecoration(
              color: Color(0xFF00FF87),
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}