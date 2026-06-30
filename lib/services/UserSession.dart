import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'api_client.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../config/api_config.dart';


class UserSession {

  UserSession._();


  static String token         = '';
  static String name          = '';
  static String studentId     = '';
  static String email         = '';
  static String phone         = '';

  static String activeRideId     = '';
  static String activeRequestId  = '';  // passenger's current request ID for WS filtering
  static String userId           = '';  // numeric user ID as string
  static String fcmToken         = '';

  static int vehicleId        = 0;
  static String vehicleMode   = '';
  static String vehicleNumber = '';
  static String vehicleModel  = '';
  static String vehicleColour = '';

  static double driverRating  = 0.0;
  static int totalRatings     = 0;
  static int totalRides       = 0;


  static List<String> registeredRoles = [];
  static String activeRole = 'passenger';


  static bool get isDriver =>
      activeRole == 'driver';

  static bool get isPassenger =>
      activeRole == 'passenger';


  static bool get canSwitchRole =>
      registeredRoles.contains('passenger') &&
      registeredRoles.contains('driver');



  static void addPassengerRole(){

    if(!registeredRoles.contains('passenger')){
      registeredRoles.add('passenger');
    }

    activeRole='passenger';
  }



  static void addDriverRole(){

    if(!registeredRoles.contains('driver')){
      registeredRoles.add('driver');
    }

    activeRole='driver';
  }






  // ================= JWT EXPIRY CHECK =================


  static bool isTokenExpired(){


    if(token.isEmpty){
      return true;
    }


    try{


      final parts = token.split('.');


      if(parts.length != 3){
        return true;
      }


      final payload = jsonDecode(

        utf8.decode(

          base64Url.decode(

            base64Url.normalize(parts[1])

          )

        )

      );



      final exp = payload['exp'];



      if(exp == null){
        return true;
      }



      final expiry =
      DateTime.fromMillisecondsSinceEpoch(
        exp * 1000
      );



      return DateTime.now()
          .isAfter(expiry);



    }catch(e){

      return true;

    }

  }






  // ================= FCM =================


  static Future<void> initFCMToken() async {

    try {


      final messaging =
      FirebaseMessaging.instance;


      await messaging.requestPermission();



      final newToken =
      await messaging.getToken();



      if(newToken != null &&
          newToken != fcmToken){


        fcmToken=newToken;


        await _saveFCMTokenToBackend(
            newToken
        );

      }



      messaging.onTokenRefresh.listen(
              (refreshedToken) async {


        fcmToken=refreshedToken;


        await _saveFCMTokenToBackend(
            refreshedToken
        );


      });



    }catch(e){

      debugPrint(
          'FCM error $e'
      );

    }

  }





  static Future<void> _saveFCMTokenToBackend(
      String newToken
      ) async {


    if(token.isEmpty){
      return;
    }


    try{


      final response =
      await http.post(

        Uri.parse(
          '${ApiConfig.baseUrl}/save-token'
        ),


        headers:{


          'Content-Type':
          'application/json',


          'Authorization':
          'Bearer $token',

        },


        body:
        jsonEncode({

          'token':newToken

        }),

      );



      ApiClient.ensureSuccess(response);



    }catch(e){

      debugPrint(
          'FCM save error $e'
      );

    }


  }








  // ================= SAVE =================


  static Future<void> save() async {


    final prefs =
    await SharedPreferences.getInstance();


    await prefs.setString(
        'token',
        token
    );


    await prefs.setString(
        'name',
        name
    );


    await prefs.setString(
        'studentId',
        studentId
    );


    await prefs.setString(
        'email',
        email
    );


    await prefs.setString(
        'phone',
        phone
    );


    await prefs.setString(
        'activeRole',
        activeRole
    );


    await prefs.setString(
        'fcmToken',
        fcmToken
    );


    await prefs.setStringList(
        'roles',
        registeredRoles
    );

  }









  // ================= LOAD =================


  static Future<bool> load() async {


    final prefs =
    await SharedPreferences.getInstance();



    token =
    prefs.getString('token') ?? '';



    name =
    prefs.getString('name') ?? '';



    studentId =
    prefs.getString('studentId') ?? '';



    email =
    prefs.getString('email') ?? '';



    phone =
    prefs.getString('phone') ?? '';



    activeRole =
    prefs.getString('activeRole')
        ?? 'passenger';



    fcmToken =
    prefs.getString('fcmToken')
        ?? '';



    registeredRoles =
        prefs.getStringList('roles')
        ?? [];


    if(token.isNotEmpty &&
        isTokenExpired()){


      await clear();


      return false;

    }



    return token.isNotEmpty;

  }









  // ================= CLEAR =================


  static Future<void> clear() async {


    token='';
    name='';
    studentId='';
    email='';
    phone='';

    activeRideId='';
    activeRequestId='';
    userId='';

    fcmToken='';


    vehicleId=0;
    vehicleMode='';
    vehicleNumber='';
    vehicleModel='';
    vehicleColour='';
    driverRating=0.0;
    totalRatings=0;
    totalRides=0;
    registeredRoles=[];
    activeRole='passenger';
    final prefs =
    await SharedPreferences.getInstance();
    await prefs.clear();
  }
}