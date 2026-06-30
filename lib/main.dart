import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'dart:async';

import 'firebase_options.dart';

import 'screens/splash_screen.dart';
import 'screens/Ridebook.dart';
import 'screens/Notifications.dart';
import 'screens/CallScreen.dart';
import 'screens/ChatScreen.dart';
import 'screens/DriverDashboard.dart';

import 'services/firebase_notification_service.dart';
import 'services/UserSession.dart';


final GlobalKey<NavigatorState> navigatorKey =
GlobalKey<NavigatorState>();



void main() async {

  WidgetsFlutterBinding.ensureInitialized();


  try {

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );


  } catch (e) {

    debugPrint(
        'Firebase init failed: $e'
    );

  }


  runApp(
    const MyApp(),
  );

}






class MyApp extends StatefulWidget {


  const MyApp({super.key});


  @override
  State<MyApp> createState() =>
      _MyAppState();


}






class _MyAppState extends State<MyApp> {


  @override
  void initState() {

    super.initState();

    _initApp();

  }






  Future<void> _initApp() async {


    // Load session first and check JWT expiry
    final loggedIn =
    await UserSession.load();



    if(!loggedIn){

      debugPrint(
          "User logged out: token expired"
      );

    }




    // Initialize notifications
    await FirebaseNotificationService.instance
        .initialize();





    FirebaseNotificationService.instance
        .notificationTapStream
        .listen((data) {


      _handleNotificationTap(data);


    });







    // NOTIFICATIONS STREAM IS JUST FOR DISPLAY IN NOTIFICATIONS SCREEN
    // AUTO-NAVIGATION ONLY HAPPENS WHEN USER TAPS NOTIFICATION
    // (via notificationTapStream and local notification tap handler)


    if(loggedIn){


      await FirebaseNotificationService.instance
          .saveTokenToBackend();


      await UserSession.initFCMToken();


    }



  }



  void _handleNotificationTap(
      Map<String,dynamic> data
      ){

    debugPrint('Notification tap received! Data: $data');

    final navigator =
        navigatorKey.currentState;

    if(navigator == null){
      debugPrint('Navigator is null!');
      return;
    }

    final type =
    data['type']?.toString();
    
    debugPrint('Notification type: $type');

    if(type == 'incoming_call'){



      final rideId =
      data['ride_id']?.toString() ?? '';


      final callerName =
      data['caller_name']?.toString()
          ??
          'Caller';



      navigator.push(
        MaterialPageRoute(

          builder: (_) => CallScreen(

            contactName: callerName,

            contactPhone:'',

            callerRole:
            UserSession.isDriver
                ? 'driver'
                : 'passenger',


            rideId:rideId,

            isIncoming:true,

          ),

        ),
      );


      return;

    }


    if(type == 'new_ride_request'
        &&
        UserSession.isDriver){



      navigator.push(

        MaterialPageRoute(

          builder: (_) =>
          const DriverDashboardScreen(),

        ),

      );


      return;

    }


    if(type == 'chat_message'
        ||
        (data['ride_id'] != null &&
            type == null)){



      final rideId =
      data['ride_id']
          ?.toString()
          ?? '';

      final senderName =
      data['sender_name']
          ?.toString()
          ??
          'User';


      navigator.push(

        MaterialPageRoute(

          builder: (_) => ChatScreen(

            contactName:senderName,

            contactRole:
            UserSession.isDriver
                ? 'passenger'
                : 'driver',


            rideRoute:'',

            rideId:rideId,

          ),

        ),

      );
      return;

    }


    // ── AI Ride Recommendation ──
    if(type == 'ride_recommendation'){
      final rideId = data['ride_id']?.toString() ?? '';
      final from   = data['from_address']?.toString() ?? '';
      final to     = data['to_address']?.toString() ?? '';
      
      // Parse string values from FCM (since FCM only supports string data)
      double? fromLat;
      double? fromLng;
      double? toLat;
      double? toLng;
      DateTime? departureTime;
      
      if (data['from_lat'] != null && data['from_lat'].toString().isNotEmpty) {
        fromLat = double.tryParse(data['from_lat'].toString());
      }
      if (data['from_lng'] != null && data['from_lng'].toString().isNotEmpty) {
        fromLng = double.tryParse(data['from_lng'].toString());
      }
      if (data['to_lat'] != null && data['to_lat'].toString().isNotEmpty) {
        toLat = double.tryParse(data['to_lat'].toString());
      }
      if (data['to_lng'] != null && data['to_lng'].toString().isNotEmpty) {
        toLng = double.tryParse(data['to_lng'].toString());
      }
      
      // Parse departure time from FCM
      if (data['departure_time'] != null && data['departure_time'].toString().isNotEmpty) {
        try {
          departureTime = DateTime.parse(data['departure_time'].toString());
        } catch (e) {
          debugPrint('Could not parse departure time: $e');
        }
      }

      // Open the booking flow pre-filled with the recommended ride
      navigator.push(
        MaterialPageRoute(
          builder: (_) => RideSearchScreen(
            prefillRideId: rideId,
            prefillFrom:   from,
            prefillTo:     to,
            prefillFromLat: fromLat,
            prefillFromLng: fromLng,
            prefillToLat:   toLat,
            prefillToLng:   toLng,
            prefillDepartureTime: departureTime,
          ),
        ),
      );
      return;
    }


    final rawRoute =
    (
        data['route']
            ??
            data['screen']
    )
        ?.toString();



    final route =
    rawRoute
        ?.trim()
        .toLowerCase();

    if(route == '/rides'
        ||
        route == 'rides'){

      navigator.push(

        MaterialPageRoute(

          builder: (_) =>
          const RideSearchScreen(),

        ),

      );


      return;

    }

    navigator.push(

      MaterialPageRoute(

        builder: (_) =>
        const NotificationsScreen(),

      ),

    );


  }


  @override
  void dispose(){

    FirebaseNotificationService.instance
        .dispose();


    super.dispose();

  }

  @override
  Widget build(BuildContext context) {


    return MaterialApp(

      navigatorKey:navigatorKey,


      debugShowCheckedModeBanner:false,


      title:'Hamrah App',



      theme:ThemeData(

        primarySwatch:Colors.teal,

        primaryColor:
        const Color(0xFF00897B),

        visualDensity:
        VisualDensity.adaptivePlatformDensity,

      ),
      home:
      const SplashScreen(),
    );
  }
}