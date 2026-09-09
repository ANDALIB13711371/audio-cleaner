import 'dart:io';
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const AudioCleanerApp());
}

class AudioCleanerApp extends StatelessWidget {
  const AudioCleanerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Audio Cleaner',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.deepPurple,
        brightness: Brightness.dark,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? inputPath;
  String? inputName;
  String? outputPath;

  bool removeSilence = true;
  bool reduceNoise = true;
  bool normalize = true;
  double silenceKeep = 0.30;
  double silenceThreshold = -38;
  String bitrate = '192k';

  String title = '';
  String artist = '';
  String album = '';
  String year = '';
  String outputName = 'clean_audio.mp3';

  bool processing = false;
  String status = 'یک فایل صوتی انتخاب کن.';

  final _titleController = TextEditingController();
  final _artistController = TextEditingController();
  final _albumController = TextEditingController();
  final _yearController = TextEditingController();
  final _filenameController = TextEditingController(text: 'clean_audio.mp3');

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    _albumController.dispose();
    _yearController.dispose();
    _filenameController.dispose();
    super.dispose();
  }

  Future<void> pickAudio() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'wav', 'm4a', 'aac', 'ogg', 'opus', 'flac', 'amr'],
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.path == null) {
      setState(() => status = '❌ مسیر فایل قابل دسترسی نیست.');
      return;
    }

    setState(() {
      inputPath = file.path;
      inputName = file.name;
      outputName = file.name.replaceFirst(RegExp(r'\.[^.]+$'), '') + '_clean.mp3';
      _filenameController.text = outputName;
      status = 'فایل انتخاب شد: ${file.name}';
      outputPath = null;
    });
  }

  String q(String value) {
    // Quote an FFmpeg argument for the command parser.
    return "'${value.replaceAll("'", "'\\''")}'";
  }

  String buildAudioFilter() {
    final filters = <String>[];

    if (removeSilence) {
      // Keep a short natural pause instead of making speech sound chopped.
      filters.add(
        'silenceremove='
        'start_periods=1:stop_periods=-1:'
        'stop_duration=0.30:'
        'stop_threshold=${silenceThreshold.toStringAsFixed(0)}dB:'
        'detection=rms',
      );
    }

    if (reduceNoise) {
      filters.add('afftdn=nr=12:nf=-40');
    }

    if (normalize) {
      filters.add('loudnorm=I=-16:TP=-1.5:LRA=11');
    }

    return filters.join(',');
  }

  Future<void> processAudio() async {
    if (inputPath == null) {
      setState(() => status = '⚠️ اول یک فایل صوتی انتخاب کن.');
      return;
    }

    setState(() {
      processing = true;
      status = '⏳ در حال پردازش صدا...';
      outputPath = null;
    });

    try {
      final dir = await getTemporaryDirectory();
      final out = File('${dir.path}/audio_cleaner_${DateTime.now().millisecondsSinceEpoch}.mp3');

      final filters = buildAudioFilter();
      final metadata = <String, String>{
        if (title.trim().isNotEmpty) 'title': title.trim(),
        if (artist.trim().isNotEmpty) 'artist': artist.trim(),
        if (album.trim().isNotEmpty) 'album': album.trim(),
        if (year.trim().isNotEmpty) 'date': year.trim(),
      };

      final metaArgs = StringBuffer();
      metadata.forEach((key, value) {
        metaArgs.write(' -metadata $key=${q(value)}');
      });

      final filterArg = filters.isEmpty ? '' : ' -af ${q(filters)}';

      final command =
          '-y -i ${q(inputPath!)} -vn'
          '$filterArg '
          '-c:a libmp3lame -b:a $bitrate'
          ' -id3v2_version 3'
          '$metaArgs ${q(out.path)}';

      final session = await FFmpegKit.execute(command);
      final code = await session.getReturnCode();

      if (!ReturnCode.isSuccess(code)) {
        final logs = await session.getOutput();
        throw Exception(logs ?? 'FFmpeg error');
      }

      setState(() {
        outputPath = out.path;
        status = '✅ پردازش کامل شد. حالا فایل را ذخیره کن.';
      });
    } catch (e) {
      setState(() {
        status = '❌ خطا در پردازش فایل.';
      });
    } finally {
      setState(() => processing = false);
    }
  }

  Future<void> saveOutput() async {
    if (outputPath == null) {
      setState(() => status = '⚠️ اول فایل را پردازش کن.');
      return;
    }

    try {
      final bytes = await File(outputPath!).readAsBytes();
      final name = _filenameController.text.trim().isEmpty
          ? 'clean_audio.mp3'
          : _filenameController.text.trim().endsWith('.mp3')
              ? _filenameController.text.trim()
              : '${_filenameController.text.trim()}.mp3';

      final uri = await FilePicker.saveFile(
        dialogTitle: 'ذخیره فایل MP3',
        fileName: name,
        bytes: Uint8List.fromList(bytes),
        mimeType: 'audio/mpeg',
        allowedExtensions: ['mp3'],
      );

      if (uri != null) {
        setState(() => status = '🎉 فایل ذخیره شد.');
      }
    } catch (e) {
      setState(() => status = '❌ ذخیره فایل انجام نشد.');
    }
  }

  Widget sectionTitle(String text, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 22),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🎧 Audio Cleaner'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Icon(Icons.audio_file, size: 64),
                    const SizedBox(height: 10),
                    Text(
                      inputName ?? 'هیچ فایل صوتی انتخاب نشده',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: processing ? null : pickAudio,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('انتخاب فایل صوتی'),
                    ),
                  ],
                ),
              ),
            ),

            sectionTitle('پردازش صدا', Icons.tune),

            SwitchListTile(
              title: const Text('✂️ کوتاه کردن فاصله‌های طولانی'),
              subtitle: Text('مکث‌ها به حدود ${silenceKeep.toStringAsFixed(1)} ثانیه کاهش می‌یابند'),
              value: removeSilence,
              onChanged: processing ? null : (v) => setState(() => removeSilence = v),
            ),

            if (removeSilence)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('مقدار مکث باقی‌مانده'),
                  Slider(
                    min: 0.10,
                    max: 0.80,
                    divisions: 14,
                    value: silenceKeep,
                    label: '${silenceKeep.toStringAsFixed(1)}s',
                    onChanged: processing ? null : (v) => setState(() => silenceKeep = v),
                  ),
                  const Text('حساسیت تشخیص سکوت'),
                  Slider(
                    min: -55,
                    max: -25,
                    divisions: 30,
                    value: silenceThreshold,
                    label: '${silenceThreshold.toStringAsFixed(0)} dB',
                    onChanged: processing ? null : (v) => setState(() => silenceThreshold = v),
                  ),
                ],
              ),

            SwitchListTile(
              title: const Text('🔇 کاهش نویز'),
              subtitle: const Text('کاهش نویز پس‌زمینه بدون حذف صدای اصلی'),
              value: reduceNoise,
              onChanged: processing ? null : (v) => setState(() => reduceNoise = v),
            ),

            SwitchListTile(
              title: const Text('🎚️ نرمال‌سازی صدا'),
              subtitle: const Text('یکنواخت‌تر کردن بلندی صدا'),
              value: normalize,
              onChanged: processing ? null : (v) => setState(() => normalize = v),
            ),

            sectionTitle('کیفیت خروجی', Icons.high_quality),

            DropdownButtonFormField<String>(
              value: bitrate,
              decoration: const InputDecoration(
                labelText: 'Bitrate MP3',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: '128k', child: Text('128 kbps')),
                DropdownMenuItem(value: '192k', child: Text('192 kbps ⭐')),
                DropdownMenuItem(value: '256k', child: Text('256 kbps')),
                DropdownMenuItem(value: '320k', child: Text('320 kbps 💎')),
              ],
              onChanged: processing ? null : (v) => setState(() => bitrate = v ?? '192k'),
            ),

            sectionTitle('جزئیات MP3', Icons.edit_note),

            TextField(
              controller: _filenameController,
              decoration: const InputDecoration(
                labelText: 'نام فایل خروجی',
                suffixText: '.mp3',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => outputName = v,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'عنوان',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => title = v,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _artistController,
              decoration: const InputDecoration(
                labelText: 'خواننده',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => artist = v,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _albumController,
              decoration: const InputDecoration(
                labelText: 'آلبوم',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => album = v,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _yearController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'سال',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => year = v,
            ),

            const SizedBox(height: 18),

            if (processing) const LinearProgressIndicator(),

            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(status, textAlign: TextAlign.center),
              ),
            ),

            const SizedBox(height: 12),

            FilledButton.icon(
              onPressed: processing ? null : processAudio,
              icon: const Icon(Icons.auto_fix_high),
              label: const Text('پردازش و ساخت MP3'),
            ),

            const SizedBox(height: 10),

            OutlinedButton.icon(
              onPressed: processing || outputPath == null ? null : saveOutput,
              icon: const Icon(Icons.save_alt),
              label: const Text('ذخیره فایل خروجی'),
            ),

            const SizedBox(height: 24),
            const Text(
              'نکته: برای گفتار، مقدار مکث ۰٫۳ ثانیه معمولاً طبیعی‌تر است. '
              'اگر مکث‌ها بیش از حد حذف شدند، حساسیت تشخیص سکوت را پایین‌تر بیاور.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
