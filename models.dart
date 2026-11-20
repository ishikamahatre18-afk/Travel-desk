import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'services/crypto_service.dart';
import 'services/vault.dart';

double _d(dynamic v, double def) => v is num ? v.toDouble() : def;
int _i(dynamic v, int def) => v is num ? v.toInt() : def;
String _s(dynamic v, [String def = '']) => v is String ? v : def;

enum TravelMode { flight, ship, road }

extension TravelModeX on TravelMode {
  String get label {
    switch (this) {
      case TravelMode.flight:
        return 'Flight';
      case TravelMode.ship:
        return 'Ship';
      case TravelMode.road:
        return 'Road';
    }
  }
}

enum HotelTier { budget, standard, luxury }

extension HotelTierX on HotelTier {
  String get label {
    switch (this) {
      case HotelTier.budget:
        return 'Budget';
      case HotelTier.standard:
        return 'Standard';
      case HotelTier.luxury:
        return 'Luxury';
    }
  }
}

class AgencyProfile {
  String name;
  String phone;
  String currency;
  double markupPct;
  double gstPct;
  double childDiscountPct;
  int validityDays;

  AgencyProfile({
    this.name = 'My Travel Agency',
    this.phone = '',
    this.currency = 'INR',
    this.markupPct = 10,
    this.gstPct = 5,
    this.childDiscountPct = 25,
    this.validityDays = 3,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'phone': phone,
        'currency': currency,
        'markupPct': markupPct,
        'gstPct': gstPct,
        'childDiscountPct': childDiscountPct,
        'validityDays': validityDays,
      };

  factory AgencyProfile.fromJson(Map<String, dynamic> j) => AgencyProfile(
        name: _s(j['name'], 'My Travel Agency'),
        phone: _s(j['phone']),
        currency: _s(j['currency'], 'INR'),
        markupPct: _d(j['markupPct'], 10),
        gstPct: _d(j['gstPct'], 5),
        childDiscountPct: _d(j['childDiscountPct'], 25),
        validityDays: _i(j['validityDays'], 3),
      );
}

class Destination {
  String id;
  String name;
  String country;
  double hotelBudget; // per room per night, 0 = not offered
  double hotelStandard;
  double hotelLuxury;
  double mealsPerDay; // per person per day
  double activitiesPerDay; // per person per day
  double localTransportPerDay; // per person per day
  String visaNote;
  List<String> highlights;
  List<int> peakMonths; // 1..12
  double peakSurchargePct; // applied to hotel on peak nights
  int hotelUpdatedAt; // epoch ms, 0 = unknown
  String source; // 'owner' or 'estimate'

  Destination({
    required this.id,
    required this.name,
    this.country = '',
    this.hotelBudget = 0,
    this.hotelStandard = 0,
    this.hotelLuxury = 0,
    this.mealsPerDay = 0,
    this.activitiesPerDay = 0,
    this.localTransportPerDay = 0,
    this.visaNote = '',
    List<String>? highlights,
    List<int>? peakMonths,
    this.peakSurchargePct = 0,
    this.hotelUpdatedAt = 0,
    this.source = 'owner',
  })  : highlights = highlights ?? [],
        peakMonths = peakMonths ?? [];

  double hotelRate(HotelTier t) {
    switch (t) {
      case HotelTier.budget:
        return hotelBudget;
      case HotelTier.standard:
        return hotelStandard;
      case HotelTier.luxury:
        return hotelLuxury;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'country': country,
        'hotelBudget': hotelBudget,
        'hotelStandard': hotelStandard,
        'hotelLuxury': hotelLuxury,
        'mealsPerDay': mealsPerDay,
        'activitiesPerDay': activitiesPerDay,
        'localTransportPerDay': localTransportPerDay,
        'visaNote': visaNote,
        'highlights': highlights,
        'peakMonths': peakMonths,
        'peakSurchargePct': peakSurchargePct,
        'hotelUpdatedAt': hotelUpdatedAt,
        'source': source,
      };

  factory Destination.fromJson(Map<String, dynamic> j) => Destination(
        id: _s(j['id']),
        name: _s(j['name']),
        country: _s(j['country']),
        hotelBudget: _d(j['hotelBudget'], 0),
        hotelStandard: _d(j['hotelStandard'], 0),
        hotelLuxury: _d(j['hotelLuxury'], 0),
        mealsPerDay: _d(j['mealsPerDay'], 0),
        activitiesPerDay: _d(j['activitiesPerDay'], 0),
        localTransportPerDay: _d(j['localTransportPerDay'], 0),
        visaNote: _s(j['visaNote']),
        highlights:
            (j['highlights'] as List?)?.map((e) => e.toString()).toList() ?? [],
        peakMonths: (j['peakMonths'] as List?)
                ?.map((e) => (e as num).toInt())
                .toList() ??
            [],
        peakSurchargePct: _d(j['peakSurchargePct'], 0),
        hotelUpdatedAt: _i(j['hotelUpdatedAt'], 0),
        source: _s(j['source'], 'owner'),
      );
}

class TransportRate {
  String id;
  String from;
  String destinationId;
  TravelMode mode;
  double pricePerPerson; // one way
  double hours; // one way, 0 = unknown
  String notes;
  int updatedAt; // epoch ms when the price was last confirmed, 0 = unknown
  String source; // 'owner' or 'estimate'

  TransportRate({
    required this.id,
    required this.from,
    required this.destinationId,
    required this.mode,
    required this.pricePerPerson,
    this.hours = 0,
    this.notes = '',
    this.updatedAt = 0,
    this.source = 'owner',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'from': from,
        'destinationId': destinationId,
        'mode': mode.name,
        'pricePerPerson': pricePerPerson,
        'hours': hours,
        'notes': notes,
        'updatedAt': updatedAt,
        'source': source,
      };

  factory TransportRate.fromJson(Map<String, dynamic> j) => TransportRate(
        id: _s(j['id']),
        from: _s(j['from']),
        destinationId: _s(j['destinationId']),
        mode: TravelMode.values.firstWhere(
          (m) => m.name == j['mode'],
          orElse: () => TravelMode.flight,
        ),
        pricePerPerson: _d(j['pricePerPerson'], 0),
        hours: _d(j['hours'], 0),
        notes: _s(j['notes']),
        updatedAt: _i(j['updatedAt'], 0),
        source: _s(j['source'], 'owner'),
      );
}

class Inquiry {
  final String clientName;
  final String origin;
  final String destinationId;
  final TravelMode mode;
  final DateTime start;
  final DateTime end;
  final int adults;
  final int children;
  final int? rooms;
  final HotelTier tier;
  final bool includeActivities;
  final bool roundTrip;
  final String clientCurrency;

  const Inquiry({
    this.clientName = '',
    required this.origin,
    required this.destinationId,
    required this.mode,
    required this.start,
    required this.end,
    required this.adults,
    this.children = 0,
    this.rooms,
    this.tier = HotelTier.standard,
    this.includeActivities = true,
    this.roundTrip = true,
    this.clientCurrency = '',
  });
}

String newId() => DateTime.now().microsecondsSinceEpoch.toString();

/// Agency data for the unlocked account. Stored as one AES-256-GCM blob
/// (key held in memory only), inside the Android-Keystore-backed vault.
/// The same blob is what gets backed up to the cloud.
class DataStore extends ChangeNotifier {
  static final DataStore instance = DataStore._();
  DataStore._();

  AgencyProfile profile = AgencyProfile();
  List<Destination> destinations = [];
  List<TransportRate> transports = [];
  List<String> notes = [];

  String? _accountId;
  List<int>? _dek;

  /// Called after every local save so the cloud copy can follow.
  VoidCallback? onLocalSave;

  Destination? destById(String id) {
    for (final d in destinations) {
      if (d.id == id) return d;
    }
    return null;
  }

  Map<String, dynamic> _toMap() => {
        'profile': profile.toJson(),
        'destinations': destinations.map((e) => e.toJson()).toList(),
        'transports': transports.map((e) => e.toJson()).toList(),
        'notes': notes,
      };

  static List<Destination> _dests(Map<String, dynamic> j) =>
      ((j['destinations'] as List?) ?? [])
          .map((e) => Destination.fromJson((e as Map).cast<String, dynamic>()))
          .toList();

  static List<TransportRate> _trans(Map<String, dynamic> j) =>
      ((j['transports'] as List?) ?? [])
          .map((e) => TransportRate.fromJson((e as Map).cast<String, dynamic>()))
          .toList();

  void replaceFrom(String json) {
    final j = jsonDecode(json) as Map<String, dynamic>;
    profile = AgencyProfile.fromJson(
        (j['profile'] as Map?)?.cast<String, dynamic>() ?? {});
    destinations = _dests(j);
    transports = _trans(j);
    notes = ((j['notes'] as List?) ?? []).map((e) => e.toString()).toList();
  }

  /// Adds items that exist only in [cloudJson]. Local items win on conflict.
  void mergeFrom(String cloudJson) {
    final j = jsonDecode(cloudJson) as Map<String, dynamic>;
    for (final d in _dests(j)) {
      if (!destinations.any((x) => x.id == d.id)) destinations.add(d);
    }
    for (final t in _trans(j)) {
      if (!transports.any((x) => x.id == t.id)) transports.add(t);
    }
    for (final n in ((j['notes'] as List?) ?? [])) {
      if (!notes.contains(n.toString())) notes.add(n.toString());
    }
  }

  Future<void> load(String accountId, List<int> dek) async {
    _accountId = accountId;
    _dek = dek;
    profile = AgencyProfile();
    destinations = [];
    transports = [];
    notes = [];
    final raw = await Vault.read('data_$accountId');
    if (raw != null && raw.isNotEmpty) {
      final plain = await CryptoService.open(dek, raw);
      var ok = false;
      if (plain != null) {
        try {
          replaceFrom(utf8.decode(plain));
          ok = true;
        } catch (_) {}
      }
      // Never overwrite data we could not read: keep a copy.
      if (!ok) await Vault.write('data_bad_$accountId', raw);
    }
    notifyListeners();
  }

  Future<String> encryptedBlob() async =>
      CryptoService.seal(_dek!, utf8.encode(jsonEncode(_toMap())));

  /// Local save by the owner: marks the cloud copy as out of date.
  Future<void> save() async {
    final id = _accountId;
    if (id == null || _dek == null) return;
    await Vault.write('data_$id', await encryptedBlob());
    await Vault.write('dirty_$id', '1');
    notifyListeners();
    onLocalSave?.call();
  }

  /// Save after data arrived from the cloud (does not mark as changed).
  Future<void> saveFromSync() async {
    final id = _accountId;
    if (id == null || _dek == null) return;
    await Vault.write('data_$id', await encryptedBlob());
    notifyListeners();
  }

  void unload() {
    _accountId = null;
    _dek = null;
    profile = AgencyProfile();
    destinations = [];
    transports = [];
    notes = [];
    notifyListeners();
  }
}
