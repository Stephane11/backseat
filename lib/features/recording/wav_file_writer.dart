import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Writes raw PCM16 bytes to disk as a standard WAV file, patching the
/// header's size fields on [close] once the total data length is known.
/// Writes are chained so callers can fire-and-forget chunks without two
/// operations ever being pending on the file at once.
class WavFileWriter {
  WavFileWriter(
    this.file, {
    this.sampleRate = 16000,
    this.numChannels = 1,
    this.bitsPerSample = 16,
  });

  static const headerBytes = 44;

  final File file;
  final int sampleRate;
  final int numChannels;
  final int bitsPerSample;

  RandomAccessFile? _raf;
  int _dataBytesWritten = 0;
  Future<void> _pending = Future.value();

  Future<void> open() async {
    await file.parent.create(recursive: true);
    _raf = await file.open(mode: FileMode.write);
    await _raf!.writeFrom(_buildHeader(0));
  }

  Future<void> writeChunk(Uint8List bytes) {
    final raf = _raf;
    if (raf == null) return Future.value();
    _dataBytesWritten += bytes.length;
    return _pending = _pending.then((_) => raf.writeFrom(bytes));
  }

  Future<void> close() async {
    final raf = _raf;
    if (raf == null) return;
    _raf = null;
    await _pending;
    await raf.setPosition(0);
    await raf.writeFrom(_buildHeader(_dataBytesWritten));
    await raf.close();
  }

  Uint8List _buildHeader(int dataSize) {
    final bytesPerSample = bitsPerSample ~/ 8;
    final byteRate = sampleRate * numChannels * bytesPerSample;
    final blockAlign = numChannels * bytesPerSample;

    final builder = BytesBuilder();
    builder.add(ascii.encode('RIFF'));
    builder.add(_uint32le(36 + dataSize));
    builder.add(ascii.encode('WAVE'));
    builder.add(ascii.encode('fmt '));
    builder.add(_uint32le(16));
    builder.add(_uint16le(1)); // PCM
    builder.add(_uint16le(numChannels));
    builder.add(_uint32le(sampleRate));
    builder.add(_uint32le(byteRate));
    builder.add(_uint16le(blockAlign));
    builder.add(_uint16le(bitsPerSample));
    builder.add(ascii.encode('data'));
    builder.add(_uint32le(dataSize));
    return builder.toBytes();
  }

  Uint8List _uint32le(int value) =>
      Uint8List(4)..buffer.asByteData().setUint32(0, value, Endian.little);

  Uint8List _uint16le(int value) =>
      Uint8List(2)..buffer.asByteData().setUint16(0, value, Endian.little);
}

/// Converts little-endian PCM16 bytes to the [-1, 1] floats sherpa-onnx takes.
Float32List pcm16ToFloat32(Uint8List bytes) {
  final data = bytes.buffer.asByteData(
    bytes.offsetInBytes,
    bytes.lengthInBytes,
  );
  final count = bytes.length ~/ 2;
  final out = Float32List(count);
  for (var i = 0; i < count; i++) {
    out[i] = data.getInt16(i * 2, Endian.little) / 32768.0;
  }
  return out;
}
