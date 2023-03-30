// ignore_for_file: lines_longer_than_80_chars
import 'dart:typed_data';
import 'dart:io';

import 'package:image/image.dart';
import 'package:test/test.dart';
import 'package:thumbhash_flutter/thumbhash_flutter.dart';

void main() {
  test('decode a thumbhash and check equality', () {
    const thumbHash = 'DC F8 05 15 82 28 48 5A 8A BB 47 B1 8F D7 86 55 D3 60 F9 86 46';
    final digits = thumbHash.split(' ');
    final data = digits.map((d) => int.parse(d, radix: 16)).toList();
    
    final actualImg = ThumbHash.thumbHashToRGBA(Uint8List.fromList(data));
    final actual = actualImg.data?.buffer.asUint8List();
    
    // generate hero image
    // File('test/images/flower-thumbhash-actual.png').writeAsBytesSync(encodePng(actualImg));

    final expectedImg = decodePng(File('test/images/flower-thumbhash.png').readAsBytesSync());
    final expected = expectedImg?.data?.buffer.asUint8List();

    expect(actual, expected);
  });

  test('decode a thumbhash2 and check equality', () {
    const thumbHash = 'DD D7 05 55 86 A5 78 77 AC 89 87 AF 76 18 88 82 88 80 76 08 68';
    final digits = thumbHash.split(' ');
    final data = digits.map((d) => int.parse(d, radix: 16)).toList();
    
    final actualImg = ThumbHash.thumbHashToRGBA(Uint8List.fromList(data));
    final actual = actualImg.data?.buffer.asUint8List();
    
    // generate hero image
    // File('test/images/landscape-thumbhash-actual.png').writeAsBytesSync(encodePng(actualImg));

    final expectedImg = decodePng(File('test/images/landscape-thumbhash.png').readAsBytesSync());
    final expected = expectedImg?.data?.buffer.asUint8List();

    expect(actual, expected);
  });
}