import 'dart:typed_data';

/// Converts successive chunks of little-endian PCM16 to normalized floats.
final class Pcm16Decoder {
  int? _pendingByte;

  /// Decodes complete samples and retains a partial sample for the next chunk.
  Float32List add(Uint8List bytes) {
    if (bytes.isEmpty) return Float32List(0);

    final pending = _pendingByte;
    final output = Float32List((bytes.length + (pending == null ? 0 : 1)) ~/ 2);
    final data = ByteData.sublistView(bytes);
    var offset = 0;
    var sample = 0;

    if (pending != null) {
      output[sample++] = ((data.getInt8(0) << 8) | pending) / 32768;
      offset++;
    }
    while (offset + 1 < bytes.length) {
      output[sample++] = data.getInt16(offset, Endian.little) / 32768;
      offset += 2;
    }

    _pendingByte = offset < bytes.length ? bytes[offset] : null;
    return output;
  }

  /// Checks that the input ended at a sample boundary.
  void finish() {
    if (_pendingByte != null) {
      throw const FormatException(
        'PCM16 input ends with an incomplete sample.',
      );
    }
  }
}
