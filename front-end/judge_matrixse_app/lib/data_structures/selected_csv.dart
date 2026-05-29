import 'dart:typed_data';

class SelectedCsv {
  SelectedCsv({required this.name, required this.bytes, required this.headers, required this.allRows});
  final String name;
  final Uint8List bytes;
  final List<String> headers;
  final List<List<String>> allRows;
}