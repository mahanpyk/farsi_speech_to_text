'use strict';

const sampleRate = 16000;
const maxRangeSize = 32 * 1024 * 1024;
const fetchTimeoutMs = 45000;
const cacheName = 'farsi_speech_to_text-773e3d8f';
const defaultModelBase =
  'https://huggingface.co/mentisialog/sherpa-onnx-nemotron-asr-streaming-farsi-1120ms-int8/resolve/773e3d8f6ce043100a5dff6083271aa7811299bd/';

// Same pinned export and checksums as the native model manifest.
const modelAssets = [
  ['LICENSE', 2629, 'be21b29b1c69af5b4a4e60a6bd7bc933eec374e52be29d1ebb9e6a17a6588491'],
  ['NOTICE', 1401, 'aa6f023739a3398c8439955b6c568be47d2cf01a032dbb1062b8a78b65da7e70'],
  ['tokens.txt', 15037, '7ace7d33f3784d50f9a46156cce7c411f39faab64b43df17bd5796abc56a3057', true],
  ['decoder.int8.onnx', 7257753, '548a4763366e3ba4ba5272f3d68465425f5c62b207922ee2d617be920a921b06', true],
  ['joiner.int8.onnx', 1735861, 'e5e365bd22a7f678899674ecad00a9fae23323973de73b508e54ea79eb56b3cc', true],
  ['encoder.int8.onnx', 657573705, '13c1d630f1c82a3534c76ff36a38b4823bdc2413254d5cf7489927b000d57aa2', true],
];

let modulePromise;
let recognizer;
let live;
let commands = Promise.resolve();

class AudioFormatError extends Error {}

self.onmessage = ({ data }) => {
  commands = commands.then(async () => {
    try {
      const text = await dispatch(data);
      self.postMessage({ id: data.id, text });
    } catch (error) {
      self.postMessage({
        id: data.id,
        error: error instanceof Error ? error.message : String(error),
        formatError: error instanceof AudioFormatError,
      });
    }
  });
};

async function dispatch({ id, type, modelBase, bytes }) {
  switch (type) {
    case 'prepare': {
      let sent = -1;
      await prepare(modelBase ?? defaultModelBase, fraction => {
        const progress = Math.floor(fraction * 1000) / 1000;
        if (progress !== sent) self.postMessage({ id, progress });
        sent = progress;
      });
      return;
    }
    case 'wav':
      return transcribeWav(bytes);
    case 'begin':
      if (live) throw new Error('A Persian transcription is already running.');
      live = { stream: openStream(sampleRate), pending: null, hasAudio: false, text: '' };
      return;
    case 'pcm':
      return addPcm(bytes);
    case 'finish':
      return finishPcm();
    case 'end':
      closeLive();
      return;
    default:
      throw new Error('Unknown Persian speech worker command.');
  }
}

async function loadWasm() {
  const assets = new URL('../../sherpa_onnx_web/assets/', self.location.href);
  importScripts(
    new URL('sherpa-onnx-wasm-web.js', assets).href,
    new URL('sherpa-onnx-asr.js', assets).href,
  );
  return await SherpaOnnx({
    locateFile: filename => new URL(filename, assets).href,
  });
}

async function prepare(base, progress) {
  if (recognizer) return;
  if (!navigator.storage?.getDirectory || !crypto.subtle) {
    throw new Error('This browser does not provide secure local model storage.');
  }

  const storage = await navigator.storage.getDirectory();
  const directory = await storage.getDirectoryHandle(cacheName, { create: true });
  const module = await (modulePromise ??= loadWasm().catch(error => {
    modulePromise = undefined;
    throw error;
  }));
  const mounted = [];
  const total = modelAssets.reduce((sum, [, bytes]) => sum + bytes, 0);
  let complete = 0;
  progress(0);

  try {
    for (const [name, length, hash, mount] of modelAssets) {
      const file = await directory.getFileHandle(name, { create: true });
      let bytes = await readVerified(file, length, hash);
      if (!bytes) {
        await download(file, new URL(name, base), length, received => {
          progress((complete + received) / total);
        });
        bytes = await readVerified(file, length, hash);
        if (!bytes) throw new Error('Model failed SHA-256 verification: ' + name);
      }
      if (mount) {
        // Reuse the browser's byte buffer instead of duplicating it in MEMFS.
        module.FS.createDataFile('/', name, bytes, true, false, true);
        mounted.push(name);
      }
      complete += length;
      progress(complete / total);
    }

    const instance = createOnlineRecognizer(module, {
      featConfig: { sampleRate, featureDim: 128 },
      modelConfig: {
        transducer: {
          encoder: '/encoder.int8.onnx',
          decoder: '/decoder.int8.onnx',
          joiner: '/joiner.int8.onnx',
        },
        tokens: '/tokens.txt',
        provider: 'cpu',
        numThreads: 1,
        debug: 0,
      },
      decodingMethod: 'greedy_search',
      enableEndpoint: 0,
    });
    if (!instance.handle) throw new Error('Failed to open the Persian recognition model.');
    recognizer = instance;
  } catch (error) {
    modulePromise = undefined;
    throw error;
  } finally {
    // ONNX Runtime has taken ownership of the initialized graphs.
    for (const name of mounted) module.FS.unlink('/' + name);
  }
}

async function readVerified(handle, length, hash) {
  const file = await handle.getFile();
  if (file.size !== length) return null;
  const bytes = new Uint8Array(await file.arrayBuffer());
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', bytes));
  const hex = Array.from(digest, byte => byte.toString(16).padStart(2, '0')).join('');
  return hex === hash ? bytes : null;
}

async function download(handle, url, length, progress) {
  if (typeof handle.createWritable !== 'function') {
    throw new Error('This browser does not provide writable local model storage.');
  }
  const writer = await handle.createWritable();
  let offset = 0;
  let failures = 0;
  const ranged = length > maxRangeSize;

  try {
    while (offset < length) {
      const start = offset;
      const end = Math.min(start + maxRangeSize, length) - 1;
      try {
        await readDownloadRange(url, length, start, end, ranged, async chunk => {
          await writer.write(chunk);
          offset += chunk.byteLength;
          progress(offset);
        });
        if (offset !== end + 1) throw new Error('The model response ended early.');
        failures = 0;
      } catch (error) {
        failures = offset > start ? 0 : failures + 1;
        if (failures >= 3) throw error;
        if (!ranged) {
          await writer.truncate(0);
          await writer.seek(0);
          offset = 0;
        }
      }
    }
    await writer.close();
  } catch (error) {
    await writer.abort().catch(() => {});
    throw error;
  }
}

async function readDownloadRange(source, total, start, end, ranged, write) {
  const url = new URL(source);
  url.searchParams.set('download', 'true');
  const headers = {};
  if (ranged) {
    url.searchParams.set('offset', String(start));
    headers.Range = 'bytes=' + start + '-' + end;
  }

  const controller = new AbortController();
  let timeout;
  let reader;
  const resetTimeout = () => {
    clearTimeout(timeout);
    timeout = setTimeout(() => controller.abort(), fetchTimeoutMs);
  };

  try {
    resetTimeout();
    const response = await fetch(url, { headers, signal: controller.signal, cache: 'no-store' });
    if (
      response.status !== (ranged ? 206 : 200) ||
      (ranged && response.headers.get('Content-Range') !== 'bytes ' + start + '-' + end + '/' + total) ||
      !response.body
    ) {
      throw new Error('Unexpected model download response (HTTP ' + response.status + ').');
    }

    reader = response.body.getReader();
    let offset = start;
    for (;;) {
      resetTimeout();
      const { done, value } = await reader.read();
      if (done) break;
      offset += value.byteLength;
      if (offset > end + 1) throw new Error('The model response exceeded its expected size.');
      await write(value);
    }
  } finally {
    clearTimeout(timeout);
    if (reader) reader.releaseLock();
    controller.abort();
  }
}

function openStream(rate) {
  if (!recognizer) throw new Error('The Persian recognition model is not ready.');
  const stream = recognizer.createStream();
  if (!stream.handle) throw new Error('Failed to open a Persian audio stream.');
  try {
    stream.setOption('language', 'fa-IR');
    // The streaming model can miss the first word without this short padding.
    stream.acceptWaveform(rate, new Float32Array(Math.floor(rate / 2)));
    return stream;
  } catch (error) {
    stream.free();
    throw error;
  }
}

function decodeAvailable(stream) {
  let decoded = false;
  while (recognizer.isReady(stream)) {
    recognizer.decode(stream);
    decoded = true;
  }
  return decoded;
}

function finish(stream, rate) {
  // One encoder window of silence lets the model flush the last word.
  stream.acceptWaveform(rate, new Float32Array(Math.floor(rate * 1.12)));
  stream.inputFinished();
  decodeAvailable(stream);
  return recognizer.getResult(stream).text.trim();
}

function addPcm(bytes) {
  if (!live) throw new Error('No live Persian transcription is running.');
  const pending = live.pending;
  const samples = new Float32Array(Math.floor((bytes.length + (pending === null ? 0 : 1)) / 2));
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  let offset = 0;
  let sample = 0;
  if (pending !== null && bytes.length > 0) {
    samples[sample++] = ((view.getInt8(0) << 8) | pending) / 32768;
    offset++;
  }
  while (offset + 1 < bytes.length) {
    samples[sample++] = view.getInt16(offset, true) / 32768;
    offset += 2;
  }
  if (bytes.length > 0) {
    live.pending = offset < bytes.length ? bytes[offset] : null;
  }
  if (samples.length > 0) {
    live.hasAudio = true;
    live.stream.acceptWaveform(sampleRate, samples);
    if (decodeAvailable(live.stream)) live.text = recognizer.getResult(live.stream).text.trim();
  }
  return live.text;
}

function finishPcm() {
  if (!live) throw new Error('No live Persian transcription is running.');
  try {
    if (live.pending !== null) throw new AudioFormatError('PCM16 input ends with an incomplete sample.');
    return live.hasAudio ? finish(live.stream, sampleRate) : '';
  } finally {
    closeLive();
  }
}

function closeLive() {
  if (!live) return;
  live.stream.free();
  live = undefined;
}

function transcribeWav(bytes) {
  const { view, dataOffset, dataLength, rate } = readWav(bytes);
  const stream = openStream(rate);
  try {
    for (let offset = 0; offset < dataLength;) {
      const count = Math.min(Math.floor((dataLength - offset) / 2), rate);
      const samples = new Float32Array(count);
      for (let i = 0; i < count; i++, offset += 2) {
        samples[i] = view.getInt16(dataOffset + offset, true) / 32768;
      }
      stream.acceptWaveform(rate, samples);
      decodeAvailable(stream);
    }
    return finish(stream, rate);
  } finally {
    stream.free();
  }
}

function readWav(bytes) {
  const formatError = new AudioFormatError('Expected a non-empty mono, 16-bit PCM WAV.');
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  // RIFF/WAVE chunk identifiers read as four ASCII bytes in order.
  if (view.byteLength < 12 || view.getUint32(0) !== 0x52494646 || view.getUint32(8) !== 0x57415645) {
    throw formatError;
  }
  const limit = view.getUint32(4, true) + 8;
  if (limit > view.byteLength) throw formatError;

  let rate = 0;
  let dataOffset = 0;
  let dataLength = 0;
  for (let offset = 12; offset + 8 <= limit;) {
    const type = view.getUint32(offset);
    const length = view.getUint32(offset + 4, true);
    const start = offset + 8;
    const end = start + length;
    if (end > limit) throw formatError;

    if (type === 0x666d7420) { // fmt
      if (
        length < 16 || view.getUint16(start, true) !== 1 ||
        view.getUint16(start + 2, true) !== 1 ||
        view.getUint16(start + 12, true) !== 2 ||
        view.getUint16(start + 14, true) !== 16
      ) throw formatError;
      rate = view.getUint32(start + 4, true);
    } else if (type === 0x64617461 && dataLength === 0) { // data
      dataOffset = start;
      dataLength = length;
    }

    offset = end + (length % 2);
  }

  if (rate === 0 || rate > 384000 || dataLength === 0 || dataLength % 2 !== 0) throw formatError;
  return { view, dataOffset, dataLength, rate };
}
