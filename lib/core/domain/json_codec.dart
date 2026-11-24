import 'dart:convert';
import 'models.dart';

Json decodeJson(String value) => Map<String, dynamic>.from(jsonDecode(value));
String encodeJson(Json value) => jsonEncode(value);
