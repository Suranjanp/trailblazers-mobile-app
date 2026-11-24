import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Defines the two measurement systems supported by the app.
///
/// Values are stored as metric internally where applicable; this setting
/// controls how measurements are presented to the user and interpreted when
/// they enter values.
enum MeasurementSystem { metric, imperial }

/// Central, app-wide store for user preferences that affect presentation.
///
/// [AppSettings] uses a singleton so screens and widgets read the same settings
/// instance. It extends [ChangeNotifier] to let listening widgets rebuild when
/// the theme or measurement system changes.
///
/// Preferences are persisted locally with SharedPreferences. This keeps these
/// lightweight display settings available between app launches without
/// requiring a Firestore profile read.
class AppSettings extends ChangeNotifier {
  AppSettings._();

  /// Shared instance used throughout the application.
  static final AppSettings instance = AppSettings._();

  // Stable SharedPreferences keys. Keep these unchanged so existing installs
  // continue to read settings saved by earlier app versions.
  static const _darkModeKey = 'settings_dark_mode';
  static const _measurementSystemKey = 'settings_measurement_system';

  // Defaults are used until [load] restores the saved preferences.
  ThemeMode _themeMode = ThemeMode.light;
  MeasurementSystem _measurementSystem = MeasurementSystem.metric;

  /// Current Flutter theme selection.
  ThemeMode get themeMode => _themeMode;

  /// Current unit system used for measurement display and input.
  MeasurementSystem get measurementSystem => _measurementSystem;

  /// Convenience flag for widgets that only need to know whether dark mode is on.
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  /// Convenience flag used by unit conversion and formatting helpers.
  bool get isMetric => _measurementSystem == MeasurementSystem.metric;

  /// Restores saved preferences from local device storage.
  ///
  /// Raw values are checked instead of using typed getters so older or
  /// incorrectly typed entries safely fall back to the app defaults.
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

    // Notify the app after both settings have been restored so dependent
    // widgets can update from one consistent settings state.
    notifyListeners();
  }

  /// Updates the in-memory theme immediately, then persists the selection.
  ///
  /// Notifying before the asynchronous write makes the interface respond
  /// without waiting for local storage.
  Future<void> setDarkMode(bool enabled) async {
    _themeMode = enabled ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();

    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_darkModeKey, enabled);
  }

  /// Changes the active measurement system and saves it locally.
  ///
  /// Screens that listen to this notifier can rebuild their labels and
  /// converted values as soon as the selection changes.
  Future<void> setMeasurementSystem(MeasurementSystem system) async {
    _measurementSystem = system;
    notifyListeners();

    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _measurementSystemKey,
      system == MeasurementSystem.metric ? 'metric' : 'imperial',
    );
  }

  // ---------------------------------------------------------------------------
  // Distance conversion and formatting
  // ---------------------------------------------------------------------------

  /// Converts a stored kilometer value into the currently selected display unit.
  ///
  /// The app keeps distance values in kilometers internally, even when the
  /// user chooses imperial units.
  // Stored distance values remain kilometers throughout the app.
  double displayDistanceFromKm(double kilometers) {
    return isMetric ? kilometers : kilometers * 0.621371;
  }

  /// Formats a kilometer value using the active distance unit.
  String formatDistanceFromKm(double kilometers, {int decimals = 2}) {
    final value = displayDistanceFromKm(kilometers);
    final unit = isMetric ? 'km' : 'mi';
    return '${value.toStringAsFixed(decimals)} $unit';
  }

  /// Unit labels for controls and summaries that display raw values.
  String get distanceUnit => isMetric ? 'km' : 'mi';
  String get weightUnit => isMetric ? 'kg' : 'lb';
  String get heightUnit => isMetric ? 'cm' : 'ft / in';

  /// Converts a distance entered in the selected display unit back to km.
  ///
  /// Call this before persisting user-entered distances so stored data remains
  /// consistent regardless of the device's selected measurement system.
  // Convert a value entered in the selected display unit back to km for storage.
  double enteredDistanceToKm(double value) {
    return isMetric ? value : value / 0.621371;
  }

  // ---------------------------------------------------------------------------
  // Speed and pace conversion
  // ---------------------------------------------------------------------------

  /// Converts a stored km/h speed into the active display unit.
  double displaySpeedFromKmh(double kilometersPerHour) {
    return isMetric ? kilometersPerHour : kilometersPerHour * 0.621371;
  }

  /// Formats a km/h speed as either km/h or mph.
  String formatSpeedFromKmh(double kilometersPerHour, {int decimals = 1}) {
    final value = displaySpeedFromKmh(kilometersPerHour);
    final unit = isMetric ? 'km/h' : 'mph';
    return '${value.toStringAsFixed(decimals)} $unit';
  }

  /// Converts a pace stored as seconds per kilometer into the selected unit.
  ///
  /// Imperial pace is expressed as seconds per mile. Invalid, zero, or
  /// non-finite values return an em dash instead of displaying unusable data.
  String formatPaceFromSecondsPerKm(double secondsPerKm) {
    final secondsPerUnit = isMetric ? secondsPerKm : secondsPerKm * 1.609344;
    if (!secondsPerUnit.isFinite || secondsPerUnit <= 0) return '—';

    final total = secondsPerUnit.round();
    final minutes = total ~/ 60;
    final seconds = (total % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds /${isMetric ? 'km' : 'mi'}';
  }

  // ---------------------------------------------------------------------------
  // Elevation conversion and formatting
  // ---------------------------------------------------------------------------

  /// Converts stored elevation in meters to meters or feet for display.
  double displayElevationFromMeters(double meters) {
    return isMetric ? meters : meters * 3.28084;
  }

  /// Formats an elevation value with its corresponding unit label.
  String formatElevationFromMeters(double meters, {int decimals = 0}) {
    final value = displayElevationFromMeters(meters);
    return '${value.toStringAsFixed(decimals)} ${isMetric ? 'm' : 'ft'}';
  }
}
