import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:google_speech/endless_streaming_service.dart';
import 'package:google_speech/google_speech.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rxdart/rxdart.dart';

const int kAudioSampleRate = 16000;
const int kAudioNumChannels = 1;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mic Stream Example',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const AudioRecognize(),
    );
  }
}

class AudioRecognize extends StatefulWidget {
  const AudioRecognize({super.key});

  @override
  State<StatefulWidget> createState() => _AudioRecognizeState();
}

class _AudioRecognizeState extends State<AudioRecognize> {
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();

  bool recognizing = false;
  bool recognizeFinished = false;
  String text = '';
  StreamSubscription<List<int>>? _audioStreamSubscription;
  BehaviorSubject<List<int>>? _audioStream;
  StreamController<Food>? _recordingDataController;
  StreamSubscription? _recordingDataSubscription;

  @override
  void initState() {
    super.initState();
  }

  void streamingRecognize() async {
    try {
      await _recorder.openRecorder();
      // Stream to be consumed by speech recognizer
      _audioStream = BehaviorSubject<List<int>>();

      // Create recording stream
      _recordingDataController = StreamController<Food>();
      _recordingDataSubscription =
          _recordingDataController?.stream.listen((buffer) {
        if (buffer is FoodData) {
          _audioStream!.add(buffer.data!);
        }
      });

      setState(() {
        recognizing = true;
      });

      await Permission.microphone.request();

      await _recorder.startRecorder(
          toStream: _recordingDataController!.sink,
          codec: Codec.pcm16,
          numChannels: kAudioNumChannels,
          sampleRate: kAudioSampleRate);

      final serviceAccount = ServiceAccount.fromString(
          (await rootBundle.loadString('assets/google_service_account.json')));
      final speechToText = EndlessStreamingService.viaServiceAccount(
          serviceAccount,
          cloudSpeechEndpoint: 'eu-speech.googleapis.com');
      final config = _getConfig();

      final responseStream = speechToText.endlessStream;

      speechToText.endlessStreamingRecognize(
          StreamingRecognitionConfig(config: config, interimResults: true),
          _audioStream!,
          restartTime: const Duration(seconds: 60),
          transitionBufferTime: const Duration(seconds: 2));

      var responseText = '';

      responseStream.listen((data) {
        final currentText =
            data.results.map((e) => e.alternatives.first.transcript).join('\n');

        if (data.results.first.isFinal) {
          responseText += '\n$currentText';
          setState(() {
            text = responseText;
            recognizeFinished = true;
          });
        } else {
          setState(() {
            text = '$responseText\n$currentText';
            recognizeFinished = true;
          });
        }
      }, onDone: () {
        setState(() {
          recognizing = false;
        });
      });
    } catch (error) {
      debugPrint('Error: $error');
      setState(() {
        recognizing = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $error'),
      ));
    }
  }

  void stopRecording() async {
    await _recorder.stopRecorder();
    await _audioStreamSubscription?.cancel();
    await _audioStream?.close();
    await _recordingDataSubscription?.cancel();
    setState(() {
      recognizing = false;
    });
  }

  RecognitionConfig _getConfig() => RecognitionConfig(
      encoding: AudioEncoding.LINEAR16,
      model: RecognitionModel.basic,
      enableAutomaticPunctuation: true,
      sampleRateHertz: 16000,
      languageCode: 'ko-KR');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audio File Example'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: <Widget>[
            Expanded(
              child: SingleChildScrollView(
                child: _RecognizeContent(
                  text: text,
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: ElevatedButton(
                  onPressed: recognizing ? stopRecording : streamingRecognize,
                  child: recognizing
                      ? const Text('Stop recording')
                      : const Text('Start endless streaming from mic'),
                ),
              ),
            ),
          ],
        ),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}

class _RecognizeContent extends StatelessWidget {
  final String text;

  const _RecognizeContent({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: <Widget>[
          const Text(
            'The text recognized by the Google Speech Api:',
          ),
          const SizedBox(
            height: 16.0,
          ),
          Text(
            text,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}
