import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum MeasurementSystem { metric, imperial }

class AppSettings extends ChangeNotifier {
  AppSettings._();

  static final AppSettings instance = AppSettings._();

  static const _darkModeKey = 'settings_dark_mode';
  static const _measurementSystemKey = 'settings_measurement_system';

  ThemeMode _themeMode = ThemeMode.light;
  MeasurementSystem _measurementSystem = MeasurementSystem.metric;

  ThemeMode get themeMode => _themeMode;
  MeasurementSystem get measurementSystem => _measurementSystem;
  bool get isDarkMode => _themeMode == ThemeMode.dark;
  bool get isMetric => _measurementSystem == MeasurementSystem.metric;

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();

    // Read raw values so an older or incorrectly typed stored preference
    // cannot cause a runtime cast exception (for example, double -> bool).
    _themeMode = preferences.get(_darkModeKey) == true
        ? ThemeMode.dark
        : ThemeMode.light;

    _measurementSystem =
        preferences.get(_measurementSystemKey) == 'imperial'
        ? MeasurementSystem.imperial
        : MeasurementSystem.metric;

    notifyListeners();
  }

  Future<void> setDarkMode(bool enabled) async {
    _themeMode = enabled ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();

    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_darkModeKey, enabled);
  }

  Future<void> setMeasurementSystem(MeasurementSystem system) async {
    _measurementSystem = system;
    notifyListeners();

    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _measurementSystemKey,
      system == MeasurementSystem.metric ? 'metric' : 'imperial',
    );
  }

  // Stored distance values remain kilometers throughout the app.
  double displayDistanceFromKm(double kilometers) {
    return isMetric ? kilometers : kilometers * 0.621371;
  }

  String formatDistanceFromKm(double kilometers, {int decimals = 2}) {
    final value = displayDistanceFromKm(kilometers);
    final unit = isMetric ? 'km' : 'mi';
    return '${value.toStringAsFixed(decimals)} $unit';
  }

  String get distanceUnit => isMetric ? 'km' : 'mi';
  String get weightUnit => isMetric ? 'kg' : 'lb';
  String get heightUnit => isMetric ? 'cm' : 'ft / in';

  // Convert a value entered in the selected display unit back to km for storage.
  double enteredDistanceToKm(double value) {
    return isMetric ? value : value / 0.621371;
  }

  double displaySpeedFromKmh(double kilometersPerHour) {
    return isMetric ? kilometersPerHour : kilometersPerHour * 0.621371;
  }

  String formatSpeedFromKmh(double kilometersPerHour, {int decimals = 1}) {
    final value = displaySpeedFromKmh(kilometersPerHour);
    final unit = isMetric ? 'km/h' : 'mph';
    return '${value.toStringAsFixed(decimals)} $unit';
  }

  String formatPaceFromSecondsPerKm(double secondsPerKm) {
    final secondsPerUnit = isMetric ? secondsPerKm : secondsPerKm * 1.609344;
    if (!secondsPerUnit.isFinite || secondsPerUnit <= 0) return '—';

    final total = secondsPerUnit.round();
    final minutes = total ~/ 60;
    final seconds = (total % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds /${isMetric ? 'km' : 'mi'}';
  }

  double displayElevationFromMeters(double meters) {
    return isMetric ? meters : meters * 3.28084;
  }

  String formatElevationFromMeters(double meters, {int decimals = 0}) {
    final value = displayElevationFromMeters(meters);
    return '${value.toStringAsFixed(decimals)} ${isMetric ? 'm' : 'ft'}';
  }
}


