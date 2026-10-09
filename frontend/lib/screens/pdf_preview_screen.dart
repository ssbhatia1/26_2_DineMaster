import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

class PdfPreviewScreen extends StatelessWidget {
  final Future<Uint8List> Function(PdfPageFormat) buildPdf;
  final String title;

  const PdfPreviewScreen({
    super.key,
    required this.buildPdf,
    this.title = 'Preview Invoice',
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: PdfPreview(
        build: buildPdf,
        allowPrinting: true,
        allowSharing: true,
        canChangeOrientation: false,
        canChangePageFormat: false,
      ),
    );
  }
}
