import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:vibration/vibration.dart';

void main() {
  runApp(MaterialApp(home: MyApp()));
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  List<List<dynamic>> dataPoints = [];
  double x = 0, y = 0, z = 0, speed = 0;
  late int startTime;
  late int lastTime;

  bool recording = false;

  int samplingPeriodms = 100;

  late TextEditingController samplingTextController;
  FocusNode focusNode = FocusNode();

  late Timer vibrationTimer;

  @override
  void initState() {
    startTime = lastTime = DateTime.now().millisecondsSinceEpoch;
    samplingTextController = TextEditingController.fromValue(
        TextEditingValue(text: samplingPeriodms.toString()));
    super.initState();
    _initAccelerometer();
    _initGPS();
  }

  void _initAccelerometer() {
    accelerometerEventStream(samplingPeriod: SensorInterval.fastestInterval)
        .listen((AccelerometerEvent event) {
      // Only update the values if 100 milliseconds have passed
      // 1 millisecond is subtracted to account for the time taken to update the values
      if (DateTime.now().millisecondsSinceEpoch - lastTime <=
          samplingPeriodms - 3) {
        return;
      }
      lastTime = DateTime.now().millisecondsSinceEpoch;

      setState(() {
        x = event.x;
        y = event.y;
        z = event.z;
      });

      if (recording) {
        dataPoints.add([
          (DateTime.now().millisecondsSinceEpoch - startTime).toDouble(),
          event.x,
          event.y,
          event.z,
          speed,
        ]);
      }

      // Limit the number of data points to 10000
      // if (dataPoints.length > 10000) {
      //   dataPoints.removeAt(0);
      // }
    });
  }

  void _initGPS() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error(
          'Location permissions are permanently denied, we cannot request permissions.');
    }

    LocationSettings locationSettings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      forceLocationManager: true,
      intervalDuration: Duration(milliseconds: samplingPeriodms),
      //(Optional) Set foreground notification config to keep the app alive
      //when going to the background
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationText:
            "Example app will continue to receive your location even when you aren't using it",
        notificationTitle: "Running in Background",
        enableWakeLock: true,
      ),
    );

    Geolocator.getPositionStream(locationSettings: locationSettings)
        .listen((Position position) {
      setState(() {
        speed = position.speed;
      });
    });
  }

  Future<void> _saveToCSV() async {
    String csvData = const ListToCsvConverter().convert(dataPoints);
    final directory = await getApplicationDocumentsDirectory();
    final now = DateTime.now();
    final path =
        '${directory.path}/data_points_${now.hour}:${now.minute}:${now.second}.csv';
    final file = File(path);
    await file.writeAsString(csvData);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Data saved to $path')),
    );
    await Share.shareXFiles([XFile(path)], text: 'Great data');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text('Starva'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            SizedBox(
              height: 40,
            ),
            Text('Accelerometer Data:'),
            Text('x=$x'),
            Text('y=$y'),
            Text('z=$z'),
            SizedBox(height: 20),
            Text('GPS Speed: $speed m/s'),
            SizedBox(height: 40),
            SizedBox(
              width: 100,
              child: TextField(
                focusNode: focusNode,
                onTapOutside: (_) => focusNode.unfocus(),
                onChanged: (value) => samplingPeriodms = int.parse(value),
                controller: samplingTextController,
                decoration: new InputDecoration(labelText: "Sampling Hz"),
                keyboardType: TextInputType.number,
              ),
            ),
            SizedBox(
              height: 20,
            ),
            recording
                ? TextButton.icon(
                    onPressed: () {
                      int stopTimems = DateTime.now().millisecondsSinceEpoch;
                      setState(() {
                        recording = false;
                        dataPoints.removeWhere((dataPoint) =>
                            stopTimems - startTime - dataPoint[0] < 15000);
                      });
                      vibrationTimer.cancel();
                    },
                    icon: const Icon(
                      Icons.stop,
                      color: Colors.white,
                    ),
                    label: const Text(
                      "Stop Recording",
                      style: TextStyle(color: Colors.white),
                    ),
                    style: TextButton.styleFrom(backgroundColor: Colors.red),
                  )
                : TextButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text("Recording stars in 15 seconds")));
                      Vibration.vibrate(duration: 1000, amplitude: 255);
                      Future.delayed(const Duration(seconds: 15))
                          .then((value) => setState(() {
                                if (!recording) {
                                  vibrationTimer = Timer.periodic(
                                      const Duration(seconds: 10),
                                      (_) => Vibration.vibrate(
                                          duration: 500, amplitude: 255));
                                  Vibration.vibrate(
                                      duration: 1000, amplitude: 255);
                                  dataPoints = [];
                                  startTime = lastTime =
                                      DateTime.now().millisecondsSinceEpoch;
                                  recording = true;
                                }
                              }));
                    },
                    icon: const Icon(
                      Icons.play_arrow,
                      color: Colors.white,
                    ),
                    label: const Text(
                      "Start Recording",
                      style: TextStyle(color: Colors.white),
                    ),
                    style: TextButton.styleFrom(backgroundColor: Colors.green),
                  ),
            SizedBox(
              height: 25,
            ),
            if (recording)
              const Text(
                  "The last 15 seconds of the data will always be excluded"),
            const SizedBox(
              height: 25,
            ),
            Text("${dataPoints.length} datapoints in memory"),
            TextButton.icon(
              onPressed: dataPoints.isNotEmpty ? _saveToCSV : null,
              icon: Icon(Icons.save),
              label: Text('Save to CSV'),
            ),
          ],
        ),
      ),
    );
  }
}
