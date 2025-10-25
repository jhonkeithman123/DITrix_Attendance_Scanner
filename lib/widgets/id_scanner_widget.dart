import 'package:flutter/material.dart';

class IdScannerWidget extends StatelessWidget {
  const IdScannerWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 240,
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black26),
      ),
      child: const Center(
        child: Icon(Icons.camera_alt, size: 64, color: Colors.black45),
      ),
    );
  }
}
