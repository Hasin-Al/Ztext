import 'dart:async';
import 'dart:ui';
import 'package:background_sms/background_sms.dart';
import 'package:battery_info/battery_info_plugin.dart';
import 'package:battery_info/model/android_battery_info.dart';
import 'package:flutter/material.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shosti/constants.dart';
import 'package:shosti/widgets/ContactRow.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:disable_battery_optimization/disable_battery_optimization.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeService();
  runApp(const MyApp());
}

Future<void> initializeService() async {
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      // this will be executed when app is in foreground or background in separated isolate
      onStart: onStart,

      // auto start service
      autoStart: true,
      isForegroundMode: true,
    ),
    iosConfiguration: IosConfiguration(
      // auto start service
      autoStart: true,

      // this will be executed when app is in foreground in separated isolate
      onForeground: onStart,

      // you have to enable background fetch capability on xcode project
      onBackground: onIosBackground,
    ),
  );
  service.startService();
}

void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  BatteryInfoPlugin()
      .androidBatteryInfoStream
      .listen((AndroidBatteryInfo? batteryInfo) {
    final batteryLevel = batteryInfo?.batteryLevel ?? 0;
    _sendSMS(batteryLevel);

    service.invoke('updateUI', {
      'batteryLevel': batteryLevel,
    });
  });
}

// to ensure this is executed
// run app from xcode, then from xcode menu, select Simulate Background Fetch
bool onIosBackground(ServiceInstance service) {
  WidgetsFlutterBinding.ensureInitialized();
  print('FLUTTER BACKGROUND FETCH');

  return true;
}

void _sendSMS(_batteryLevel) async {
  print('trying to send sms');
  if (!await shouldSendSMS(_batteryLevel)) {
    print('we should not send sms');
    return;
  }

  print('sending sms');

  final location = await getLocation();

  print('location: ' + location);
  print('battery level: ' + _batteryLevel.toString());

  final contactNos = (await SharedPreferences.getInstance())
      .getStringList(Constants.CONTACT_NO_STORE);

  if (contactNos == null) {
    print('no contacts found to send sms');
    return;
  }

  final message =
      "My phone is running out of Battery level. Check my location on map'https://www.google.com/maps/@?api=1&query=$location'";

  bool isSuccess = false;
  for (String contactNo in contactNos) {
    final result = await BackgroundSms.sendMessage(
      phoneNumber: contactNo,
      message: message,
    );

    if (result == SmsStatus.sent) {
      isSuccess = true;
    }
  }

  if (isSuccess) {
    print('sms sent successfully');
    setSMSSent(true);
  } else {
    print('can\'t send sms');
  }
}

Future<bool> shouldSendSMS(_batteryLevel) async {
  if (_batteryLevel <= 10) {
    if (await isAlreadySentSMS()) {
      return false;
    }
    return true;
  } else {
    setSMSSent(false);
    return false;
  }
}

Future<bool> isAlreadySentSMS() async {
  var sharedPref = await SharedPreferences.getInstance();
  var isSent = sharedPref.getBool(Constants.SMS_SENT_FLAG);
  return isSent ?? false;
}

void setSMSSent(value) async {
  var sharedPref = await SharedPreferences.getInstance();
  sharedPref.setBool(Constants.SMS_SENT_FLAG, value);
}

Future<String> getLocation() async {
  bool serviceEnabled;

  // Test if location services are enabled.
  serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    return Future.error('Location services are disabled.');
  }

  var location = 'unknown lat, unknown lng';
  final position = await Geolocator.getCurrentPosition(
    desiredAccuracy: LocationAccuracy.high,
  );

  location = "${position.latitude}, ${position.longitude}";

  return location;
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Shosti',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.cyan,
      ),
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key}) : super(key: key);

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class MyContact {
  String name;
  String number;

  MyContact(this.name, this.number) {}
}

class _MyHomePageState extends State<MyHomePage> {
  List<MyContact> _contacts = [];
  bool isLoading = false;
  int _batteryLevel = 0;
  String permisstionStatus = 'Granted:';
  bool isBackgroundServiceRunning = false;
  bool isBatteryOptimizationDisabled = false;

  @override
  void initState() {
    getPermissions();
    getBatteryState();
    fillContacts();
    backgroundServiceInfo();
    batteryOptimization();
    super.initState();
  }

  void batteryOptimization() async {
    isBatteryOptimizationDisabled =
        await DisableBatteryOptimization.isBatteryOptimizationDisabled ?? false;
  }

  void backgroundServiceInfo() async {
    isBackgroundServiceRunning = await FlutterBackgroundService().isRunning();
    FlutterBackgroundService().invoke('setAsForeground');
  }

  void getPermissions() async {
    final sms = await Permission.sms.request();
    if (sms.isGranted) {
      permisstionStatus += ' SMS';
    }
    final geolocation = await Permission.location.request();
    if (geolocation.isGranted) {
      final alwaysLocation = await Permission.locationAlways.request();
      if (alwaysLocation.isGranted) {
        permisstionStatus += ' Location';
      }
    }
    final contact = await Permission.contacts.request();
    if (contact.isGranted) {
      permisstionStatus += ' Contact';
    }

    bool disabled = await DisableBatteryOptimization
            .showDisableBatteryOptimizationSettings() ??
        false;

    setState(() {
      permisstionStatus = permisstionStatus;

      isBatteryOptimizationDisabled = disabled;
    });
  }

  void addContact(Contact contact) async {
    final sharedPref = await SharedPreferences.getInstance();
    var names = sharedPref.getStringList(Constants.CONTACT_NAME_STORE);
    var nos = sharedPref.getStringList(Constants.CONTACT_NO_STORE);

    if (names == null || nos == null) {
      names = <String>[];
      nos = <String>[];
    }

    if (contact.displayName == null ||
        contact.phones == null ||
        contact.phones!.isEmpty) {
      return;
    }

    final name = contact.displayName!;
    var no = '';

    if (contact.phones!.length > 1) {
      no = contact.phones!.elementAt(0).value!;
    } else {
      no = contact.phones!.elementAt(0).value!;
    }

    names.add(name);
    nos.add(no);

    sharedPref.setStringList(Constants.CONTACT_NAME_STORE, names);
    sharedPref.setStringList(Constants.CONTACT_NO_STORE, nos);

    setState(() {
      _contacts.add(MyContact(name, no));
    });
  }

  void deleteContact(int index) async {
    final sharedPref = await SharedPreferences.getInstance();

    final contactNames = sharedPref.getStringList(Constants.CONTACT_NAME_STORE);
    final contactNos = sharedPref.getStringList(Constants.CONTACT_NO_STORE);
    final contacts = <MyContact>[];

    if (contactNames != null && contactNos != null) {
      final names = <String>[];
      final nos = <String>[];

      for (int i = 0; i < contactNames.length; i++) {
        if (i == index) continue;

        names.add(contactNames[i]);
        nos.add(contactNos[i]);
        contacts.add(MyContact(contactNames[i], contactNos[i]));
      }

      sharedPref.setStringList(Constants.CONTACT_NAME_STORE, names);
      sharedPref.setStringList(Constants.CONTACT_NO_STORE, nos);
    }

    setState(() {
      _contacts = contacts;
    });
  }

  void fillContacts() async {
    final sharedPref = await SharedPreferences.getInstance();

    final contactNames = sharedPref.getStringList(Constants.CONTACT_NAME_STORE);
    final contactNos = sharedPref.getStringList(Constants.CONTACT_NO_STORE);

    if (contactNames == null || contactNos == null) {
      return;
    }

    final storedContacts = <MyContact>[];
    for (int i = 0; i < contactNames.length; i++) {
      storedContacts.add(MyContact(contactNames[i], contactNos[i]));
    }

    setState(() {
      _contacts = storedContacts;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Ztext"),
        backgroundColor: const Color.fromARGB(255, 30, 173, 106),
      ),
      body: SingleChildScrollView(
        child: Center(
            child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Column(
              children: [
                const SizedBox(
                  height: 20,
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isBackgroundServiceRunning
                          ? Icons.check_box_outlined
                          : Icons.check_box_outline_blank_rounded,
                    ),
                    const Text('Background Service status'),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.all(10),
                  child: CircularPercentIndicator(
                    radius: 120.0,
                    lineWidth: 10.0,
                    animation: true,
                    percent: _batteryLevel / 100,
                    center: Text(
                      "$_batteryLevel%",
                      style: const TextStyle(
                          fontSize: 20.0,
                          fontWeight: FontWeight.w600,
                          color: Color.fromRGBO(0, 0, 0, 1)),
                    ),
                    backgroundColor: const Color.fromARGB(255, 100, 98, 98),
                    circularStrokeCap: CircularStrokeCap.round,
                    progressColor: const Color.fromARGB(255, 30, 173, 106),
                  ),
                ),
                if (_contacts.isNotEmpty && !isLoading)
                  ListView.builder(
                    scrollDirection: Axis.vertical,
                    shrinkWrap: true,
                    itemCount: _contacts.length,
                    itemBuilder: (BuildContext ctx, int index) {
                      return ContactRow(
                          _contacts.elementAt(index), deleteContact, index);
                    },
                  ),
                if (_contacts.isEmpty && !isLoading)
                  const Text('No contacts found'),
                if (isLoading) const CircularProgressIndicator(),
                TextButton(
                  onPressed: () async {
                    final sharedPref = await SharedPreferences.getInstance();
                    final contactNos =
                        sharedPref.getStringList(Constants.CONTACT_NO_STORE);
                    if (contactNos == null) {
                      return;
                    }

                    for (String contactNo in contactNos) {
                      final result = await BackgroundSms.sendMessage(
                        phoneNumber: contactNo,
                        message:
                            'You are selected as a trusted contact of Ztext App',
                      );

                      if (result == SmsStatus.sent) {
                        print('sent test sms to $contactNo');
                      }
                    }
                  },
                  child: const Text('Inform Them'),
                ),
                Text(permisstionStatus),
                if (!isBatteryOptimizationDisabled)
                  MaterialButton(
                    child: const Text('Disable Battery Optimizations'),
                    onPressed: () async {
                      bool disabled = await DisableBatteryOptimization
                              .showDisableBatteryOptimizationSettings() ??
                          false;

                      if (disabled) {
                        setState(() {
                          isBatteryOptimizationDisabled = true;
                        });
                      }
                    },
                  ),
              ],
            ),
          ],
        )),
      ),
      floatingActionButton: FloatingActionButton(
          onPressed: !isLoading && _contacts.length < 3
              ? () => getContacts(context)
              : null,
          backgroundColor: const Color.fromARGB(255, 30, 173, 106),
          child: const Icon(Icons.add)),
    );
  }

  Future<void> getContacts(context) async {
    setState(() {
      isLoading = true;
    });

    var status = await Permission.contacts.request();
    if (status == PermissionStatus.denied) {
      status = await Permission.contacts.request();
      if (status == PermissionStatus.denied) {
        Future.error('Contacts permission denied');
      }
    }

    if (status == PermissionStatus.permanentlyDenied) {
      Future.error('Error, Can\'t use this app, please allow from settings');
    }

    if (status == PermissionStatus.granted) {
      final Iterable<Contact> contacts = await ContactsService.getContacts(
        withThumbnails: false,
        photoHighResolution: false,
      );

      setState(() {
        isLoading = false;
      });

      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Select Contact'),
            content: SizedBox(
              width: MediaQuery.of(context).size.width - 50,
              height: MediaQuery.of(context).size.height - 200,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: contacts.length,
                itemBuilder: (context, index) {
                  final contact = contacts.elementAt(index);
                  return ListTile(
                    title: Text(
                      contact.displayName == null
                          ? 'NULL'
                          : contact.displayName!,
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.check),
                      onPressed: () {
                        addContact(contact);
                        Navigator.of(context).pop();
                      },
                    ),
                  );
                },
              ),
            ),
            actions: <Widget>[
              TextButton(
                child: const Text('Cancel'),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      );
    } else {
      // TODO show message
      print('no permission');

      setState(() {
        isLoading = false;
      });
    }
  }

  void getBatteryState() async {
    var androidBatteryInfo = await BatteryInfoPlugin().androidBatteryInfo;
    setState(() {
      _batteryLevel = androidBatteryInfo?.batteryLevel ?? 0;
    });

    FlutterBackgroundService().on('updateUI').listen((data) {
      if (data != null) {
        setState(() {
          _batteryLevel = data['batteryLevel'];
        });
      }
    });
  }

  @override
  void dispose() {
    FlutterBackgroundService().invoke('setAsBackground');
    super.dispose();
  }
}
