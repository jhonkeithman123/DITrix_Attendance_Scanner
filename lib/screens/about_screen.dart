import 'package:flutter/material.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'DITrix Attendance Scanner\n\n'
          'This app captures student ID images and sends them to the backend for processing.'
          'Use the Capture ID screen to take a photo of an ID.',
          style: TextStyle(fontSize: 16),
        ),
      ),
    );
  }
}
