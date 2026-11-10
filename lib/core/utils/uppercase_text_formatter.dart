import 'package:flutter/services.dart';

/// Formatter huruf kapital dan pembersih karakter non-alphanumeric
/// tanpa merusak composing region keyboard Android (mencegah lag / input patah-patah).
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final clean = newValue.text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (clean == newValue.text) {
      return newValue;
    }
    final int newOffset = clean.length < newValue.selection.end
        ? clean.length
        : (newValue.selection.end < 0 ? 0 : newValue.selection.end);
    return TextEditingValue(
      text: clean,
      selection: TextSelection.collapsed(offset: newOffset),
      composing: TextRange.empty,
    );
  }
}

