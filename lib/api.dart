import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class Api {
  final String serverUrl; // The base URL of the API server
  bool autoRefreshFlag = false;
  bool refreshInProcessFlag = false;

  Timer? autoRefreshTimer;
  DateTime? lastTokenRefreshTime;
  DateTime? idTokenExpiration;
  DateTime? accessTokenExpiration;

  String? accessToken;
  String? refreshToken; // Field for storing refresh token

  // Requires a BuildContext to display the snackbar
  final BuildContext context;

  Api({required this.serverUrl, required this.context});


Future<http.Response> issueRequest(String endpoint,
      {Map<String, String>? headers,
      String? body,
      String method = 'GET'}) async {
    log("Starting issueRequest method", name: "API Request");

    try {
      await _refreshAccessTokenIfNeeded(); // Ensure token refresh if necessary
      log("Access token refreshed or valid", name: "Token Status");

      final fullUrl = Uri.parse('$serverUrl$endpoint');
      log("Full URL: ${fullUrl.path}", name: "Full URL");

      final finalHeaders = headers ?? {};
      if (accessToken != null) {
        finalHeaders['Authorization'] = 'Bearer $accessToken';
        log("Authorization header set with token", name: "Authorization");
      }

      final request = http.Request(method, fullUrl);
      log("HTTP Method: $method, Full URL: $fullUrl", name: "Request Details");

      if (body != null) {
        request.body = body;
        log("Request body set", name: "Body Details");
      }

      request.headers.addAll(finalHeaders);
      log("Final request headers: ${request.headers}", name: "Request Headers");

      final streamedResponse = await request.send();
      log("Request sent, awaiting response", name: "Sending Request");

      final response = await http.Response.fromStream(streamedResponse);
      log("Response received with status: ${response.statusCode}",
          name: "Response Status");

      // Display Snackbar message based on response
      if (response.statusCode >= 200 && response.statusCode < 300) {
        log("Response body: ${response.body}", name: "Response Body");

        // Display Snackbar at the top
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('GetMessage successful'),
            duration: const Duration(seconds: 2), // Show for 2 seconds
            behavior: SnackBarBehavior.floating, // Make it appear on top
            margin: const EdgeInsets.only(top: 50.0), // Position it towards top
          ),
        );
      } else {
        log("Error response: ${response.body}", name: "Error Response");

        // Display Error Snackbar at the top
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${response.body}'),
            duration: const Duration(seconds: 2), // Show for 2 seconds
            behavior: SnackBarBehavior.floating, // Make it appear on top
            margin: const EdgeInsets.only(top: 50.0), // Position it towards top
          ),
        );
      }

      return response;
    } catch (e, stacktrace) {
      log("Error in issueRequest: $e", name: "Error");
      log("Stacktrace: $stacktrace", name: "Stacktrace");

      // Display Error Snackbar if an exception occurs
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('An error occurred: $e'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(top: 50.0),
        ),
      );

      rethrow; // Re-throw the error to be handled elsewhere
    }
  }


  // Log in using the Firebase token and retrieve access/refresh tokens
 // Log in using the Firebase token and retrieve access/refresh tokens
  Future<void> loginWithFirebaseToken(String token) async {
    final response = await http.post(
      Uri.parse('$serverUrl/login-with-firebase-idtoken'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization':
            'Bearer $token', // Send the Firebase token in the Authorization header
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body)['data'];
      _setTokens(data['access_token'], data['refresh_token'],
          DateTime.parse(data['expiry']));

      // Store tokens securely using FlutterSecureStorage
      await _storeTokensSecurely(data['access_token'], data['refresh_token']);
    } else {
      throw Exception('Login failed: ${response.body}');
    }
  }


   // Load tokens from Secure Storage
  Future<void> loadTokens() async {
    const storage = FlutterSecureStorage();
    accessToken = await storage.read(key: 'access_token');
    refreshToken = await storage.read(key: 'refresh_token');

    // Here you would set token expiration details if needed, from your tokens or API response
  }

  // Refresh the access token
  Future<void> refreshAccessToken() async {
    if (refreshInProcessFlag) return;

    refreshInProcessFlag = true;
    try {
      if (refreshToken == null) {
        throw Exception(
            'Refresh token is null; cannot refresh the access token.');
      }

      final response = await http.post(
        Uri.parse('$serverUrl/refresh-token'),
        body: jsonEncode({'refresh_token': refreshToken}),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'];
        _setTokens(data['access_token'], data['refresh_token'],
            DateTime.parse(data['expiry']));

        // Show a snackbar indicating the token was refreshed
        _showSnackbar("Token refreshed successfully");

        // Store the new tokens securely
        await _storeTokensSecurely(data['access_token'], data['refresh_token']);
      } else {
        throw Exception('Failed to refresh token: ${response.body}');
      }
    } finally {
      refreshInProcessFlag = false;
    }
  }

  // Verify the JWT token (native verification in Dart)
  bool verifyJWT(String token) {
    return !JwtDecoder.isExpired(token);
  }

  // Start the auto-refresh timer (1.5-minute interval)
  void startAutoRefresh() {
    if (autoRefreshTimer != null) return;

    autoRefreshFlag = true;
    autoRefreshTimer = Timer.periodic(
      const Duration(seconds: 90), // 1.5 minutes = 90 seconds
      (timer) => _refreshAccessTokenIfNeeded(),
    );
  }

  // Stop the auto-refresh timer
  void stopAutoRefresh() {
    autoRefreshTimer?.cancel();
    autoRefreshTimer = null;
    autoRefreshFlag = false;
  }

  // Refresh the access token if needed
  Future<void> _refreshAccessTokenIfNeeded() async {
    if (accessTokenExpiration != null &&
        DateTime.now().isAfter(accessTokenExpiration!)) {
      await refreshAccessToken(); // Call renamed method here
    }
  }

  // Set tokens and their expiration details
  void _setTokens(
      String accessToken, String refreshToken, DateTime accessTokenExpiry) {
    this.accessToken = accessToken;
    this.refreshToken = refreshToken;
    accessTokenExpiration = accessTokenExpiry;
    lastTokenRefreshTime = DateTime.now();
  }

  // Store access and refresh tokens securely using FlutterSecureStorage
  Future<void> _storeTokensSecurely(
      String accessToken, String refreshToken) async {
    const storage = FlutterSecureStorage();
    await storage.write(key: 'access_token', value: accessToken);
    await storage.write(key: 'refresh_token', value: refreshToken);
  }

  // Show a snackbar message
  void _showSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 1),
      ),
    );
  }
}
