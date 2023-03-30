// ignore_for_file: non_constant_identifier_names

import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart';

class ThumbHash {
  static Image thumbHashToRGBA(Uint8List hash) {
    // Read the constants
    var header24 =
        (hash[0] & 255) | ((hash[1] & 255) << 8) | ((hash[2] & 255) << 16);
    var header16 = (hash[3] & 255) | ((hash[4] & 255) << 8);
    final l_dc = (header24 & 63) / 63.0;
    final p_dc = ((header24 >> 6) & 63) / 31.5 - 1.0;
    final q_dc = ((header24 >> 12) & 63) / 31.5 - 1.0;
    final l_scale = ((header24 >> 18) & 31) / 31.0;
    final hasAlpha = (header24 >> 23) != 0;
    final p_scale = ((header16 >> 3) & 63) / 63.0;
    final q_scale = ((header16 >> 9) & 63) / 63.0;
    final isLandscape = (header16 >> 15) != 0;
    final lx = max(
        3,
        isLandscape
            ? hasAlpha
                ? 5
                : 7
            : header16 & 7);
    final ly = max(
        3,
        isLandscape
            ? header16 & 7
            : hasAlpha
                ? 5
                : 7);
    final a_dc = hasAlpha ? (hash[5] & 15) / 15.0 : 1.0;
    final a_scale = ((hash[5] >> 4) & 15) / 15.0;

    // Read the varying factors (boost saturation by 1.25x to compensate for quantization)
    final ac_start = hasAlpha ? 6 : 5;
    var ac_index = 0;
    var l_channel = Channel(lx, ly);
    var p_channel = Channel(3, 3);
    var q_channel = Channel(3, 3);
    Channel? a_channel;
    ac_index = l_channel.decode(hash, ac_start, ac_index, l_scale);
    ac_index = p_channel.decode(hash, ac_start, ac_index, p_scale * 1.25);
    ac_index = q_channel.decode(hash, ac_start, ac_index, q_scale * 1.25);
    if (hasAlpha) {
      a_channel = Channel(5, 5);
      a_channel.decode(hash, ac_start, ac_index, a_scale);
    }
    var l_ac = l_channel.ac;
    var p_ac = p_channel.ac;
    var q_ac = q_channel.ac;
    var a_ac = hasAlpha ? a_channel?.ac : null;

    // Decode using the DCT into RGB
    final ratio = thumbHashToApproximateAspectRatio(hash);
    final w = (ratio > 1.0 ? 32.0 : 32.0 * ratio).round();
    final h = (ratio > 1.0 ? 32.0 / ratio : 32.0).round();
    final rgba = Uint8List(w * h * 4);
    int cx_stop = max(lx, hasAlpha ? 5 : 3);
    int cy_stop = max(ly, hasAlpha ? 5 : 3);
    final fx = List<double>.filled(cx_stop, 0);
    final fy = List<double>.filled(cy_stop, 0);

    for (var y = 0, i = 0; y < h; y++) {
      for (var x = 0; x < w; x++, i += 4) {
        var l = l_dc, p = p_dc, q = q_dc, a = a_dc;

        // Precompute the coefficients
        for (var cx = 0; cx < cx_stop; cx++) {
          fx[cx] = cos(pi / w * (x + 0.5) * cx);
        }
        for (var cy = 0; cy < cy_stop; cy++) {
          fy[cy] = cos(pi / h * (y + 0.5) * cy);
        }

        // Decode L
        for (var cy = 0, j = 0; cy < ly; cy++) {
          var fy2 = fy[cy] * 2.0;
          for (var cx = cy > 0 ? 0 : 1; cx * ly < lx * (ly - cy); cx++, j++) {
            l += l_ac[j] * fx[cx] * fy2;
          }
        }

        // Decode P and Q
        for (var cy = 0, j = 0; cy < 3; cy++) {
          var fy2 = fy[cy] * 2.0;
          for (var cx = cy > 0 ? 0 : 1; cx < 3 - cy; cx++, j++) {
            var f = fx[cx] * fy2;
            p += p_ac[j] * f;
            q += q_ac[j] * f;
          }
        }

        // Decode A
        if (hasAlpha && a_ac != null) {
          for (var cy = 0, j = 0; cy < 5; cy++) {
            var fy2 = fy[cy] * 2.0;
            for (var cx = cy > 0 ? 0 : 1; cx < 5 - cy; cx++, j++) {
              a += a_ac[j] * fx[cx] * fy2;
            }
          }
        }

        // Convert to RGB
        final b = l - 2.0 / 3.0 * p;
        final r = (3.0 * l - b + q) / 2.0;
        final g = r - q;
        rgba[i] = max(0, (255.0 * min(1, r)).round());
        rgba[i + 1] = max(0, (255.0 * min(1, g)).round());
        rgba[i + 2] = max(0, (255.0 * min(1, b)).round());
        rgba[i + 3] = max(0, (255.0 * min(1, a)).round());
      }
    }

    return Image.fromBytes(
      width: w,
      height: h,
      bytes: rgba.buffer,
      numChannels: 4
    );
  }

  /// Extracts the approximate aspect ratio of the original image.
  ///
  /// @param hash The bytes of the ThumbHash.
  /// @return The approximate aspect ratio (i.e. width / height).
  static double thumbHashToApproximateAspectRatio(Uint8List hash) {
    final header = hash[3];
    final hasAlpha = (hash[2] & 0x80) != 0;
    final isLandscape = (hash[4] & 0x80) != 0;
    final lx = isLandscape
        ? hasAlpha
            ? 5
            : 7
        : header & 7;
    final ly = isLandscape
        ? header & 7
        : hasAlpha
            ? 5
            : 7;
    return lx.toDouble() / ly.toDouble();
  }
}

class Channel {
  int nx;
  int ny;
  double dc = 0;
  List<double> ac = [];
  double scale = 0;

  Channel(this.nx, this.ny) {
    var n = 0;
    for (var cy = 0; cy < ny; cy++) {
      for (var cx = cy > 0 ? 0 : 1; cx * ny < nx * (ny - cy); cx++) {
        n++;
      }
    }
    ac = List<double>.filled(n, 0);
  }

  Channel encode(int w, int h, List<double> channel) {
    var n = 0;
    var fx = List<double>.filled(w, 0);

    for (var cy = 0; cy < ny; cy++) {
      for (var cx = 0; cx * ny < nx * (ny - cy); cx++) {
        var f = 0.0;
        for (var x = 0; x < w; x++) {
          fx[x] = cos(pi / w * cx * (x + 0.5));
        }

        for (var y = 0; y < h; y++) {
          var fy = cos(pi / h * cy * (y + 0.5));
          for (var x = 0; x < w; x++) {
            f += channel[x + y * w] * fx[x] * fy;
          }
        }
        f /= w * h;
        if (cx > 0 || cy > 0) {
          ac[n++] = f;
          scale = max(scale, f.abs());
        } else {
          dc = f;
        }
      }
    }
    if (scale > 0) {
      for (var i = 0; i < ac.length; i++) {
        ac[i] = 0.5 + 0.5 / scale * ac[i];
      }
    }
    return this;
  }

  int decode(Uint8List hash, int start, int index, double scale) {
    for (var i = 0; i < ac.length; i++) {
      final data = hash[start + (index >> 1)] >> ((index & 1) << 2);
      ac[i] = ((data & 15) / 7.5 - 1.0) * scale;
      index++;
    }
    return index;
  }

  int writeTo(Uint8List hash, int start, int index) {
    for (var v in ac) {
      hash[start + (index >> 1)] |= (15.0 * v).round() << ((index & 1) << 2);
      index++;
    }
    return index;
  }
}
