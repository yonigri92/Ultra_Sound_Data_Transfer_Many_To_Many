import 'package:flutter/material.dart';
import './Models/ultra_api.dart'; 

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const UltraDataTransferApp());
}

class UltraDataTransferApp extends StatelessWidget {
  const UltraDataTransferApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UltraSound DataTrasfer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
        brightness: Brightness.light,
      ),
      home: const Scaffold(
        body: SafeArea(
          child: UltraApiInterface(),
        ),
      ),
    );
  }
}